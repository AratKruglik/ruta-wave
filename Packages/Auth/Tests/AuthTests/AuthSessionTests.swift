import Foundation
import Security
import Testing
@testable import Auth

private final class KeychainSpy: KeychainStore, @unchecked Sendable {
    var stored: Data?
    var readError: KeychainError?
    private(set) var deleteCount = 0

    func read() throws(KeychainError) -> Data? {
        if let readError { throw readError }
        return stored
    }

    func write(_ data: Data) { stored = data }

    func delete() {
        deleteCount += 1
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
}
