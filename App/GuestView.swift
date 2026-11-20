import Auth
import SwiftUI

struct GuestView: View {
    let session: AuthSession
    @State private var model = GuestModel()
    @State private var attempt = 0
    @State private var isSigningIn = false

    var body: some View {
        GuestContent(
            status: model.state,
            isSignInDisabled: session.isSigningOut,
            isSessionExpired: session.isSessionExpired,
            onRetry: { attempt += 1 },
            onSignIn: { isSigningIn = true }
        )
        .task(id: attempt) { await model.connect() }
        .onAppear { if session.isSessionExpired { isSigningIn = true } }
        .sheet(isPresented: Binding(get: { isSigningIn }, set: { if !$0 { cancel() } })) {
            VStack(spacing: 0) {
                SignInView(session: session)
                Button("Cancel") { cancel() }
                    .keyboardShortcut(.cancelAction)
                    .padding(8)
            }
            .frame(minWidth: 520, minHeight: 640)
        }
    }

    private func cancel() {
        isSigningIn = false
        Task { await session.cancelSignIn() }
    }
}

private struct GuestContent: View {
    let status: GuestModel.State
    let isSignInDisabled: Bool
    let isSessionExpired: Bool
    let onRetry: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Rutawave").font(.largeTitle)
            if isSessionExpired {
                Text("Your session expired. Sign in again.")
            }
            Group {
                switch status {
                case .connecting:
                    HStack { ProgressView().controlSize(.small); Text("Connecting to YouTube Music") }
                case .connected:
                    Text("Connected to YouTube Music as a guest")
                case .failed:
                    Text("Couldn't reach YouTube Music")
                }
            }
            .accessibilityElement(children: .combine)
            if status == .failed {
                Button("Retry", action: onRetry)
            }
            Button("Sign in", action: onSignIn)
                .disabled(isSignInDisabled)
        }
        .padding()
    }
}

#Preview("Connecting") {
    GuestContent(status: .connecting, isSignInDisabled: false, isSessionExpired: false, onRetry: {}, onSignIn: {})
}

#Preview("Connected") {
    GuestContent(status: .connected, isSignInDisabled: false, isSessionExpired: false, onRetry: {}, onSignIn: {})
}

#Preview("Failed") {
    GuestContent(status: .failed, isSignInDisabled: false, isSessionExpired: false, onRetry: {}, onSignIn: {})
}

#Preview("Expired") {
    GuestContent(status: .connected, isSignInDisabled: false, isSessionExpired: true, onRetry: {}, onSignIn: {})
}
