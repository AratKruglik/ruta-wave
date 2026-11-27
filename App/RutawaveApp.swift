import Auth
import AppSettings
import InnerTube
import PlayerEngine
import Plugins
import SwiftUI
import SystemKit
import UserNotifications

@main
struct RutawaveApp: App {
    @NSApplicationDelegateAdaptor private var app: AppDelegate
    @Environment(\.openWindow) private var openWindow

    init() {
        // SecItemDelete can block on a Keychain prompt for the old binary's item, so this must stay off the main actor.
        Task.detached(priority: .utility) { LegacyStores.remove() }
        Task.detached(priority: .utility) { await InnerTubeClient().refreshClientVersion() }
    }

    var body: some Scene {
        // The delegate needs the action to reopen the window with none open, and only a scene can hand it out.
        let _ = app.openMainWindow = { openWindow(id: AppDelegate.mainWindowId) }
        let _ = app.openMiniPlayer = { openWindow(id: AppDelegate.miniPlayerWindowId) }
        WindowGroup(id: AppDelegate.mainWindowId) {
            RootView(session: app.session, nowPlaying: app.nowPlaying, toasts: app.toasts, network: app.network, links: app.links)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: Metrics.defaultWindowWidth, height: Metrics.defaultWindowHeight)
        .commands {
            SidebarCommands()
            AppCommands(nowPlaying: app.nowPlaying, showMainWindow: { [app] in app.showMainWindow() })
        }
        .handlesExternalEvents(matching: [])
        Window("Mini Player", id: AppDelegate.miniPlayerWindowId) { MiniPlayerView(nowPlaying: app.nowPlaying) }
            .windowResizability(.contentSize)
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .handlesExternalEvents(matching: [])
        Settings { SettingsView(session: app.session, plugins: app.plugins) }
        #if DEBUG
        Window("Player Debug", id: "player-debug") { PlayerDebugView(player: app.player) }
            .handlesExternalEvents(matching: [])
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
    let plugins: PluginRegistry
    let notifications: NotificationsPlugin
    let network = NetworkMonitor()
    let links = LinkInbox()
    static let mainWindowId = "main"
    static let miniPlayerWindowId = "mini-player"
    var openMainWindow: (() -> Void)?
    var openMiniPlayer: (() -> Void)?
    private var statusMenu: StatusMenu?
    private var playerWindow: PlayerWindow?

    override init() {
        let session = AuthSession()
        let player = PlayerEngine()
        let toasts = ToastCenter()
        self.session = session
        self.player = player
        self.toasts = toasts
        nowPlaying = NowPlayingModel(player: player, toasts: toasts, credentials: { session.credentials })
        let systemNowPlaying = SystemNowPlaying(
            send: { [nowPlaying] in nowPlaying.perform($0) }, publish: { [player] in player.publishNowPlaying($0) })
        nowPlaying.albumChanged = { systemNowPlaying.setAlbum($1, for: $0) }
        self.systemNowPlaying = systemNowPlaying
        NotificationsPlugin.migrateLegacySetting()
        let notifications = NotificationsPlugin(posting: UserNotificationPosting(), isFrontmost: { NSApp.isActive })
        self.notifications = notifications
        plugins = PluginRegistry(plugins: [notifications], player: player)
        super.init()
        statusMenu = StatusMenu(
            nowPlaying: nowPlaying, showMainWindow: { [weak self] in self?.showMainWindow() },
            showMiniPlayer: { [weak self] in self?.showMiniPlayer() })
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        applyPresentation()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let preferences = Preferences()
        // The single-account migration signs out without an isSignedIn change, so no observer clears the old account's track.
        if session.droppedLegacySession { preferences.lastPlayback = nil }
        if preferences.resumeOnStart, let videoId = preferences.lastPlayback?.videoId {
            notifications.skipRestored(videoId: videoId)
        }
        UNUserNotificationCenter.current().delegate = self
        playerWindow = PlayerWindow(
            session: session, player: player,
            onStarted: { [nowPlaying, session] in
                // A migration after "Try again" or "Continue without signing in" runs after launch.
                if session.droppedLegacySession { Preferences().lastPlayback = nil }
                nowPlaying.resumeLastSession()
            },
            onIdentityChange: { [nowPlaying, toasts] in
                nowPlaying.resetAccountState()
                toasts.reset()
            })
        network.start()
        Task { await nowPlaying.run() }
        Task { await systemNowPlaying.run(player.events()) }
        plugins.sync()
        Task {
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                applyPresentation(revealsOnPolicyChange: true)
                plugins.sync()
            }
        }
    }

    // The Mini Player counts as a visible window, so this ignores `hasVisibleWindows`; false stops a second default reopen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        NSApp.activationPolicy() == .accessory ? nil : statusMenu?.dockMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        nowPlaying.savePosition()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let link = urls.lazy.compactMap(Self.link).first else { return }
        switch link {
        case .play(let target): nowPlaying.openLink(target)
        case .openInBrowser(let url): NSWorkspace.shared.open(url)
        case .section, .route:
            links.pending = link
            showMainWindow()
        }
    }

    private static let maxWeblocSize = 64 * 1024

    private static func link(from url: URL) -> MusicLink? {
        guard url.isFileURL else { return MusicLink(url) }
        let file = url.resolvingSymlinksInPath()
        guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxWeblocSize + 1), data.count <= maxWeblocSize else { return nil }
        return MusicLink.webloc(data).flatMap(MusicLink.init)
    }

    func showMiniPlayer() {
        NSApp.activate()
        openMiniPlayer?()
    }

    func showMainWindow() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(Self.mainWindowId) == true }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }

    private func applyPresentation(revealsOnPolicyChange: Bool = false) {
        let preferences = Preferences()
        statusMenu?.setVisible(preferences.showMenuBarExtra)
        let policy: NSApplication.ActivationPolicy = preferences.hideDockIcon ? .accessory : .regular
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Switching to .accessory deactivates the app, so the window the user is looking at would disappear.
        if revealsOnPolicyChange { showMainWindow() }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { showMainWindow() }
    }
}

struct UserNotificationPosting: NotificationPosting {
    func authorizationStatus() async -> NotificationAuthorization {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .authorized
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
    }

    func post(identifier: String, title: String, body: String, attachmentURL: URL?) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let attachmentURL, let attachment = try? UNNotificationAttachment(identifier: "artwork", url: attachmentURL) {
            content.attachments = [attachment]
        }
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
}
