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
    public var authUserIndex = 0

    @ObservationIgnored private var continuations: [UUID: AsyncStream<PlayerEvent>.Continuation] = [:]
    @ObservationIgnored private var songTask: Task<Void, Never>?
    @ObservationIgnored private var isEphemeral = true
    @ObservationIgnored private let isReachable: @Sendable (URL) async -> Bool
    @ObservationIgnored private let delegate = WebDelegate()
    @ObservationIgnored private static let log = Logger(subsystem: "dev.kruhlyk.redwave", category: "player")

    public convenience init() {
        self.init(isReachable: Self.headCheck)
    }

    init(isReachable: @escaping @Sendable (URL) async -> Bool) {
        self.isReachable = isReachable
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
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        songTask?.cancel()
        songTask = nil
        isReady = false
        song = nil
        elapsed = 0
        isPaused = true
    }

    public func load(videoId: String, playlistId: String?) {
        guard let webView else {
            Self.log.error("load ignored: player not started")
            return
        }
        guard let url = PlayerRules.watchURL(videoId: videoId, playlistId: playlistId, authUserIndex: isEphemeral ? 0 : authUserIndex) else {
            Self.log.error("load ignored: invalid id")
            return
        }
        webView.load(URLRequest(url: url))
    }

    func handle(_ message: BridgeMessage) -> PlayerEvent? {
        switch message {
        case .ready:
            isReady = true
            return emit(.ready)
        case .playback(let paused, let time):
            isPaused = paused
            elapsed = time
            return emit(.playbackChanged(isPaused: paused, elapsed: time))
        case .time(let time):
            elapsed = time
            return emit(.timeChanged(time))
        case .song(let incoming, let artworkWithQuery):
            guard incoming.videoId != song?.videoId else { return nil }
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
        emit(.songChanged(newSong))
    }

    @discardableResult
    private func emit(_ event: PlayerEvent) -> PlayerEvent {
        switch event {
        case .songChanged(let song):
            Self.log.info("songChanged id=\(song.videoId, privacy: .private(mask: .hash)) title=\(song.title, privacy: .private) artist=\(song.artist, privacy: .private)")
        case .timeChanged:
            break
        case .ready, .playbackChanged:
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

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        engine?.contentProcessTerminated()
    }
}
