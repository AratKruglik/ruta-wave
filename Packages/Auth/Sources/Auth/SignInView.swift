import SwiftUI
import WebKit

public struct SignInView: View {
    let session: AuthSession
    @State private var attempt = 0
    @State private var loadFailed = false

    public init(session: AuthSession) {
        self.session = session
    }

    public var body: some View {
        SignInWebView(session: session, loadFailed: $loadFailed)
            .id(attempt)
            .overlay { if let message { errorOverlay(message) } }
    }

    private var message: String? {
        if session.signInError != nil { return "Couldn't save your session" }
        return loadFailed ? "Couldn't load the sign-in page" : nil
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message).font(.headline)
            Button(session.signInError != nil ? "Try again" : "Reload") {
                session.clearSignInError()
                loadFailed = false
                attempt += 1
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SignInWebView: NSViewRepresentable {
    let session: AuthSession
    @Binding var loadFailed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, loadFailed: $loadFailed)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.applicationNameForUserAgent = SignInRules.safariApplicationName
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.configuration.websiteDataStore.httpCookieStore.add(context.coordinator)
        context.coordinator.webView = webView
        webView.load(URLRequest(url: SignInRules.signInURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        private let session: AuthSession
        private let loadFailed: Binding<Bool>
        private var didComplete = false
        weak var webView: WKWebView?

        init(session: AuthSession, loadFailed: Binding<Bool>) {
            self.session = session
            self.loadFailed = loadFailed
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.targetFrame?.isMainFrame == false { return .allow }
            guard let url = navigationAction.request.url else { return .cancel }
            return SignInRules.isAllowedMainFrameNavigation(url) ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkSignIn()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            report(error)
        }

        nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor [weak self] in self?.checkSignIn() }
        }

        private func report(_ error: any Error) {
            let nsError = error as NSError
            let interrupted = nsError.domain == "WebKitErrorDomain" && nsError.code == 102
            if nsError.code == NSURLErrorCancelled || interrupted { return }
            loadFailed.wrappedValue = true
        }

        private func checkSignIn() {
            guard !didComplete, let webView, webView.url?.host?.lowercased() == "music.youtube.com" else { return }
            Task { [weak self, weak webView] in
                guard let webView else { return }
                let all = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                guard let self, !self.didComplete, self.isSignInActive,
                      SignInRules.isSignInComplete(mainFrameURL: webView.url, cookies: all) else { return }
                if self.session.completeSignIn(with: SignInRules.musicCookies(all)) {
                    self.didComplete = true
                }
            }
        }

        private var isSignInActive: Bool {
            if case .signedOut = session.state { true } else { false }
        }
    }
}
