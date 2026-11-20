import AppKit
import Auth
import InnerTube
import PlayerEngine
import SwiftUI
import WebKit

/// Keeps the player web view in one invisible window the app owns, so playback does not depend on which windows are open.
@MainActor
final class PlayerWindow {
    private let window: NSWindow

    init(session: AuthSession, player: PlayerEngine) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isExcludedFromWindowsMenu = true
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces]
        window.contentView = NSHostingView(rootView: PlayerHostView(session: session, player: player))
        window.orderBack(nil)
    }
}

private struct PlayerHostView: View {
    let session: AuthSession
    let player: PlayerEngine

    var body: some View {
        PlayerHost(engine: player)
            .frame(width: 1, height: 1)
            .onChange(of: session.state.isSignedIn) { InnerTubeClient.resetGuestVisitor() }
            .onChange(of: session.authUserIndex, initial: true) { player.authUserIndex = $1 }
            .task(id: PlayerSession(session)) { await startPlayer() }
    }

    private func startPlayer() async {
        player.rate = { [session] videoId, status in
            guard case .signedIn(let cookies) = session.state else { throw InnerTubeError.signInRequired }
            let rating: Rating = switch status {
            case .like: .like
            case .dislike: .dislike
            case .indifferent: .indifferent
            }
            try await InnerTubeClient().rate(
                videoId: videoId, rating, credentials: Credentials(cookies: cookies, authUserIndex: session.authUserIndex))
        }
        switch PlayerSession(session) {
        case .off:
            player.stop()
            return
        case .guest, .account:
            await player.start(session.state)
        }
        #if DEBUG
        if let videoId = UserDefaults.standard.string(forKey: "debugVideoId") {
            player.load(videoId: videoId, playlistId: UserDefaults.standard.string(forKey: "debugPlaylistId"))
        }
        #endif
    }
}

// Tears the signed-in web view down as soon as sign-out starts; the wipe of the shared store may already be running.
private enum PlayerSession: Equatable {
    case guest, account, off

    @MainActor init(_ session: AuthSession) {
        switch session.state {
        case .keychainUnavailable: self = .off
        case .signedIn: self = session.isSigningOut ? .off : .account
        case .signedOut: self = .guest
        }
    }
}

struct PlayerHost: NSViewRepresentable {
    let engine: PlayerEngine

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        container.alphaValue = 0
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let webView = engine.webView
        if container.subviews.first === webView { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        guard let webView else { return }
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }
}
