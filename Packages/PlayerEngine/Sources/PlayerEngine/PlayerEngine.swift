import Auth
import Foundation
import Observation
import OSLog
import WebKit

@MainActor @Observable
public final class PlayerEngine {
    public private(set) var song: SongInfo?
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var isPaused = true
    public private(set) var isReady = false
    public private(set) var webView: WKWebView?
    public private(set) var volume = 1.0
    public private(set) var isMuted = false
    public private(set) var like = LikeStatus.indifferent
    public private(set) var repeatMode = RepeatMode.off
    public private(set) var isShuffled = false
    public private(set) var queue: [QueueItem] = []
    public private(set) var isAd = false
    public var authUserIndex = 0
    /// Set by the app: the engine has no InnerTube dependency, so a like is written through this closure.
    @ObservationIgnored public var rate: (@MainActor (_ videoId: String, _ status: LikeStatus) async throws -> Void)?

    @ObservationIgnored private var continuations: [UUID: AsyncStream<PlayerEvent>.Continuation] = [:]
    @ObservationIgnored private var songTask: Task<Void, Never>?
    @ObservationIgnored var isEphemeral = true
    @ObservationIgnored private let isReachable: @Sendable (URL) async -> Bool
    @ObservationIgnored private let playerTimeout: Duration
    @ObservationIgnored var target: (videoId: String, playlistId: String?)?
    @ObservationIgnored var position: TimeInterval = 0
    @ObservationIgnored var attempts = 0
    @ObservationIgnored var resumeAt: TimeInterval?
    // Every page load brings back the volume the page's player bar stored, not the one set through the player.
    @ObservationIgnored var requestedVolume: Double?
    // InnerTube writes the like; the hidden page keeps reporting its stale status for that track.
    @ObservationIgnored var ratedLike: (videoId: String, status: LikeStatus)?
    @ObservationIgnored var watchdog: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private let delegate = WebDelegate()
    @ObservationIgnored private static let log = Logger(subsystem: "dev.kruhlyk.redwave", category: "player")

    public convenience init() {
        self.init(isReachable: Self.headCheck)
    }

    init(isReachable: @escaping @Sendable (URL) async -> Bool, playerTimeout: Duration = PlayerRules.playerTimeout) {
        self.isReachable = isReachable
        self.playerTimeout = playerTimeout
        delegate.engine = self
    }

    public func events() -> AsyncStream<PlayerEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<PlayerEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[id] = nil }
        }
        return stream
    }

    private static let terminationReason = "Player web view is active"

    public func start(_ state: AuthSession.State) async {
        let ephemeral: Bool
        let cookies: [HTTPCookie]
        switch state {
        case .signedOut:
            (ephemeral, cookies) = (true, [])
        case .signedIn(let restored):
            (ephemeral, cookies) = (false, restored)
        case .keychainUnavailable:
            stop()
            return
        }
        if webView != nil, isEphemeral == ephemeral { return }
        stop()

        let store = ephemeral ? WKWebsiteDataStore.nonPersistent() : WKWebsiteDataStore.default()
        let view = makeWebView(store: store)
        // Without this, macOS terminates the app ~10 s after the last window closes and playback dies with it.
        ProcessInfo.processInfo.disableAutomaticTermination(Self.terminationReason)
        webView = view
        isEphemeral = ephemeral
        if !ephemeral {
            // Cookies the web view already holds are newer than the Keychain copies, so restore only into an empty store.
            let existing = await store.httpCookieStore.allCookies()
            guard webView === view else { return }
            if !SignInRules.musicCookies(existing).contains(where: { $0.name == "SAPISID" }) {
                for cookie in cookies {
                    guard webView === view, !Task.isCancelled else { return }
                    await store.httpCookieStore.setCookie(cookie)
                }
                guard webView === view else { return }
            }
        }
    }

    public func stop() {
        if webView != nil { ProcessInfo.processInfo.enableAutomaticTermination(Self.terminationReason) }
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        songTask?.cancel()
        songTask = nil
        watchdog?.cancel()
        watchdog = nil
        target = nil
        resumeAt = nil
        ratedLike = nil
        attempts = 0
        position = 0
        isReady = false
        song = nil
        elapsed = 0
        isPaused = true
        volume = 1
        isMuted = false
        like = .indifferent
        repeatMode = .off
        isShuffled = false
        queue = []
        isAd = false
    }

    public func load(videoId: String, playlistId: String?) {
        guard let webView else {
            Self.log.error("load ignored: player not started")
            return
        }
        guard let url = PlayerRules.loadURL(videoId: videoId, playlistId: playlistId, authUserIndex: isEphemeral ? nil : authUserIndex) else {
            Self.log.error("load ignored: invalid id")
            return
        }
        target = (videoId, playlistId)
        attempts = 0
        resumeAt = nil
        navigate(to: url, in: webView)
    }

    public func send(_ command: PlayerCommand) {
        switch command {
        case .load(let videoId, let playlistId):
            load(videoId: videoId, playlistId: playlistId)
            return
        case .setLike(let status):
            setLike(status)
            return
        case .setVolume(let level) where level.isFinite:
            requestedVolume = min(max(level, 0), 1)
        default:
            break
        }
        guard let webView, isReady, webView.url?.host()?.lowercased() == PlayerRules.playerHost else {
            Self.log.info("command ignored: player not ready")
            return
        }
        if isAd, PlayerRules.isRefusedDuringAd(command) {
            Self.log.info("command ignored: ad is playing")
            return
        }
        guard let call = PlayerRules.bridgeCall(for: command, queue: queue) else {
            Self.log.info("command refused: invalid arguments")
            return
        }
        Task {
            do {
                let result = try await webView.callAsyncJavaScript(
                    "return window.__bridge.run(action, args)",
                    arguments: ["action": call.action, "args": call.args], in: nil, contentWorld: .page)
                if result as? Bool != true { Self.log.info("page refused \(call.action, privacy: .public)") }
            } catch {
                Self.log.error("page call \(call.action, privacy: .public) failed: \((error as NSError).domain, privacy: .public) \((error as NSError).code, privacy: .public)")
            }
        }
    }

    private func setLike(_ status: LikeStatus) {
        guard !isEphemeral, let rate, let videoId = song?.videoId else {
            emit(.error(.signInRequired))
            return
        }
        Task {
            do {
                try await rate(videoId, status)
                ratedLike = (videoId, status)
                guard song?.videoId == videoId else { return }
                like = status
                emit(.likeChanged(status))
            } catch {
                Self.log.error("rate failed: \((error as NSError).domain, privacy: .public) \((error as NSError).code, privacy: .public)")
            }
        }
    }

    private func navigate(to url: URL, in webView: WKWebView) {
        webView.load(URLRequest(url: url))
        watchdog?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let timeout = playerTimeout
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.webView === webView, self.loadGeneration == generation else { return }
            self.emit(.error(.playerTimeout))
            self.reload()
        }
    }

    func nextRecoveryURL() -> URL? {
        guard attempts < PlayerRules.maxReloadAttempts, let target else {
            Self.log.error("recovery gave up")
            return nil
        }
        attempts += 1
        return PlayerRules.loadURL(videoId: target.videoId, playlistId: target.playlistId, authUserIndex: isEphemeral ? nil : authUserIndex)
    }

    private func reload() {
        guard let webView, let url = nextRecoveryURL() else { return }
        navigate(to: url, in: webView)
    }

    func handle(_ message: BridgeMessage) -> PlayerEvent? {
        switch message {
        case .ready:
            isReady = true
            let event = emit(.ready)
            if let requestedVolume { send(.setVolume(requestedVolume)) }
            return event
        case .playback(let paused, let time):
            isPaused = paused
            elapsed = time
            if !isAd { position = time }
            return emit(.playbackChanged(isPaused: paused, elapsed: time))
        case .time(let time):
            elapsed = time
            if !isAd { position = time }
            return emit(.timeChanged(time))
        case .volume(let level, let muted):
            volume = level
            isMuted = muted
            return emit(.volumeChanged(volume: level, isMuted: muted))
        case .like(let reported, let videoId):
            let status = ratedLike.flatMap { $0.videoId == videoId ? $0.status : nil } ?? reported
            // The page re-reports the like status on every ready and track change, not only when it changes.
            guard status != like else { return nil }
            like = status
            return emit(.likeChanged(status))
        case .repeatMode(let mode):
            repeatMode = mode
            return emit(.repeatChanged(mode))
        case .shuffle(let enabled):
            isShuffled = enabled
            return emit(.shuffleChanged(enabled))
        case .queue(let items):
            queue = items
            return emit(.queueChanged(items))
        case .ad(let playing):
            isAd = playing
            return emit(.adChanged(playing))
        case .unavailable(let videoId):
            watchdog?.cancel()
            return emit(.error(.unavailable(videoId: videoId)))
        case .song(let incoming, let artworkWithQuery):
            if incoming.videoId == song?.videoId, resumeAt == nil {
                // Reloading the current track: the player is up, so the load is done even though the song is unchanged.
                // The attempt count stays: the page reports the same song several times, which would undo the crash-loop cap.
                watchdog?.cancel()
                return nil
            }
            songTask?.cancel()
            let isReachable = isReachable
            songTask = Task { [weak self] in
                let artwork = await PlayerRules.resolveArtwork(
                    stripped: incoming.artworkURL, original: artworkWithQuery, isReachable: isReachable)
                guard !Task.isCancelled else { return }
                self?.commit(incoming.with(artworkURL: artwork, elapsed: 0, isPaused: self?.isPaused ?? true))
            }
            return nil
        }
    }

    func commit(_ newSong: SongInfo) {
        song = newSong
        elapsed = 0
        watchdog?.cancel()
        if let resume = resumeAt {
            resumeAt = nil
            if newSong.videoId == target?.videoId { send(.seek(to: resume)) }
        } else {
            attempts = 0
        }
        target = (newSong.videoId, newSong.playlistId)
        emit(.songChanged(newSong))
    }

    @discardableResult
    private func emit(_ event: PlayerEvent) -> PlayerEvent {
        switch event {
        case .songChanged(let song):
            Self.log.info("songChanged id=\(song.videoId, privacy: .private(mask: .hash)) title=\(song.title, privacy: .private) artist=\(song.artist, privacy: .private)")
        case .timeChanged, .volumeChanged:
            break
        case .queueChanged(let items):
            Self.log.info("queueChanged count=\(items.count, privacy: .public)")
        case .error(.unavailable(let videoId)):
            Self.log.info("error unavailable id=\(videoId, privacy: .private(mask: .hash))")
        default:
            Self.log.info("\(String(describing: event), privacy: .public)")
        }
        for continuation in continuations.values { continuation.yield(event) }
        return event
    }

    private func makeWebView(store: WKWebsiteDataStore) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.applicationNameForUserAgent = SignInRules.safariApplicationName
        configuration.preferences.inactiveSchedulingPolicy = .none
        if let script = Self.bridgeSource {
            configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        configuration.userContentController.add(delegate, name: "player")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = delegate
        view.uiDelegate = delegate
        #if DEBUG
        view.isInspectable = true
        #endif
        return view
    }

    private static let bridgeSource: String? = {
        do {
            guard let url = Bundle.module.url(forResource: "bridge", withExtension: "js") else {
                log.fault("bridge.js missing from bundle")
                return nil
            }
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            log.fault("bridge.js unreadable: \(error, privacy: .public)")
            return nil
        }
    }()

    private static let headCheck: @Sendable (URL) async -> Bool = { url in
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "HEAD"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        guard let (_, response) = try? await URLSession(configuration: configuration).data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    fileprivate func handleScript(_ message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard PlayerRules.isTrustedMessage(
            isMainFrame: message.frameInfo.isMainFrame, scheme: origin.protocol, host: origin.host, port: origin.port),
            let decoded = BridgeMessage.decode(message.body) else { return }
        _ = handle(decoded)
    }

    fileprivate func policy(for action: WKNavigationAction) -> WKNavigationActionPolicy {
        if action.targetFrame?.isMainFrame == false { return .allow }
        if PlayerRules.isAllowedMainFrameNavigation(action.request.url) { return .allow }
        Self.log.info("blocked main-frame host=\(action.request.url?.host() ?? "?", privacy: .public)")
        return .cancel
    }

    fileprivate func navigationCommitted() {
        isReady = false
    }

    fileprivate func contentProcessTerminated() {
        Self.log.error("web content process terminated")
        isReady = false
        resumeAt = position
        isAd = false
        emit(.error(.contentProcessCrashed))
        reload()
    }

    fileprivate func navigationFailed(_ error: any Error) {
        guard !PlayerRules.isIgnorableNavigationError(error as NSError) else { return }
        Self.log.error("navigation failed: \((error as NSError).domain, privacy: .public) \((error as NSError).code, privacy: .public)")
        emit(.error(.pageLoadFailed))
    }
}

@MainActor
private final class WebDelegate: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var engine: PlayerEngine?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        engine?.handleScript(message)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        engine?.policy(for: navigationAction) ?? .cancel
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        engine?.navigationCommitted()
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        engine?.navigationFailed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        engine?.navigationFailed(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        engine?.contentProcessTerminated()
    }
}
