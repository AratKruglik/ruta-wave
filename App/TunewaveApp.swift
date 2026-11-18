import Auth
import SwiftUI

@main
struct TunewaveApp: App {
    @State private var session = AuthSession()

    var body: some Scene {
        WindowGroup {
            Group {
                switch session.state {
                case .signedOut:
                    SignInView(session: session)
                case .signedIn:
                    SignedInPlaceholderView(session: session)
                case .keychainUnavailable:
                    VStack(spacing: 12) {
                        Text("Couldn't access the saved session")
                        Button("Try again") { session.restore() }
                    }
                }
            }
            .frame(minWidth: 520, minHeight: 640)
        }
    }
}
