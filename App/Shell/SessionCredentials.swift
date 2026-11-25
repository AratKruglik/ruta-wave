import Auth
import InnerTube

extension AuthSession {
    var credentials: Credentials? {
        guard case .signedIn(let cookies) = state else { return nil }
        return Credentials(cookies: cookies)
    }
}
