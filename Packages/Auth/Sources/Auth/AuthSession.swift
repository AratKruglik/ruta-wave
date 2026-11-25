import Foundation
import Observation
import WebKit

@MainActor @Observable
public final class AuthSession {
    public enum State {
        case signedOut
        case signedIn(cookies: [HTTPCookie])
        case keychainUnavailable(KeychainError)
    }

    private static let migrationKey = "singleAccountMigrated"
    private static let legacyIndexKey = "authUserIndex"

    public private(set) var state: State = .signedOut
    public private(set) var signInError: (any Error)?
    public private(set) var signOutError: KeychainError?
    public private(set) var isSigningOut = false
    public private(set) var isSessionExpired = false

    @ObservationIgnored var migration: Task<Void, Never>?

    private let keychain: any KeychainStore
    private let defaults: UserDefaults

    public convenience init() {
        self.init(keychain: KeychainItem.session, defaults: .standard)
    }

    init(keychain: any KeychainStore, defaults: UserDefaults) {
        self.keychain = keychain
        self.defaults = defaults
        restore()
    }

    public func restore() {
        let data: Data?
        do {
            data = try keychain.read()
        } catch {
            state = .keychainUnavailable(error)
            migrateToSingleAccount()
            return
        }
        switch SessionCookies.restore(from: data, now: Date()) {
        case .signedIn(let cookies):
            state = .signedIn(cookies: cookies)
        case .signedOut, .corrupt:
            if data != nil { try? keychain.delete() }
            state = .signedOut
        }
        migrateToSingleAccount()
    }

    // A pre-single-account session may hold several Google accounts; one wipe leaves a single account after the next sign-in.
    // The signed-out state is set before anything else can read the session, so no request goes out with the old cookies.
    private func migrateToSingleAccount() {
        guard !defaults.bool(forKey: Self.migrationKey) else { return }
        defaults.removeObject(forKey: Self.legacyIndexKey)
        switch state {
        case .keychainUnavailable:
            return
        case .signedOut:
            defaults.set(true, forKey: Self.migrationKey)
        case .signedIn:
            state = .signedOut
            isSigningOut = true
            migration = Task { @MainActor in
                defer { isSigningOut = false }
                await wipeWebData()
                guard (try? keychain.delete()) != nil else { return }
                defaults.set(true, forKey: Self.migrationKey)
            }
        }
    }

    public func clearSignInError() {
        signInError = nil
    }

    public func continueAsGuest() {
        guard case .keychainUnavailable = state else { return }
        state = .signedOut
    }

    // The state guard matters: a successful sign-in dismisses the sheet, which must not wipe the new session.
    public func cancelSignIn() async {
        guard case .signedOut = state, !isSigningOut else { return }
        signInError = nil
        isSigningOut = true
        defer { isSigningOut = false }
        await wipeWebData()
    }

    private func wipeWebData() async {
        await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        URLCache.shared.removeAllCachedResponses()
    }

    public func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        signOutError = nil
        // WebKit first: a crash mid-wipe must not leave an empty Keychain next to live google.com cookies.
        await wipeWebData()
        do {
            try keychain.delete()
        } catch {
            signOutError = error
            return
        }
        state = .signedOut
    }

    // The caller passes the cookies it sent, so a late 401 from a replaced session is ignored.
    public func expireSession(cookies: [HTTPCookie]) async {
        guard case .signedIn(let current) = state, current == cookies else { return }
        await signOut()
        if case .signedOut = state { isSessionExpired = true }
    }

    // Returns false while the cookie set is still incomplete, so the caller keeps observing.
    func completeSignIn(with cookies: [HTTPCookie]) -> Bool {
        guard case .signedOut = state, !isSigningOut else { return false }
        do {
            let data = try SessionCookies.encode(cookies)
            guard case .signedIn(let restored) = SessionCookies.restore(from: data, now: Date()) else { return false }
            try keychain.write(data)
            state = .signedIn(cookies: restored)
            isSessionExpired = false
            signInError = nil
        } catch {
            signInError = error
        }
        return true
    }
}

extension AuthSession.State {
    public var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }
}
