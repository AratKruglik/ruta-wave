#if DEBUG
import Foundation

private struct EmptyKeychain: KeychainStore {
    func read() throws(KeychainError) -> Data? { nil }
    func write(_ data: Data) throws(KeychainError) {}
    func delete() throws(KeychainError) {}
}

extension AuthSession {
    /// A guest session for UI-test fixtures: no Keychain access and no write to `UserDefaults.standard`.
    public static func fixtureGuest() -> AuthSession {
        let suite = "RutawaveUITestsAuth"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: migrationKey)
        return AuthSession(keychain: EmptyKeychain(), defaults: defaults)
    }
}
#endif
