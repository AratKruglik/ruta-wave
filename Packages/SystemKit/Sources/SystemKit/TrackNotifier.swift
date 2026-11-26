import Foundation
import PlayerEngine
import UniformTypeIdentifiers

/// The seam to `UNUserNotificationCenter`, which only works inside an app bundle.
public protocol NotificationPosting: Sendable {
    func authorizationStatus() async -> NotificationAuthorization
    func requestAuthorization() async -> Bool
    func post(identifier: String, title: String, body: String, attachmentURL: URL?) async
}

/// Posts one notification per announced track change. A fixed identifier makes each post replace the previous one.
@MainActor
public final class TrackNotifier {
    public static let identifier = "track-change"

    private let posting: any NotificationPosting
    private let loadArtwork: @Sendable (URL) async -> URL?
    private let isEnabled: @MainActor () -> Bool
    private let isFrontmost: @MainActor () -> Bool
    private var state = TrackNotificationState()
    private var postTask: Task<Void, Never>?

    public init(
        posting: any NotificationPosting,
        isEnabled: @escaping @MainActor () -> Bool,
        isFrontmost: @escaping @MainActor () -> Bool,
        loadArtwork: @escaping @Sendable (URL) async -> URL? = TrackNotifier.downloadArtwork
    ) {
        self.posting = posting
        self.isEnabled = isEnabled
        self.isFrontmost = isFrontmost
        self.loadArtwork = loadArtwork
    }

    public func run(_ events: AsyncStream<PlayerEvent>) async {
        for await event in events { handle(event) }
    }

    /// The track restored at launch counts as already announced.
    public func skipRestored(videoId: String) {
        state.announcedVideoId = videoId
    }

    /// For a notifier started mid-ad: the player sent its ad flag before this notifier was listening.
    public func markAdPlaying() {
        state.isAd = true
    }

    public func cancel() {
        postTask?.cancel()
        postTask = nil
    }

    func handle(_ event: PlayerEvent) {
        if case .stopped = event {
            postTask?.cancel()
            postTask = nil
        }
        let (next, song) = TrackNotificationRules.reduce(state, event)
        state = next
        guard let song else { return }
        postTask?.cancel()
        postTask = Task { await post(song) }
    }

    var currentPostTask: Task<Void, Never>? { postTask }

    func waitForPost() async {
        await postTask?.value
    }

    private func post(_ song: SongInfo) async {
        guard isEnabled(), !isFrontmost() else { return }
        var authorization = await posting.authorizationStatus()
        if authorization == .notDetermined {
            authorization = await posting.requestAuthorization() ? .authorized : .denied
        }
        guard !Task.isCancelled, authorization == .authorized else { return }
        let artwork = await song.artworkURL.flatMap { TrackNotificationRules.isAcceptableArtwork($0) ? $0 : nil }.asyncMap(loadArtwork)
        defer { artwork.map { try? FileManager.default.removeItem(at: $0) } }
        guard !Task.isCancelled, TrackNotificationRules.shouldPost(isEnabled: isEnabled(), isFrontmost: isFrontmost(), authorization: authorization)
        else { return }
        // shortcut: an ad flag that arrives after the artwork wait (about 2 s) cannot be seen, so one notification may name the content track.
        if state.isAd {
            state.pending = song
            return
        }
        await posting.post(identifier: Self.identifier, title: song.title, body: song.artist, attachmentURL: artwork)
    }

    private static let artworkSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 2
        return URLSession(configuration: configuration)
    }()

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
        ) async -> URLRequest? { nil }
    }

    /// `UNNotificationAttachment` rejects a file without an extension, so the image is saved with the one its MIME type names.
    public static let downloadArtwork: @Sendable (URL) async -> URL? = { url in
        guard TrackNotificationRules.isAcceptableArtwork(url) else { return nil }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        guard let (bytes, response) = try? await artworkSession.bytes(for: request, delegate: NoRedirects()),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let mimeType = http.mimeType, mimeType.lowercased().hasPrefix("image/") else { return nil }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > TrackNotificationRules.maxArtworkBytes { return nil }
            }
        } catch {
            return nil
        }
        guard TrackNotificationRules.isAcceptableImage(mimeType: mimeType, byteCount: data.count),
              let fileExtension = UTType(mimeType: mimeType)?.preferredFilenameExtension else { return nil }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("rutawave-artwork-\(UUID().uuidString).\(fileExtension)")
        do {
            try data.write(to: file)
            return file
        } catch {
            return nil
        }
    }
}

private extension Optional where Wrapped: Sendable {
    func asyncMap<T: Sendable>(_ transform: @Sendable (Wrapped) async -> T?) async -> T? {
        guard let self else { return nil }
        return await transform(self)
    }
}
