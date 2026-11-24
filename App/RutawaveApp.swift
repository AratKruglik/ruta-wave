import Auth
import InnerTube
import PlayerEngine
import SwiftUI
import SystemKit

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
            RootView(session: app.session, nowPlaying: app.nowPlaying, toasts: app.toasts, network: app.network)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: Metrics.defaultWindowWidth, height: Metrics.defaultWindowHeight)
        .commands {
            SidebarCommands()
            AppCommands(nowPlaying: app.nowPlaying)
        }
        Settings { SettingsView() }
        #if DEBUG
        Window("Player Debug", id: "player-debug") { PlayerDebugView(player: app.player) }
        #endif
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let session: AuthSession
    let player: PlayerEngine
    let toasts: ToastCenter
    let nowPlaying: NowPlayingModel
    let systemNowPlaying: SystemNowPlaying
    let network = NetworkMonitor()
    private var playerWindow: PlayerWindow?

    override init() {
        let session = AuthSession()
        let player = PlayerEngine()
        let toasts = ToastCenter()
        self.session = session
        self.player = player
        self.toasts = toasts
        nowPlaying = NowPlayingModel(player: player, toasts: toasts, credentials: { session.credentials })
        let systemNowPlaying = SystemNowPlaying(send: { [nowPlaying] in nowPlaying.perform($0) })
        nowPlaying.albumChanged = { systemNowPlaying.setAlbum($1, for: $0) }
        self.systemNowPlaying = systemNowPlaying
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        playerWindow = PlayerWindow(session: session, player: player)
        network.start()
        Task { await nowPlaying.run() }
        Task { await systemNowPlaying.run(player.events()) }
    }
}
