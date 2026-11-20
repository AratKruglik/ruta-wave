import Auth
import InnerTube

/// Changes whenever the screens must reload: a mode switch or an account switch.
struct ContentIdentity: Hashable {
    let isSignedIn: Bool
    let authUserIndex: Int
}

extension AuthSession {
    var contentIdentity: ContentIdentity {
        ContentIdentity(isSignedIn: state.isSignedIn, authUserIndex: authUserIndex)
    }

    var credentials: Credentials? {
        guard case .signedIn(let cookies) = state else { return nil }
        return Credentials(cookies: cookies, authUserIndex: authUserIndex)
    }
}
