import Foundation
import Security
import Testing
@testable import Auth

private final class KeychainSpy: KeychainStore, @unchecked Sendable {
    var stored: Data?
    var readError: KeychainError?
    var deleteError: KeychainError?
    private(set) var deleteCount = 0

    func read() throws(KeychainError) -> Data? {
        if let readError { throw readError }
        return stored
    }

    func write(_ data: Data) { stored = data }

    func delete() throws(KeychainError) {
        deleteCount += 1
        if let deleteError { throw deleteError }
        stored = nil
    }
}

@MainActor @Suite struct AuthSessionTests {
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "singleAccountMigrated")
    }

    private func unmigratedDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    @Test func isSignedInOnlyForSignedIn() {
        #expect(AuthSession.State.signedIn(cookies: []).isSignedIn)
        #expect(!AuthSession.State.signedOut.isSignedIn)
        #expect(!AuthSession.State.keychainUnavailable(KeychainError(status: errSecInteractionNotAllowed)).isSignedIn)
    }

    @Test func continueAsGuestDoesNotTouchKeychain() {
        let keychain = KeychainSpy()
        keychain.readError = KeychainError(status: errSecInteractionNotAllowed)
        let session = AuthSession(keychain: keychain, defaults: defaults)
        guard case .keychainUnavailable = session.state else { Issue.record("expected keychainUnavailable"); return }
        session.continueAsGuest()
        guard case .signedOut = session.state else { Issue.record("expected signedOut"); return }
        #expect(keychain.deleteCount == 0)
    }

    @Test func restoreDropsCorruptEntry() {
        let keychain = KeychainSpy()
        keychain.stored = Data("x".utf8)
        let session = AuthSession(keychain: keychain, defaults: defaults)
        guard case .signedOut = session.state else { Issue.record("expected signedOut"); return }
        #expect(keychain.deleteCount == 1)
    }

    @Test func cancelSignInKeepsSignedInSession() async throws {
        let keychain = KeychainSpy()
        keychain.stored = try SessionCookies.encode(SessionCookies.requiredNames.map { makeCookie($0) })
        let session = AuthSession(keychain: keychain, defaults: defaults)
        #expect(session.state.isSignedIn)
        await session.cancelSignIn()
        #expect(session.state.isSignedIn)
        #expect(keychain.deleteCount == 0)
    }

    private func validData() throws -> Data {
        try SessionCookies.encode(SessionCookies.requiredNames.map { makeCookie($0) })
    }

    @Test func restoreWithoutItemIsSignedOut() {
        let keychain = KeychainSpy()
        let session = AuthSession(keychain: keychain, defaults: defaults)
        #expect(!session.state.isSignedIn)
        #expect(keychain.deleteCount == 0)
    }

    @Test func restoreValidItemIsSignedIn() throws {
        let keychain = KeychainSpy()
        keychain.stored = try validData()
        #expect(AuthSession(keychain: keychain, defaults: defaults).state.isSignedIn)
    }

    @Test func unavailableKeychainKeepsItem() {
        let keychain = KeychainSpy()
        keychain.stored = Data("x".utf8)
        keychain.readError = KeychainError(status: errSecInteractionNotAllowed)
        let session = AuthSession(keychain: keychain, defaults: defaults)
        guard case .keychainUnavailable = session.state else { Issue.record("expected keychainUnavailable"); return }
        #expect(keychain.deleteCount == 0)
        #expect(keychain.stored != nil)
    }

    @Test func continueAsGuestIgnoredWhenSignedIn() throws {
        let keychain = KeychainSpy()
        keychain.stored = try validData()
        let session = AuthSession(keychain: keychain, defaults: defaults)
        session.continueAsGuest()
        #expect(session.state.isSignedIn)
    }

    @Test func cancelSignInIgnoredWhenKeychainUnavailable() async {
        let keychain = KeychainSpy()
        keychain.readError = KeychainError(status: errSecInteractionNotAllowed)
        let session = AuthSession(keychain: keychain, defaults: defaults)
        await session.cancelSignIn()
        guard case .keychainUnavailable = session.state else { Issue.record("expected keychainUnavailable"); return }
        #expect(!session.isSigningOut)
    }

    @Test func completeSignInPersistsAndSignsIn() {
        let keychain = KeychainSpy()
        let session = AuthSession(keychain: keychain, defaults: defaults)
        #expect(session.completeSignIn(with: SessionCookies.requiredNames.map { makeCookie($0) }))
        #expect(session.state.isSignedIn)
        #expect(keychain.stored != nil)
    }

    @Test func completeSignInWithIncompleteCookiesKeepsObserving() {
        let keychain = KeychainSpy()
        let session = AuthSession(keychain: keychain, defaults: defaults)
        #expect(!session.completeSignIn(with: [makeCookie("SID")]))
        #expect(!session.state.isSignedIn)
        #expect(keychain.stored == nil)
    }

    private func signedInSession(_ keychain: KeychainSpy) throws -> (AuthSession, [HTTPCookie]) {
        keychain.stored = try validData()
        let session = AuthSession(keychain: keychain, defaults: defaults)
        guard case .signedIn(let cookies) = session.state else { throw KeychainError(status: errSecItemNotFound) }
        return (session, cookies)
    }

    @Test func expireSessionSignsOutAndFlags() async throws {
        let keychain = KeychainSpy()
        let (session, cookies) = try signedInSession(keychain)
        await session.expireSession(cookies: cookies)
        guard case .signedOut = session.state else { Issue.record("expected signedOut"); return }
        #expect(session.isSessionExpired)
        #expect(keychain.deleteCount == 1)
        await session.expireSession(cookies: cookies)
        #expect(keychain.deleteCount == 1)
    }

    @Test func expireSessionIgnoresStaleCookies() async throws {
        let keychain = KeychainSpy()
        let (session, _) = try signedInSession(keychain)
        await session.expireSession(cookies: [makeCookie("SID")])
        #expect(session.state.isSignedIn)
        #expect(!session.isSessionExpired)
        #expect(keychain.deleteCount == 0)
    }

    @Test func expireSessionIgnoresSameNamesWithDifferentValues() async throws {
        let keychain = KeychainSpy()
        let (session, current) = try signedInSession(keychain)
        let stale = current.map { cookie in
            HTTPCookie(properties: [
                .name: cookie.name, .value: cookie.value + "-old", .domain: cookie.domain, .path: cookie.path,
            ])!
        }
        await session.expireSession(cookies: stale)
        #expect(session.state.isSignedIn)
        #expect(!session.isSessionExpired)
        #expect(keychain.deleteCount == 0)
    }

    @Test func expireSessionIgnoredWhenSignedOut() async {
        let keychain = KeychainSpy()
        let session = AuthSession(keychain: keychain, defaults: defaults)
        await session.expireSession(cookies: [])
        #expect(!session.isSessionExpired)
        #expect(keychain.deleteCount == 0)
    }

    @Test func expireSessionKeepsSessionWhenKeychainDeleteFails() async throws {
        let keychain = KeychainSpy()
        let (session, cookies) = try signedInSession(keychain)
        keychain.deleteError = KeychainError(status: errSecInteractionNotAllowed)
        await session.expireSession(cookies: cookies)
        #expect(session.state.isSignedIn)
        #expect(!session.isSessionExpired)
    }

    @Test func completeSignInClearsExpiredFlag() async throws {
        let keychain = KeychainSpy()
        let (session, cookies) = try signedInSession(keychain)
        await session.expireSession(cookies: cookies)
        #expect(session.isSessionExpired)
        #expect(session.completeSignIn(with: SessionCookies.requiredNames.map { makeCookie($0) }))
        #expect(!session.isSessionExpired)
    }

    @Test func completeSignInDoesNotOverwriteSignedInSession() throws {
        let keychain = KeychainSpy()
        let (session, cookies) = try signedInSession(keychain)
        #expect(!session.completeSignIn(with: SessionCookies.requiredNames.map { makeCookie($0, domain: "music.youtube.com") }))
        guard case .signedIn(let current) = session.state else { Issue.record("expected signedIn"); return }
        #expect(current == cookies)
    }

    @Test(arguments: [nil, 1] as [Int?])
    func migrationWipesSignedInSessionOnce(legacyIndex: Int?) async throws {
        let fresh = unmigratedDefaults()
        if let legacyIndex { fresh.set(legacyIndex, forKey: "authUserIndex") }
        let keychain = KeychainSpy()
        keychain.stored = try validData()
        let session = AuthSession(keychain: keychain, defaults: fresh)
        guard case .signedOut = session.state else { Issue.record("expected signedOut"); return }
        #expect(session.isSigningOut)
        #expect(!session.completeSignIn(with: SessionCookies.requiredNames.map { makeCookie($0) }))
        await session.migration?.value
        #expect(keychain.deleteCount == 1)
        #expect(fresh.bool(forKey: "singleAccountMigrated"))
        #expect(fresh.object(forKey: "authUserIndex") == nil)
        #expect(!session.isSessionExpired)
        #expect(!session.isSigningOut)
        #expect(session.droppedLegacySession)
    }

    @Test func migrationOfGuestOnlyWritesMarker() {
        let fresh = unmigratedDefaults()
        let keychain = KeychainSpy()
        let session = AuthSession(keychain: keychain, defaults: fresh)
        #expect(session.migration == nil)
        #expect(keychain.deleteCount == 0)
        #expect(fresh.bool(forKey: "singleAccountMigrated"))
        #expect(!session.droppedLegacySession)
    }

    @Test func migratedSessionIsKept() throws {
        let keychain = KeychainSpy()
        let (session, _) = try signedInSession(keychain)
        #expect(session.state.isSignedIn)
        #expect(keychain.deleteCount == 0)
    }

    @Test func failedMigrationWipeRetriesOnNextLaunch() async throws {
        let fresh = unmigratedDefaults()
        let keychain = KeychainSpy()
        keychain.stored = try validData()
        keychain.deleteError = KeychainError(status: errSecInteractionNotAllowed)
        let first = AuthSession(keychain: keychain, defaults: fresh)
        await first.migration?.value
        #expect(!fresh.bool(forKey: "singleAccountMigrated"))
        guard case .signedOut = first.state else { Issue.record("expected signedOut"); return }

        keychain.deleteError = nil
        let second = AuthSession(keychain: keychain, defaults: fresh)
        await second.migration?.value
        #expect(fresh.bool(forKey: "singleAccountMigrated"))
        #expect(keychain.stored == nil)
    }

    @Test func migrationWaitsForKeychainAndRunsOnRestore() async throws {
        let fresh = unmigratedDefaults()
        let keychain = KeychainSpy()
        keychain.stored = try validData()
        keychain.readError = KeychainError(status: errSecInteractionNotAllowed)
        let session = AuthSession(keychain: keychain, defaults: fresh)
        #expect(!fresh.bool(forKey: "singleAccountMigrated"))
        #expect(session.migration == nil)
        keychain.readError = nil
        session.restore()
        await session.migration?.value
        #expect(keychain.deleteCount == 1)
        #expect(fresh.bool(forKey: "singleAccountMigrated"))
    }

    @Test func guestWithUnreadableKeychainWipesWebDataBeforeMigration() async {
        let fresh = unmigratedDefaults()
        let keychain = KeychainSpy()
        keychain.readError = KeychainError(status: errSecInteractionNotAllowed)
        let session = AuthSession(keychain: keychain, defaults: fresh)
        session.continueAsGuest()
        #expect(session.isSigningOut)
        #expect(session.droppedLegacySession)
        #expect(!session.completeSignIn(with: SessionCookies.requiredNames.map { makeCookie($0) }))
        await session.migration?.value
        #expect(!session.isSigningOut)
        #expect(keychain.deleteCount == 0)
        #expect(!fresh.bool(forKey: "singleAccountMigrated"))
    }

    @Test func guestWithUnreadableKeychainAfterMigrationSkipsWipe() {
        let keychain = KeychainSpy()
        keychain.readError = KeychainError(status: errSecInteractionNotAllowed)
        let session = AuthSession(keychain: keychain, defaults: defaults)
        session.continueAsGuest()
        #expect(session.migration == nil)
        #expect(!session.isSigningOut)
        #expect(!session.droppedLegacySession)
    }
}
