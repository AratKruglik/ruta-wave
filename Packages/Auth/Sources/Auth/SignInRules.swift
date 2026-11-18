import Foundation

public enum SignInRules {
    public static let signInURL = URL(string: "https://accounts.google.com/ServiceLogin?ltmpl=music&service=youtube&continue=https%3A%2F%2Fmusic.youtube.com%2F")!
    public static let addAccountURL = URL(string: "https://accounts.google.com/AddSession?ltmpl=music&service=youtube&continue=https%3A%2F%2Fmusic.youtube.com%2F")!

    public static let allowedHosts: Set<String> = [
        "accounts.google.com", "accounts.youtube.com",
        "consent.google.com", "consent.youtube.com",
        "music.youtube.com", "www.youtube.com",
        "myaccount.google.com", "www.google.com",
        "gds.google.com",
    ]

    // shortcut: Safari version is read from the installed app, falling back to a constant, update the fallback when it ages.
    public static let safariApplicationName: String = {
        let version = Bundle(path: "/Applications/Safari.app")?
            .infoDictionary?["CFBundleShortVersionString"] as? String ?? "17.0"
        return "Version/\(version) Safari/605.1.15"
    }()

    public static func isAllowedMainFrameNavigation(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return allowedHosts.contains(host) || isRegionalAccountsHost(host)
    }

    // Google redirects SetSID to a country-specific accounts domain (e.g. accounts.google.com.ua).
    private static func isRegionalAccountsHost(_ host: String) -> Bool {
        host.wholeMatch(of: /accounts\.google\.(?:com\.|co\.)?[a-z]{2}/) != nil
    }

    public static func musicCookies(_ cookies: [HTTPCookie]) -> [HTTPCookie] {
        cookies.filter { ["youtube.com", "music.youtube.com"].contains(normalizedDomain($0)) }
    }

    public static func isSignInComplete(mainFrameURL: URL?, cookies: [HTTPCookie]) -> Bool {
        guard mainFrameURL?.host?.lowercased() == "music.youtube.com" else { return false }
        return musicCookies(cookies).contains { $0.name == "SAPISID" }
    }

    private static func normalizedDomain(_ cookie: HTTPCookie) -> String {
        let domain = cookie.domain.lowercased()
        return domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
    }
}
