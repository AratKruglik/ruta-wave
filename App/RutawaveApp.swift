import Auth
import InnerTube
import PlayerEngine
import SwiftUI

@main
struct RutawaveApp: App {
    @NSApplicationDelegateAdaptor private var app: AppDelegate

    init() {
        // SecItemDelete can block on a Keychain prompt for the old binary's item, so this must stay off the main actor.
        Task.detached(priority: .utility) { LegacyStores.remove() }
        Task.detached(priority: .utility) { await InnerTubeClient().refreshClientVersion() }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch app.session.state {
                case .signedOut:
                    GuestView(session: app.session)
                case .signedIn:
                    AccountView(session: app.session)
                case .keychainUnavailable:
                    VStack(spacing: 12) {
                        Text("Couldn't access the saved session")
                        Button("Try again") { app.session.restore() }
                        Button("Continue without signing in") { app.session.continueAsGuest() }
                    }
                }
            }
            .frame(minWidth: 520, minHeight: 640)
        }
        #if DEBUG
        Window("Player Debug", id: "player-debug") { PlayerDebugView(player: app.player) }
        #endif
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let session = AuthSession()
    let player = PlayerEngine()
    private var playerWindow: PlayerWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        playerWindow = PlayerWindow(session: session, player: player)
    }
}
