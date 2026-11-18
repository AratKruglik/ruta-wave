import Auth
import InnerTube
import SwiftUI

@main
struct TunewaveApp: App {
    @State private var session = AuthSession()

    var body: some Scene {
        WindowGroup {
            Group {
                switch session.state {
                case .signedOut:
                    GuestView(session: session)
                case .signedIn:
                    AccountView(session: session)
                case .keychainUnavailable:
                    VStack(spacing: 12) {
                        Text("Couldn't access the saved session")
                        Button("Try again") { session.restore() }
                        Button("Continue without signing in") { session.continueAsGuest() }
                    }
                }
            }
            .frame(minWidth: 520, minHeight: 640)
            .onChange(of: session.state.isSignedIn) { InnerTubeClient.resetGuestVisitor() }
        }
    }
}
