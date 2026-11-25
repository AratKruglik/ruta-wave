import AppKit
import AppSettings
import Auth
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let session: AuthSession

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            PlaybackSettings()
                .tabItem { Label("Playback", systemImage: "play.circle") }
            AccountSettings(session: session)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
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
                        Text("Restart Rutawave to apply the language.")
                            .font(.rwCaption)
                            .foregroundStyle(.textSecondary)
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
                        Text("Allow Rutawave in Login Items to open it at login.")
                            .font(.rwCaption)
                            .foregroundStyle(.textSecondary)
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                } else if launchAtLogin.failed {
                    Text("Couldn't change the login item")
                        .font(.rwCaption)
                        .foregroundStyle(.textSecondary)
                }
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

private struct AccountSettings: View {
    let session: AuthSession
    @State private var account = AccountModel()

    var body: some View {
        Form {
            if session.state.isSignedIn {
                switch account.state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .loaded(let info, _):
                    LabeledContent("Signed in as") {
                        VStack(alignment: .trailing) {
                            Text(verbatim: info.name)
                            if let handle = info.handle { Text(verbatim: handle).foregroundStyle(.textSecondary) }
                        }
                    }
                case .failed:
                    Text("Couldn't load your account")
                }
                Button("Sign out") { Task { await session.signOut() } }
                    .disabled(session.isSigningOut)
            } else {
                Text("You're not signed in. Sign in from the main window to like songs and see your library.")
                    .foregroundStyle(.textSecondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: AccountKey(isSignedIn: session.state.isSignedIn, authUserIndex: session.authUserIndex)) {
            await account.load(session: session)
        }
    }
}

private struct AccountKey: Equatable {
    let isSignedIn: Bool
    let authUserIndex: Int
}
