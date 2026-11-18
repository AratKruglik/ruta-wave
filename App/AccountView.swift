import Auth
import InnerTube
import SwiftUI

private struct ReloadKey: Equatable {
    let index: Int
    let attempt: Int
}

struct AccountView: View {
    let session: AuthSession
    @State private var model = AccountModel()
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 12) {
            switch model.state {
            case .loading:
                ProgressView()
            case .loaded(let info, let accounts):
                AccountHeader(info: info)
                if let accounts {
                    AccountRows(accounts: accounts, session: session)
                } else {
                    Text("Couldn't load other accounts")
                    Button("Retry") { attempt += 1 }
                }
            case .failed(let accounts):
                Text("Couldn't load your account")
                Button("Retry") { attempt += 1 }
                if let accounts {
                    AccountRows(accounts: accounts, session: session)
                }
            }
            Button("Add account") { session.addAccount() }
                .disabled(session.isSigningOut)
            Button("Sign out") { Task { await session.signOut() } }
                .disabled(session.isSigningOut)
            if session.signOutError != nil {
                Text("Couldn't clear the saved session").foregroundStyle(.red)
            }
        }
        .padding()
        .task(id: ReloadKey(index: session.authUserIndex, attempt: attempt)) {
            await model.load(session: session)
        }
        .onChange(of: session.isAddingAccount) { _, adding in
            if !adding { attempt += 1 }
        }
        .sheet(isPresented: Binding(get: { session.isAddingAccount }, set: { if !$0 { session.cancelAddAccount() } })) {
            VStack(spacing: 0) {
                SignInView(session: session)
                Button("Cancel") { session.cancelAddAccount() }.padding(8)
            }
            .frame(minWidth: 520, minHeight: 640)
        }
    }
}

private struct AccountRows: View {
    let accounts: [AccountListItem]
    let session: AuthSession

    var body: some View {
        if accounts.count > 1 {
            HStack(spacing: 12) {
                ForEach(accounts) { item in
                    AccountRow(
                        item: item,
                        isActive: item.authUserIndex == session.authUserIndex,
                        isDisabled: session.isSigningOut,
                        onSelect: { session.authUserIndex = item.authUserIndex }
                    )
                }
            }
        }
    }
}

private struct AccountHeader: View {
    let info: AccountInfo

    var body: some View {
        VStack(spacing: 8) {
            AccountAvatar(url: info.avatarURL, size: 64)
            Text(info.name).font(.title)
            if let handle = info.handle {
                Text(handle).foregroundStyle(.secondary)
            }
        }
    }
}

private struct AccountAvatar: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle").resizable().foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
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
                .overlay { Circle().stroke(Color.accentColor, lineWidth: isActive ? 2 : 0) }
        }
        .buttonStyle(.plain)
        .disabled(isActive || isDisabled)
        .help(item.name)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

#Preview {
    AccountHeader(info: AccountInfo(name: "Test User", handle: "@testhandle", avatarURL: nil))
        .padding()
}

#Preview("Row") {
    HStack {
        AccountRow(
            item: AccountListItem(name: "Test User 1", handle: "@testhandle1", avatarURL: nil, authUserIndex: 1, isSelected: false),
            isActive: true, isDisabled: false, onSelect: {}
        )
        AccountRow(
            item: AccountListItem(name: "Test User 2", handle: nil, avatarURL: nil, authUserIndex: 2, isSelected: false),
            isActive: false, isDisabled: false, onSelect: {}
        )
    }
    .padding()
}
