import Foundation
import Testing
@testable import Auth

@MainActor @Suite struct AuthSessionFixturesTests {
    @Test func fixtureGuestStartsSignedOut() {
        let session = AuthSession.fixtureGuest()
        guard case .signedOut = session.state else {
            Issue.record("expected signedOut, got \(session.state)")
            return
        }
    }

    @Test func fixtureGuestLeavesStandardDefaultsUntouched() {
        let before = UserDefaults.standard.object(forKey: AuthSession.migrationKey)
        _ = AuthSession.fixtureGuest()
        #expect(UserDefaults.standard.object(forKey: AuthSession.migrationKey) as? Bool == before as? Bool)
    }
}
