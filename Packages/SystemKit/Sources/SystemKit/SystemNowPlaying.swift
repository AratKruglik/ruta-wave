import AppKit
import Foundation
import MediaPlayer
import os
import PlayerEngine

@MainActor
public final class SystemNowPlaying {
    private nonisolated static let log = Logger(subsystem: "dev.kruhlyk.rutawave", category: "nowplaying")

    private let send: @MainActor (PlayerCommand) -> Void
    private let publish: @MainActor ([String: Any]?, MPNowPlayingPlaybackState) -> Void
    private let fetchArtwork: @Sendable (URL) async -> Data?
    private var state: NowPlayingState?
    private var artwork: (videoId: String, image: MPMediaItemArtwork)?
    private var artworkTask: Task<Void, Never>?
    private var registered = false

    public convenience init(send: @escaping @MainActor (PlayerCommand) -> Void) {
        self.init(send: send, publish: Self.publishToSystem, fetchArtwork: Self.fetchFromNetwork)
    }

    init(
        send: @escaping @MainActor (PlayerCommand) -> Void,
        publish: @escaping @MainActor ([String: Any]?, MPNowPlayingPlaybackState) -> Void,
        fetchArtwork: @escaping @Sendable (URL) async -> Data?
    ) {
        self.send = send
        self.publish = publish
        self.fetchArtwork = fetchArtwork
    }

    public func run(_ events: AsyncStream<PlayerEvent>) async {
        registerCommands()
        for await event in events { handle(event) }
    }

    /// The album arrives after the details load, so a late answer for a previous track is dropped.
    public func setAlbum(_ album: String?, for videoId: String) {
        guard state?.videoId == videoId, state?.album != album else { return }
        state?.album = album
        push()
    }

    func handle(_ event: PlayerEvent) {
        let previousId = state?.videoId
        let (next, shouldPublish) = NowPlayingRules.reduce(state, event)
        state = next
        if next?.videoId != previousId { startArtwork(for: next) }
        if shouldPublish { push() }
    }

    func perform(_ command: PlayerCommand) -> MPRemoteCommandHandlerStatus {
        guard let state else { return .noActionableNowPlayingItem }
        if state.isAd && PlayerRules.isRefusedDuringAd(command) { return .commandFailed }
        send(command)
        return .success
    }

    private func push() {
        guard let state else {
            publish(nil, .stopped)
            return
        }
        var info = NowPlayingRules.info(state)
        if let artwork, artwork.videoId == state.videoId { info[MPMediaItemPropertyArtwork] = artwork.image }
        publish(info, NowPlayingRules.playbackState(state))
    }

    private func startArtwork(for state: NowPlayingState?) {
        artworkTask?.cancel()
        artworkTask = nil
        artwork = nil
        guard let state, let url = state.artworkURL, PlayerRules.isAllowedArtworkHost(url) else { return }
        let videoId = state.videoId
        let fetch = fetchArtwork
        artworkTask = Task { [weak self] in
            guard let data = await fetch(url), let image = Self.artwork(from: data) else { return }
            guard !Task.isCancelled, let self, self.state?.videoId == videoId else { return }
            artwork = (videoId, image)
            push()
        }
    }

    nonisolated static func artwork(from data: Data) -> MPMediaItemArtwork? {
        guard let size = NSImage(data: data)?.size, size.width > 0, size.height > 0 else { return nil }
        return MPMediaItemArtwork(boundsSize: size) { _ in NSImage(data: data) ?? NSImage() }
    }

    private static let publishToSystem: @MainActor ([String: Any]?, MPNowPlayingPlaybackState) -> Void = { info, playback in
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = playback
    }

    private nonisolated static let artworkByteLimit = 5 * 1024 * 1024

    private nonisolated static let artworkSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration, delegate: ArtworkRedirectGuard(), delegateQueue: nil)
    }()

    private nonisolated static let fetchFromNetwork: @Sendable (URL) async -> Data? = { url in
        do {
            let (bytes, response) = try await artworkSession.bytes(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                http.mimeType?.hasPrefix("image/") == true,
                response.expectedContentLength <= artworkByteLimit
            else { return nil }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > artworkByteLimit { return nil }
            }
            return data
        } catch {
            let nsError = error as NSError
            log.error("artwork fetch failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
            return nil
        }
    }

    private final class ArtworkRedirectGuard: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(request.url.map(PlayerRules.isAllowedArtworkHost) == true ? request : nil)
        }
    }

    private func registerCommands() {
        guard !registered else { return }
        registered = true
        Self.install(on: self)
    }

    // Built in a nonisolated context: MediaPlayer calls these handlers off the main actor, and a closure
    // formed in a main-actor method would trap on that call.
    private nonisolated static func install(on target: SystemNowPlaying) {
        let center = MPRemoteCommandCenter.shared()
        let simple: [(MPRemoteCommand, PlayerCommand)] = [
            (center.playCommand, .play), (center.pauseCommand, .pause), (center.togglePlayPauseCommand, .togglePlay),
            (center.nextTrackCommand, .next), (center.previousTrackCommand, .previous),
        ]
        for (remote, command) in simple {
            remote.addTarget { [weak target] _ in target?.onMain { $0.perform(command) } ?? .commandFailed }
        }
        center.changePlaybackPositionCommand.addTarget { [weak target] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            return target?.onMain { $0.perform(.seek(to: time)) } ?? .commandFailed
        }
        let skips = [(center.skipForwardCommand, NowPlayingRules.skipInterval), (center.skipBackwardCommand, -NowPlayingRules.skipInterval)]
        for (remote, delta) in skips {
            remote.preferredIntervals = [NSNumber(value: NowPlayingRules.skipInterval)]
            remote.addTarget { [weak target] _ in target?.onMain { $0.perform(.skip(by: delta)) } ?? .commandFailed }
        }
    }

    private nonisolated func onMain(_ body: @escaping @MainActor @Sendable (SystemNowPlaying) -> MPRemoteCommandHandlerStatus) -> MPRemoteCommandHandlerStatus {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { body(self) }
        }
        DispatchQueue.main.async { MainActor.assumeIsolated { _ = body(self) } }
        return .success
    }
}
