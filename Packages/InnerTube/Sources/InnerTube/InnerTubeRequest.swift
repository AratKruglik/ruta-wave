import Auth
import Foundation

enum InnerTubeRequest {
    static let origin = "https://music.youtube.com"
    private static let mobileClientName = "ANDROID_MUSIC"
    private static let mobileClientVersion = "7.27.52"
    private static let mobileUserAgent = "com.google.android.apps.youtube.music/\(mobileClientVersion) (Linux; U; Android 14) gzip"

    static func make(
        endpoint: String,
        body: [String: any Sendable] = [:],
        cookies: [HTTPCookie],
        now: Date,
        locale: Locale
    ) throws(InnerTubeError) -> URLRequest {
        var request = try signed(
            URL(string: "\(origin)/youtubei/v1/\(endpoint)?prettyPrint=false")!,
            cookies: cookies, now: now)
        try attachPayload(&request, body: body, locale: locale)
        return request
    }

    static func makeGuest(
        endpoint: String,
        body: [String: any Sendable] = [:],
        visitorData: String?,
        locale: Locale
    ) throws(InnerTubeError) -> URLRequest {
        var request = unauthenticated(URL(string: "\(origin)/youtubei/v1/\(endpoint)?prettyPrint=false")!)
        if let visitorData = GuestVisitor.validated(visitorData) {
            request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        try attachPayload(&request, body: body, locale: locale)
        return request
    }

    /// No Safari UA, `Origin` or visitor id: the mobile client answers a guest with the timed lyrics only when it looks like the app.
    static func makeMobileGuest(
        endpoint: String,
        body: [String: any Sendable] = [:],
        locale: Locale
    ) throws(InnerTubeError) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(origin)/youtubei/v1/\(endpoint)?prettyPrint=false")!)
        request.httpShouldHandleCookies = false
        request.setValue(mobileUserAgent, forHTTPHeaderField: "User-Agent")
        try attachPayload(
            &request, body: body, locale: locale,
            clientName: mobileClientName, clientVersion: mobileClientVersion)
        return request
    }

    static func makePage() -> URLRequest {
        var request = unauthenticated(URL(string: origin + "/")!)
        request.httpMethod = "GET"
        return request
    }

    private static func signed(
        _ url: URL,
        cookies: [HTTPCookie],
        now: Date
    ) throws(InnerTubeError) -> URLRequest {
        guard let sapisid = cookies.first(where: { $0.name == "SAPISID" && isYouTubeRoot($0.domain) })?.value else {
            throw .missingSAPISID
        }
        let live = SignInRules.musicCookies(cookies).filter { ($0.expiresDate ?? .distantFuture) > now }
        var request = unauthenticated(url)
        let hash = SAPISIDHash.make(sapisid: sapisid, timestamp: Int(now.timeIntervalSince1970), origin: origin)
        var headers = HTTPCookie.requestHeaderFields(with: live)
        headers["Authorization"] = "SAPISIDHASH \(hash)"
        headers["X-Goog-AuthUser"] = "0"
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    private static func unauthenticated(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue(origin, forHTTPHeaderField: "X-Origin")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) "
                + SignInRules.safariApplicationName,
            forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func attachPayload(
        _ request: inout URLRequest,
        body: [String: any Sendable],
        locale: Locale,
        clientName: String = "WEB_REMIX",
        clientVersion: String = ClientVersion.shared.current
    ) throws(InnerTubeError) {
        var payload: [String: Any] = body
        payload["context"] = [
            "client": [
                "clientName": clientName,
                "clientVersion": clientVersion,
                "hl": locale.language.languageCode?.identifier ?? "en",
                "gl": locale.region?.identifier ?? "US",
            ],
        ]
        request.httpMethod = "POST"
        guard JSONSerialization.isValidJSONObject(payload) else { throw .unexpectedResponse }
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw .unexpectedResponse
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private static func isYouTubeRoot(_ domain: String) -> Bool {
        ["youtube.com", ".youtube.com"].contains(domain.lowercased())
    }
}
