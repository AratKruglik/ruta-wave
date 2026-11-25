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
    @ObservationIgnored var queueOffset = 0
    public private(set) var isAd = false
    public private(set) var isBuffering = false
    public private(set) var authUserIndex = 0
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
    @ObservationIgnored var resumeQueue: [String] = []
    /// Set by `resume`: the page autoplays every load, so playback is paused until the user starts it.
    @ObservationIgnored var holdsPause = false
    // InnerTube writes the like; the hidden page keeps reporting its stale status for that track.
    @ObservationIgnored var ratedLike: (videoId: String, status: LikeStatus)?
    @ObservationIgnored var watchdog: Task<Void, Never>?
    @ObservationIgnored var committedAt: ContinuousClock.Instant?
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var nowPlaying: NowPlayingInfo?
    @ObservationIgnored private let delegate = WebDelegate()
    @ObservationIgnored private static let log = Logger(subsystem: "dev.kruhlyk.rutawave", category: "player")

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

    /// Starts the player for a session. A switch to another signed-in account stops the old one first,
    /// so its track does not stay in Control Centre or resume under the new account.
    public func start(_ state: AuthSession.State, authUserIndex: Int = 0) async {
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
        let reuses = webView != nil && PlayerRules.reusesPlayer(
            running: (isEphemeral, self.authUserIndex), wanted: (ephemeral, authUserIndex))
        self.authUserIndex = authUserIndex
        if reuses { return }
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
        resumeQueue = []
        holdsPause = false
        ratedLike = nil
        committedAt = nil
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
        queueOffset = 0
        isAd = false
        isBuffering = false
        emit(.stopped)
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
        resumeQueue = []
        holdsPause = false
        navigate(to: url, in: webView)
    }

    /// Like `load`, but the track stays paused at `time` instead of playing from the start.
    public func resume(videoId: String, playlistId: String?, at time: TimeInterval) {
        load(videoId: videoId, playlistId: playlistId)
        guard target?.videoId == videoId else { return }
        if time.isFinite, time > 0 { resumeAt = time }
        holdsPause = true
    }

    public func send(_ command: PlayerCommand) {
        switch command {
        case .load(let videoId, let playlistId):
            load(videoId: videoId, playlistId: playlistId)
            return
        case .setLike(let status):
            setLike(status)
            return
        case .resume(let videoId, let playlistId, let time):
            resume(videoId: videoId, playlistId: playlistId, at: time)
            return
        case .recover:
            recover()
            return
        case .play, .togglePlay, .next, .previous, .playQueueItem:
            holdsPause = false
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
        guard let call = PlayerRules.bridgeCall(for: command, queue: queue, offset: queueOffset) else {
            Self.log.info("command refused: invalid arguments")
            return
        }
        run(call, in: webView)
    }

    private func run(_ call: (action: String, args: [Any]), in webView: WKWebView) {
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
            // The failed navigation's own watchdog would otherwise report a second error 15 s later.
            watchdog?.cancel()
            return nil
        }
        attempts += 1
        return PlayerRules.loadURL(videoId: target.videoId, playlistId: target.playlistId, authUserIndex: isEphemeral ? nil : authUserIndex)
    }

    /// A page that stalled and came back resumes on its own; one that gave up is reloaded where it was.
    private func recover() {
        guard target != nil else { return }
        if let webView, isReady, webView.url?.host()?.lowercased() == PlayerRules.playerHost {
            send(.play)
        } else {
            prepareRecovery()
            reload()
        }
    }

    /// Not `load`, which would drop the position and queue the reload restores.
    func prepareRecovery() {
        snapshotForRestore()
        attempts = 0
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
            if holdsPause { pauseHeldPlayback() }
            publishNowPlaying(nowPlaying)
            return event
        case .playback(let paused, let time):
            if holdsPause {
                if !paused {
                    pauseHeldPlayback()
                } else if resumeAt == nil, song?.videoId == target?.videoId {
                    // The resumed track is committed, sought and paused: from here on the user decides.
                    holdsPause = false
                }
            }
            isPaused = paused
            elapsed = time
            if !isAd { position = time }
            return emit(.playbackChanged(isPaused: paused, elapsed: time))
        case .time(let time):
            elapsed = time
            if !isAd { position = time }
            if attempts > 0, resumeAt == nil, let committedAt, ContinuousClock.now - committedAt >= PlayerRules.stablePlayback {
                attempts = 0
            }
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
        case .queue(let items, let offset):
            queue = items
            queueOffset = offset
            return emit(.queueChanged(items))
        case .ad(let playing):
            isAd = playing
            return emit(.adChanged(playing))
        case .buffering(let buffering):
            isBuffering = buffering
            return nil
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

    private func pauseHeldPlayback() {
        guard let webView, isReady, let call = PlayerRules.bridgeCall(for: .pause, queue: queue) else { return }
        run(call, in: webView)
    }

    func commit(_ newSong: SongInfo) {
        song = newSong
        elapsed = 0
        committedAt = .now
        watchdog?.cancel()
        if let resume = resumeAt {
            resumeAt = nil
            if newSong.videoId == target?.videoId { send(.seek(to: resume)) }
            if !resumeQueue.isEmpty, let webView, isReady { run(("append", [resumeQueue]), in: webView) }
            resumeQueue = []
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
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.mediaSessionNeutraliser, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if let script = Self.resource("bridge") {
            configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        if let script = Self.resource("nowplaying") {
            configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Self.nowPlayingWorld))
        }
        configuration.userContentController.add(delegate, name: "player")
        configuration.userContentController.add(delegate, contentWorld: Self.nowPlayingWorld, name: "nowPlaying")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = delegate
        view.uiDelegate = delegate
        #if DEBUG
        view.isInspectable = true
        #endif
        return view
    }

    // The page's Media Session made WebKit publish a second Now Playing entry; SystemKit owns it (risk 5).
    // Runs at document start so the page never registers handlers; navigator.mediaSession stays defined.
    private static let mediaSessionNeutraliser = """
        (() => {
          const session = navigator.mediaSession;
          if (!session) return;
          const proto = Object.getPrototypeOf(session);
          for (const action of ['play', 'pause', 'stop', 'previoustrack', 'nexttrack', 'seekto', 'seekbackward', 'seekforward']) {
            try { proto.setActionHandler.call(session, action, null); } catch {}
          }
          proto.setActionHandler = () => {};
          proto.setPositionState = () => {};
          Object.defineProperty(proto, 'metadata', { get: () => null, set: () => {}, configurable: false });
        })();
        """

    // WebKit publishes its own Now Playing entry for the page's media element and offers no way to remove it,
    // so the app drives that entry's Media Session from a world the page cannot reach (risk 5).
    private static let nowPlayingWorld = WKContentWorld.world(name: "rutawave-now-playing")

    private static func resource(_ name: String) -> String? {
        do {
            guard let url = Bundle.module.url(forResource: name, withExtension: "js") else {
                log.fault("\(name, privacy: .public).js missing from bundle")
                return nil
            }
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            log.fault("\(name, privacy: .public).js unreadable: \(error, privacy: .public)")
            return nil
        }
    }

    /// Kept and re-sent after each page load, since a new document starts with an empty Media Session.
    public func publishNowPlaying(_ info: NowPlayingInfo?) {
        nowPlaying = info
        guard let webView, isReady else { return }
        Task {
            do {
                _ = try await webView.callAsyncJavaScript(
                    "window.__nowPlaying?.update(info)", arguments: PlayerRules.nowPlayingArguments(info), in: nil,
                    contentWorld: Self.nowPlayingWorld)
            } catch {
                Self.log.error("now playing update failed: \((error as NSError).domain, privacy: .public) \((error as NSError).code, privacy: .public)")
            }
        }
    }

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

    fileprivate func handleNowPlayingScript(_ message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard PlayerRules.isTrustedMessage(
            isMainFrame: message.frameInfo.isMainFrame, scheme: origin.protocol, host: origin.host, port: origin.port),
            let command = PlayerRules.remoteCommand(from: message.body) else { return }
        emit(.remoteCommand(command))
    }

    fileprivate func policy(for action: WKNavigationAction) -> WKNavigationActionPolicy {
        if action.targetFrame?.isMainFrame == false { return .allow }
        if PlayerRules.isAllowedMainFrameNavigation(action.request.url) { return .allow }
        Self.log.info("blocked main-frame host=\(action.request.url?.host() ?? "?", privacy: .public)")
        return .cancel
    }

    func navigationCommitted() {
        isReady = false
        isBuffering = false
        clearAd()
    }

    // A new document starts with bridge.js `adShowing = false` and posts only edges, so an ad cut off by a load never ends.
    private func clearAd() {
        guard isAd else { return }
        isAd = false
        emit(.adChanged(false))
    }

    fileprivate func contentProcessTerminated() {
        Self.log.error("web content process terminated")
        isReady = false
        snapshotForRestore()
        clearAd()
        isBuffering = false
        emit(.error(.contentProcessCrashed))
        reload()
    }

    /// A crash before the previous restore committed would see the reloaded page's position and queue, not the user's.
    func snapshotForRestore() {
        guard resumeAt == nil else { return }
        resumeAt = position
        resumeQueue = PlayerRules.upcomingVideoIds(queue)
        // The tail is re-added by hand, so reloading the playlist as well would put its tracks ahead of the user's queue.
        if !resumeQueue.isEmpty { target?.playlistId = nil }
    }

    fileprivate func navigationFailed(_ error: any Error) {
        guard !PlayerRules.isIgnorableNavigationError(error as NSError) else { return }
        Self.log.error("navigation failed: \((error as NSError).domain, privacy: .public) \((error as NSError).code, privacy: .public)")
        emit(.error(.pageLoadFailed))
        guard let webView else { return }
        watchdog?.cancel()
        let generation = loadGeneration
        let delay = PlayerRules.failedLoadRetryDelay
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.webView === webView, self.loadGeneration == generation else { return }
            self.reload()
        }
    }
}

@MainActor
private final class WebDelegate: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var engine: PlayerEngine?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "nowPlaying" {
            engine?.handleNowPlayingScript(message)
        } else {
            engine?.handleScript(message)
        }
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
