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
            case .loaded(let info):
                AccountHeader(info: info)
            case .failed:
                Text("Couldn't load your account")
                Button("Retry") { attempt += 1 }
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

private struct AccountHeader: View {
    let info: AccountInfo

    var body: some View {
        VStack(spacing: 8) {
            AsyncImage(url: info.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle").resizable().foregroundStyle(.secondary)
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
            .accessibilityHidden(true)
            Text(info.name).font(.title)
            if let handle = info.handle {
                Text(handle).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    AccountHeader(info: AccountInfo(name: "Test User", handle: "@testhandle", avatarURL: nil))
        .padding()
}
