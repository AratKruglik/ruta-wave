import InnerTube
import SwiftUI

struct AccountView: View {
    let state: AccountModel.State
    let authUserIndex: Int
    let isSigningOut: Bool
    let signOutFailed: Bool
    let onSwitch: (Int) -> Void
    let onAddAccount: () -> Void
    let onHistory: () -> Void
    let onSignOut: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: Metrics.space12) {
            switch state {
            case .loading:
                ProgressView()
            case .loaded(let info, let accounts):
                AccountHeader(info: info)
                if let accounts {
                    AccountRows(accounts: accounts, authUserIndex: authUserIndex, isDisabled: isSigningOut, onSelect: onSwitch)
                } else {
                    retry("Couldn't load other accounts")
                }
            case .failed(let accounts):
                retry("Couldn't load your account")
                if let accounts {
                    AccountRows(accounts: accounts, authUserIndex: authUserIndex, isDisabled: isSigningOut, onSelect: onSwitch)
                }
            }
            Divider().overlay(.strokeSubtle)
            MenuRow(title: "Add account", action: onAddAccount).disabled(isSigningOut)
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
        .background(.themeBase)
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

private struct AccountRows: View {
    let accounts: [AccountListItem]
    let authUserIndex: Int
    let isDisabled: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        if accounts.count > 1 {
            HStack(spacing: Metrics.space12) {
                ForEach(accounts) { item in
                    AccountRow(
                        item: item, isActive: item.authUserIndex == authUserIndex, isDisabled: isDisabled,
                        onSelect: { onSelect(item.authUserIndex) })
                }
            }
        }
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

private struct AccountRow: View {
    let item: AccountListItem
    let isActive: Bool
    let isDisabled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            AccountAvatar(url: item.avatarURL, size: 34)
                .padding(2)
                .overlay { Circle().stroke(.strokeFocus, lineWidth: isActive ? 2 : 0) }
        }
        .buttonStyle(.plain)
        .disabled(isActive || isDisabled)
        .help(Text(verbatim: item.name))
        .accessibilityLabel(Text(verbatim: item.name))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

#if DEBUG
#Preview("Loaded") {
    AccountView(
        state: .loaded(
            PreviewFixtures.account,
            accounts: [
                AccountListItem(name: "Test User 1", handle: "@testhandle1", avatarURL: nil, authUserIndex: 0, isSelected: true),
                AccountListItem(name: "Test User 2", handle: nil, avatarURL: nil, authUserIndex: 1, isSelected: false),
            ]),
        authUserIndex: 0, isSigningOut: false, signOutFailed: false,
        onSwitch: { _ in }, onAddAccount: {}, onHistory: {}, onSignOut: {}, onRetry: {})
}
#endif

#Preview("Failed") {
    AccountView(
        state: .failed(accounts: nil), authUserIndex: 0, isSigningOut: false, signOutFailed: true,
        onSwitch: { _ in }, onAddAccount: {}, onHistory: {}, onSignOut: {}, onRetry: {})
}
