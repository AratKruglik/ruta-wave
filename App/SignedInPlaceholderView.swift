import Auth
import SwiftUI

struct SignedInPlaceholderView: View {
    let session: AuthSession

    var body: some View {
        VStack(spacing: 12) {
            Text("Signed in").font(.title)
            Button("Add account") { session.addAccount() }
                .disabled(session.isSigningOut)
            Button("Sign out") { Task { await session.signOut() } }
                .disabled(session.isSigningOut)
            if session.signOutError != nil {
                Text("Couldn't clear the saved session").foregroundStyle(.red)
            }
        }
        .padding()
        .sheet(isPresented: Binding(get: { session.isAddingAccount }, set: { if !$0 { session.cancelAddAccount() } })) {
            VStack(spacing: 0) {
                SignInView(session: session)
                Button("Cancel") { session.cancelAddAccount() }.padding(8)
            }
            .frame(minWidth: 520, minHeight: 640)
        }
    }
}
