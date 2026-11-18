import Foundation
import Testing
@testable import Auth

@Suite struct SessionCookiesTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func fullSet(expires: Date? = nil) -> [HTTPCookie] {
        SessionCookies.requiredNames.map { makeCookie($0, expires: expires) }
    }

    @Test func roundTripKeepsAttributes() throws {
        let original = makeCookie("SAPISID", httpOnly: true)
        let data = try SessionCookies.encode([original])
        let list = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]])
        let restored = try #require(HTTPCookie(properties: Dictionary(uniqueKeysWithValues: list[0].map { (HTTPCookiePropertyKey($0.key), $0.value) })))
        #expect(restored.name == original.name)
        #expect(restored.value == original.value)
        #expect(restored.domain == original.domain)
        #expect(restored.path == original.path)
        #expect(restored.expiresDate == nil)
        #expect(restored.isSecure)
        #expect(restored.isHTTPOnly)
        #expect(restored.sameSitePolicy == .sameSiteLax)
    }

    @Test func restoreOutcomes() throws {
        let future = now.addingTimeInterval(1000)
        guard case .signedIn = SessionCookies.restore(from: try SessionCookies.encode(fullSet(expires: future)), now: now) else { Issue.record("full"); return }
        guard case .signedIn = SessionCookies.restore(from: try SessionCookies.encode(fullSet()), now: now) else { Issue.record("no expiry"); return }

        let missing = fullSet().filter { $0.name != "SSID" }
        guard case .signedOut = SessionCookies.restore(from: try SessionCookies.encode(missing), now: now) else { Issue.record("missing"); return }

        var expired = fullSet(expires: future).filter { $0.name != "SID" }
        expired.append(makeCookie("SID", expires: now.addingTimeInterval(-1)))
        guard case .signedOut = SessionCookies.restore(from: try SessionCookies.encode(expired), now: now) else { Issue.record("expired"); return }

        guard case .corrupt = SessionCookies.restore(from: Data("garbage".utf8), now: now) else { Issue.record("corrupt"); return }
        guard case .signedOut = SessionCookies.restore(from: nil, now: now) else { Issue.record("nil"); return }
    }

    @Test func restoredCookiesKeepAttributes() throws {
        let cookies = SessionCookies.requiredNames.map { makeCookie($0, httpOnly: true) }
        guard case .signedIn(let restored) = SessionCookies.restore(from: try SessionCookies.encode(cookies), now: now) else {
            Issue.record("expected signedIn"); return
        }
        #expect(Set(restored.map(\.name)) == Set(SessionCookies.requiredNames))
        #expect(restored.allSatisfy { $0.isHTTPOnly && $0.isSecure && $0.domain == ".youtube.com" && $0.sameSitePolicy == .sameSiteLax })
    }

    @Test func expiredOptionalCookieDoesNotSignOut() throws {
        let extra = makeCookie("LOGIN_INFO", expires: now.addingTimeInterval(-1))
        guard case .signedIn = SessionCookies.restore(from: try SessionCookies.encode(fullSet() + [extra]), now: now) else {
            Issue.record("expected signedIn"); return
        }
    }
}
