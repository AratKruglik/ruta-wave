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

    private static let authUserIndexKey = "authUserIndex"

    public private(set) var state: State = .signedOut
    public private(set) var signInError: (any Error)?
    public private(set) var signOutError: KeychainError?
    public private(set) var isAddingAccount = false
    public private(set) var isSigningOut = false

    public var authUserIndex: Int {
        didSet { defaults.set(authUserIndex, forKey: Self.authUserIndexKey) }
    }

    private let keychain: any KeychainStore
    private let defaults: UserDefaults

    public convenience init() {
        self.init(keychain: KeychainItem.session, defaults: .standard)
    }

    init(keychain: any KeychainStore, defaults: UserDefaults) {
        self.keychain = keychain
        self.defaults = defaults
        authUserIndex = defaults.integer(forKey: Self.authUserIndexKey)
        restore()
    }

    public func restore() {
        let data: Data?
        do {
            data = try keychain.read()
        } catch {
            state = .keychainUnavailable(error)
            return
        }
        switch SessionCookies.restore(from: data, now: Date()) {
        case .signedIn(let cookies):
            state = .signedIn(cookies: cookies)
        case .signedOut, .corrupt:
            if data != nil {
                try? keychain.delete()
                authUserIndex = 0
            }
            state = .signedOut
        }
    }

    public func addAccount() {
        guard !isSigningOut else { return }
        isAddingAccount = true
    }

    public func cancelAddAccount() {
        isAddingAccount = false
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
        isAddingAccount = false
        // WebKit first: a crash mid-wipe must not leave an empty Keychain next to live google.com cookies.
        await wipeWebData()
        do {
            try keychain.delete()
        } catch {
            signOutError = error
            return
        }
        authUserIndex = 0
        state = .signedOut
    }

    // Returns false while the cookie set is still incomplete, so the caller keeps observing.
    func completeSignIn(with cookies: [HTTPCookie]) -> Bool {
        guard !isSigningOut else { return false }
        do {
            let data = try SessionCookies.encode(cookies)
            guard case .signedIn(let restored) = SessionCookies.restore(from: data, now: Date()) else { return false }
            try keychain.write(data)
            if !isAddingAccount { authUserIndex = 0 }
            state = .signedIn(cookies: restored)
            signInError = nil
            isAddingAccount = false
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
