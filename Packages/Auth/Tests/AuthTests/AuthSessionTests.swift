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
        defaults.set(2, forKey: "authUserIndex")
        let session = AuthSession(keychain: keychain, defaults: defaults)
        guard case .signedOut = session.state else { Issue.record("expected signedOut"); return }
        #expect(keychain.deleteCount == 1)
        #expect(session.authUserIndex == 0)
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
        session.authUserIndex = 2
        await session.expireSession(cookies: cookies)
        guard case .signedOut = session.state else { Issue.record("expected signedOut"); return }
        #expect(session.isSessionExpired)
        #expect(keychain.deleteCount == 1)
        #expect(session.authUserIndex == 0)
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
}
