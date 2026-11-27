import SwiftUI

struct GuestPromptContent: View {
    let reason: LocalizedStringResource
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: Metrics.space12) {
            Text(reason)
                .font(.rwBody)
                .foregroundStyle(.textPrimary)
                .multilineTextAlignment(.center)
            Button("Sign in", action: onSignIn)
                .buttonStyle(PillButtonStyle(isProminent: true))
        }
        .padding(Metrics.space16)
    }
}

extension View {
    func guestPrompt(isPresented: Binding<Bool>, reason: LocalizedStringResource, onSignIn: @escaping () -> Void) -> some View {
        popover(isPresented: isPresented) {
            GuestPromptContent(reason: reason) {
                isPresented.wrappedValue = false
                onSignIn()
            }
        }
    }
}

/// Always equal: the closure only sets state, so a new instance must not invalidate every reader.
struct SignInRequest: Equatable {
    let perform: @MainActor () -> Void

    static func == (lhs: SignInRequest, rhs: SignInRequest) -> Bool { true }
}

extension EnvironmentValues {
    @Entry var requestSignIn = SignInRequest {}
}

#Preview {
    GuestPromptContent(reason: "Sign in to like songs", onSignIn: {})
        .noInitialPopoverFocus()
        .popoverSurface()
}
