import Auth
import InnerTube
import PlayerEngine
import SwiftUI

@main
struct RedwaveApp: App {
    @State private var session = AuthSession()
    @State private var player = PlayerEngine()

    init() {
        // SecItemDelete can block on a Keychain prompt for the old binary's item, so this must stay off the main actor.
        Task.detached(priority: .utility) { LegacyStores.remove() }
        Task.detached(priority: .utility) { await InnerTubeClient().refreshClientVersion() }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch session.state {
                case .signedOut:
                    GuestView(session: session)
                case .signedIn:
                    AccountView(session: session)
                case .keychainUnavailable:
                    VStack(spacing: 12) {
                        Text("Couldn't access the saved session")
                        Button("Try again") { session.restore() }
                        Button("Continue without signing in") { session.continueAsGuest() }
                    }
                }
            }
            .frame(minWidth: 520, minHeight: 640)
            .onChange(of: session.state.isSignedIn) { InnerTubeClient.resetGuestVisitor() }
            .background { PlayerHost(engine: player).frame(width: 1, height: 1) }
            .onChange(of: session.authUserIndex, initial: true) { player.authUserIndex = $1 }
            .task(id: PlayerSession(session)) { await startPlayer() }
        }
        #if DEBUG
        Window("Player Debug", id: "player-debug") { PlayerDebugView(player: player) }
        #endif
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
