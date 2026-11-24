import AppKit
import AppSettings
import SwiftUI

struct SettingsView: View {
    @State private var language: String?
    @State private var launchLanguage: String?
    @State private var useArtworkColors = Preferences().useArtworkColors

    private let preferences = Preferences()

    init() {
        let current = Preferences().appLanguage
        _language = State(initialValue: current)
        _launchLanguage = State(initialValue: current)
    }

    var body: some View {
        Form {
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
            Toggle("Use artwork colours", isOn: $useArtworkColors)
            Text("More settings are coming.")
                .font(.rwCaption)
                .foregroundStyle(.textSecondary)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: language) { _, newValue in preferences.appLanguage = newValue }
        .onChange(of: useArtworkColors) { _, newValue in preferences.useArtworkColors = newValue }
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

#Preview {
    SettingsView()
}
