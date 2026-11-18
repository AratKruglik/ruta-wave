import Foundation
import Testing
@testable import Auth

func makeCookie(_ name: String, domain: String = ".youtube.com", expires: Date? = nil, httpOnly: Bool = false) -> HTTPCookie {
    var props: [HTTPCookiePropertyKey: Any] = [
        .name: name, .value: "test-value", .domain: domain, .path: "/", .secure: "TRUE",
    ]
    if let expires { props[.expires] = expires }
    if httpOnly { props[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
    props[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax
    return HTTPCookie(properties: props)!
}

@Suite struct SignInRulesTests {
    let music = URL(string: "https://music.youtube.com/")!

    @Test func completeWhenMusicHostAndSapisidOnYoutube() {
        #expect(SignInRules.isSignInComplete(mainFrameURL: music, cookies: [makeCookie("SAPISID")]))
    }

    @Test func incompleteCases() {
        let sapisid = makeCookie("SAPISID")
        #expect(!SignInRules.isSignInComplete(mainFrameURL: music, cookies: [makeCookie("SAPISID", domain: ".google.com")]))
        #expect(!SignInRules.isSignInComplete(mainFrameURL: URL(string: "https://www.youtube.com/")!, cookies: [sapisid]))
        #expect(!SignInRules.isSignInComplete(mainFrameURL: URL(string: "https://accounts.google.com/")!, cookies: [sapisid]))
        #expect(!SignInRules.isSignInComplete(mainFrameURL: music, cookies: []))
        #expect(!SignInRules.isSignInComplete(mainFrameURL: nil, cookies: [sapisid]))
    }

    @Test func partialSetIsCompleteButNotRestorable() throws {
        let partial = [makeCookie("SAPISID")]
        #expect(SignInRules.isSignInComplete(mainFrameURL: music, cookies: partial))
        let outcome = SessionCookies.restore(from: try SessionCookies.encode(partial), now: Date())
        guard case .signedOut = outcome else { Issue.record("expected signedOut"); return }
    }

    @Test(arguments: [
        ("https://accounts.google.com/x", true), ("https://accounts.youtube.com/", true),
        ("https://consent.google.com/", true), ("https://consent.youtube.com/", true),
        ("https://music.youtube.com/", true), ("https://www.youtube.com/", true),
        ("https://myaccount.google.com/", true), ("https://www.google.com/", true),
        ("https://Accounts.Google.com/", true), ("https://gds.google.com/web/landing", true),
        ("https://accounts.google.com.ua/accounts/SetSID", true),
        ("https://accounts.google.de/accounts/SetSID", true),
        ("https://accounts.google.co.uk/accounts/SetSID", true),
        ("https://accounts.google.cat/accounts/SetSID", true),
        ("https://accounts.google.de/accounts/SetSID?continue=x", true),
        ("https://accounts.google.de/ServiceLogin", false), ("https://accounts.google.com.ua/", false),
        ("https://accounts.google.de/accounts/SetSID/", false),
        ("https://accounts.google.de/accounts/setsid", false),
        ("https://accounts.google.de//accounts/SetSID", false),
        ("https://accounts.google.de/accounts/SetSID/x", false),
        ("https://accounts.google.de:8443/accounts/SetSID", true),
        ("https://accounts.google.xyz/accounts/SetSID", false),
        ("https://accounts.google.com.evil.ua/accounts/SetSID", false),
        ("https://evil.accounts.google.com.ua/accounts/SetSID", false),
        ("https://accounts.google.com.ua.evil.com/accounts/SetSID", false),
        ("http://accounts.google.de/accounts/SetSID", false),
        ("https://accounts.google.xyz/", false), ("https://accounts.google.com.evil.ua/", false),
        ("https://evil.accounts.google.com.ua/", false), ("https://accounts.google.com.ua.evil.com/", false),
        ("http://accounts.google.com.ua/", false),
        ("http://accounts.google.com/", false),("https://google.com.evil.example/", false),
        ("https://notyoutube.com/", false), ("https://evil.example/", false), ("about:blank", false),
    ])
    func allowlist(url: String, allowed: Bool) {
        #expect(SignInRules.isAllowedMainFrameNavigation(URL(string: url)!) == allowed)
    }

    @Test func musicCookiesFiltersByDomain() {
        let kept = ["youtube.com", ".youtube.com", "music.youtube.com"].map { makeCookie("a", domain: $0) }
        let dropped = [".google.com", "www.youtube.com", "notyoutube.com"].map { makeCookie("a", domain: $0) }
        #expect(SignInRules.musicCookies(kept + dropped).map(\.domain) == kept.map(\.domain))
    }

    @Test func signInURLsStartOnAllowedHostsOverHTTPS() {
        #expect(SignInRules.isAllowedMainFrameNavigation(SignInRules.signInURL))
        #expect(SignInRules.isAllowedMainFrameNavigation(SignInRules.addAccountURL))
    }

    @Test func safariTokenPresent() {
        #expect(SignInRules.safariApplicationName.hasPrefix("Version/"))
        #expect(SignInRules.safariApplicationName.hasSuffix("Safari/605.1.15"))
    }
}
