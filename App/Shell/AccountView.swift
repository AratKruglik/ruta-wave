import InnerTube
import SwiftUI

struct AccountView: View {
    let state: AccountModel.State
    let isSigningOut: Bool
    let signOutFailed: Bool
    let onHistory: () -> Void
    let onSignOut: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: Metrics.space12) {
            switch state {
            case .loading:
                ProgressView()
            case .loaded(let info):
                AccountHeader(info: info)
            case .failed:
                retry("Couldn't load your account")
            }
            Divider().overlay(.strokeSubtle)
            MenuRow(title: "History", action: onHistory)
            SettingsLink {
                Text("Settings…")
                    .font(.rwBody)
                    .foregroundStyle(.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metrics.space8)
                    .frame(minHeight: Metrics.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            MenuRow(title: "Sign out", action: onSignOut).disabled(isSigningOut)
            if signOutFailed {
                Label("Couldn't clear the saved session", systemImage: "exclamationmark.triangle")
                    .font(.rwCaption)
                    .foregroundStyle(.textPrimary)
            }
        }
        .padding(Metrics.space16)
        .frame(width: 280)
        .noInitialPopoverFocus()
        .popoverSurface()
    }

    private func retry(_ message: LocalizedStringKey) -> some View {
        VStack(spacing: Metrics.space8) {
            Text(message).font(.rwBody).foregroundStyle(.textSecondary)
            Button("Retry", action: onRetry)
                .buttonStyle(.plain)
                .font(.rwButton)
                .foregroundStyle(.accentLink)
        }
    }
}

private struct MenuRow: View {
    let title: LocalizedStringKey
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.rwBody)
                .foregroundStyle(isEnabled ? .textPrimary : .textDisabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.space8)
                .frame(minHeight: Metrics.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AccountHeader: View {
    let info: AccountInfo

    var body: some View {
        VStack(spacing: Metrics.space8) {
            AccountAvatar(url: info.avatarURL, size: 64)
            Text(verbatim: info.name).font(.rwShelfTitle).foregroundStyle(.textPrimary).lineLimit(1)
            if let handle = info.handle {
                Text(verbatim: handle).font(.rwBody).foregroundStyle(.textSecondary).lineLimit(1)
            }
        }
    }
}

#if DEBUG
#Preview("Loaded") {
    AccountView(
        state: .loaded(PreviewFixtures.account), isSigningOut: false, signOutFailed: false,
        onHistory: {}, onSignOut: {}, onRetry: {})
}
#endif

#Preview("Failed") {
    AccountView(state: .failed, isSigningOut: false, signOutFailed: true, onHistory: {}, onSignOut: {}, onRetry: {})
}
