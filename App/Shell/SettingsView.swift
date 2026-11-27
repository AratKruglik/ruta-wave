import AppKit
import AppSettings
import Auth
import Plugins
import ServiceManagement
import SwiftUI
import UserNotifications

struct SettingsView: View {
    let session: AuthSession
    let plugins: PluginRegistry

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            PlaybackSettings()
                .tabItem { Label("Playback", systemImage: "play.circle") }
            PluginsSettings(registry: plugins)
                .tabItem { Label("Plugins", systemImage: "puzzlepiece.extension") }
            ShortcutsSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AccountSettings(session: session)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .preferredColorScheme(.dark)
        .scrollIndicators(.never)
        .toggleStyle(.switch)
        .focusEffectDisabled()
        .frame(width: 480)
    }
}

private struct GeneralSettings: View {
    @State private var language: String?
    @State private var launchLanguage: String?
    @State private var startingPage = Preferences().startingPage
    @State private var alwaysOnTop = Preferences().alwaysOnTop
    @State private var useArtworkColors = Preferences().useArtworkColors
    @State private var launchAtLogin = LaunchAtLogin()
    @State private var showMenuBarExtra = Preferences().showMenuBarExtra
    @State private var menuBarClickTogglesPlay = Preferences().menuBarClickTogglesPlay
    @State private var hideDockIcon = Preferences().hideDockIcon

    private let preferences = Preferences()

    init() {
        let current = Preferences().appLanguage
        _language = State(initialValue: current)
        _launchLanguage = State(initialValue: current)
    }

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $language) {
                    Text("System").tag(String?.none)
                    Text(verbatim: "English").tag(String?.some("en"))
                    Text(verbatim: "Українська").tag(String?.some("uk"))
                }
                if language != launchLanguage {
                    HStack {
                        Text("Restart RutaWave to apply the language.")
                            .font(.rwCaption)
                            .foregroundStyle(.secondary)
                        Button("Restart now", action: restart)
                    }
                }
            }
            Section {
                Picker("Open on", selection: $startingPage) {
                    Text("Last page").tag(String?.none)
                    ForEach(SidebarSection.allCases, id: \.self) { section in
                        Text(section.title).tag(String?.some(section.preference))
                    }
                }
                Toggle("Open at login", isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) }))
                if launchAtLogin.needsApproval {
                    HStack {
                        Text("Allow RutaWave in Login Items to open it at login.")
                            .font(.rwCaption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Metrics.space8)
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                            .fixedSize()
                    }
                } else if launchAtLogin.failed {
                    Text("Couldn't change the login item")
                        .font(.rwCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Show in the menu bar", isOn: $showMenuBarExtra)
                Toggle("Click the menu bar icon to play or pause", isOn: $menuBarClickTogglesPlay)
                    .disabled(!showMenuBarExtra)
                Toggle(isOn: $hideDockIcon) {
                    Text("Hide the Dock icon")
                    Text("Needs the menu bar icon. Open the window from its menu.")
                }
                .disabled(!showMenuBarExtra)
            }
            Section {
                Toggle("Keep the window on top", isOn: $alwaysOnTop)
                Toggle("Use artwork colours", isOn: $useArtworkColors)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: language) { _, newValue in preferences.appLanguage = newValue }
        .onChange(of: startingPage) { _, newValue in preferences.startingPage = newValue }
        .onChange(of: showMenuBarExtra) { _, newValue in
            preferences.showMenuBarExtra = newValue
            if !newValue { hideDockIcon = false }
        }
        .onChange(of: menuBarClickTogglesPlay) { _, newValue in preferences.menuBarClickTogglesPlay = newValue }
        .onChange(of: hideDockIcon) { _, newValue in preferences.hideDockIcon = newValue }
        .onChange(of: alwaysOnTop) { _, newValue in preferences.alwaysOnTop = newValue }
        .onChange(of: useArtworkColors) { _, newValue in preferences.useArtworkColors = newValue }
        // The user can switch the login item off in System Settings while this window is open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
    }

    private func restart() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        Task {
            guard (try? await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)) != nil else { return }
            NSApp.terminate(nil)
        }
    }
}

/// `SMAppService` owns this setting, so it is read from the system rather than stored in `UserDefaults`.
@MainActor @Observable
private final class LaunchAtLogin {
    private(set) var status = SMAppService.mainApp.status
    private(set) var failed = false

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            failed = false
        } catch {
            failed = true
        }
        refresh()
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }
}

private struct PlaybackSettings: View {
    @State private var resumeOnStart = Preferences().resumeOnStart
    @State private var showDislikeButton = Preferences().showDislikeButton

    private let preferences = Preferences()

    var body: some View {
        Form {
            Toggle(isOn: $resumeOnStart) {
                Text("Resume the last track at launch")
                Text("The track opens paused where you stopped.")
            }
            Toggle("Show the dislike button", isOn: $showDislikeButton)
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: resumeOnStart) { _, newValue in preferences.resumeOnStart = newValue }
        .onChange(of: showDislikeButton) { _, newValue in preferences.showDislikeButton = newValue }
    }
}

private struct PluginsSettings: View {
    let registry: PluginRegistry

    var body: some View {
        Form {
            ForEach(registry.plugins, id: \.pluginId) { plugin in
                PluginRow(plugin: plugin, state: registry.states[type(of: plugin).id])
            }
            KaraokeSettings()
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct KaraokeSettings: View {
    @State private var isOn = Preferences().karaokeEnabled

    var body: some View {
        Section {
            Toggle(isOn: $isOn) {
                Text("Karaoke lyrics")
                Text("Highlights each word as it is sung in the Lyrics tab")
                Text("Experimental. It may add load on the system while the Lyrics tab is open.")
            }
        }
        .onChange(of: isOn) { _, newValue in Preferences().karaokeEnabled = newValue }
    }
}

private extension Plugin {
    var pluginId: String { Self.id }
}

/// The system owns this permission, so it is read from the notification centre rather than stored.
@MainActor @Observable
private final class NotificationPermission {
    private(set) var isDenied = false

    func refresh() async {
        isDenied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
}

private struct PluginRow: View {
    let plugin: any Plugin
    let state: PluginRegistry.RunState?
    @State private var isOn: Bool
    @State private var permission = NotificationPermission()

    init(plugin: any Plugin, state: PluginRegistry.RunState?) {
        self.plugin = plugin
        self.state = state
        let type = type(of: plugin)
        _isOn = State(initialValue: PluginSettings(id: type.id).isEnabled(default: type.isEnabledByDefault))
    }

    private var isNotifications: Bool { type(of: plugin).id == NotificationsPlugin.id }
    private var isDenied: Bool { isNotifications && permission.isDenied }

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { isOn && !isDenied }, set: { isOn = $0 })) {
                Text(type(of: plugin).title)
                if isNotifications { Text("Notify when the track changes") }
            }
            .disabled(isDenied)
            if state == .failed, isOn {
                Text("Couldn't start")
                    .font(.rwCaption)
                    .foregroundStyle(.secondary)
            }
            if isDenied {
                HStack {
                    Text("Notifications are off in System Settings.")
                        .font(.rwCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Metrics.space8)
                    Button("Open Notification Settings", action: openNotificationSettings)
                        .fixedSize()
                }
            }
        }
        .onChange(of: isOn) { _, newValue in PluginSettings(id: type(of: plugin).id).setEnabled(newValue) }
        .task { if isNotifications { await permission.refresh() } }
        // The user can change the permission in System Settings while this window is open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if isNotifications { Task { await permission.refresh() } }
        }
    }

    private func openNotificationSettings() {
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleId)") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct ShortcutsSettings: View {
    // shortcut: glyphs are typed by hand, so they must follow AppCommands when a key changes.
    private static let shortcuts: [(title: LocalizedStringKey, keys: Text)] = [
        ("Play / Pause", Text("Space")),
        ("Previous", Text(verbatim: "⌘←")),
        ("Next", Text(verbatim: "⌘→")),
        ("Seek Back 10 Seconds", Text(verbatim: "⇧⌘←")),
        ("Seek Forward 10 Seconds", Text(verbatim: "⇧⌘→")),
        ("Volume Up", Text(verbatim: "⌘↑")),
        ("Volume Down", Text(verbatim: "⌘↓")),
        ("Mute", Text(verbatim: "⌥⌘↓")),
        ("Repeat", Text(verbatim: "⌘R")),
        ("Shuffle", Text(verbatim: "⌘S")),
        ("Like", Text(verbatim: "⌥⌘L")),
        ("Dislike", Text(verbatim: "⌥⌘D")),
        ("Player Page", Text(verbatim: "⌘P")),
        ("Search", Text(verbatim: "⌘F, ⌘L")),
        ("Back", Text(verbatim: "⌘[")),
        ("Forward", Text(verbatim: "⌘]")),
        ("Mini Player", Text(verbatim: "⇧⌘M")),
    ]

    var body: some View {
        Form {
            ForEach(Array(Self.shortcuts.enumerated()), id: \.offset) { _, shortcut in
                LabeledContent(shortcut.title) { shortcut.keys }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AccountSettings: View {
    let session: AuthSession
    @State private var account = AccountModel()

    var body: some View {
        Form {
            if session.state.isSignedIn {
                switch account.state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .loaded(let info):
                    LabeledContent("Signed in as") {
                        VStack(alignment: .trailing) {
                            Text(verbatim: info.name)
                            if let handle = info.handle { Text(verbatim: handle).foregroundStyle(.secondary) }
                        }
                    }
                case .failed:
                    Text("Couldn't load your account")
                }
                Button("Sign out") { Task { await session.signOut() } }
                    .disabled(session.isSigningOut)
            } else {
                Text("You're not signed in. Sign in from the main window to like songs and see your library.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: session.state.isSignedIn) {
            await account.load(session: session)
        }
    }
}
