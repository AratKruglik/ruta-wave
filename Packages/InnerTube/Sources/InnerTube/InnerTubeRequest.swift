import Auth
import Foundation

enum InnerTubeRequest {
    static let origin = "https://music.youtube.com"

    static func make(
        endpoint: String,
        body: [String: any Sendable] = [:],
        cookies: [HTTPCookie],
        authUserIndex: Int,
        now: Date,
        locale: Locale
    ) throws(InnerTubeError) -> URLRequest {
        var request = try signed(
            URL(string: "\(origin)/youtubei/v1/\(endpoint)?prettyPrint=false")!,
            cookies: cookies, authUserIndex: authUserIndex, now: now)
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

    static func makeGet(
        path: String,
        cookies: [HTTPCookie],
        authUserIndex: Int,
        now: Date
    ) throws(InnerTubeError) -> URLRequest {
        var request = try signed(URL(string: origin + path)!, cookies: cookies, authUserIndex: authUserIndex, now: now)
        request.httpMethod = "GET"
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
        authUserIndex: Int,
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
        headers["X-Goog-AuthUser"] = "\(authUserIndex)"
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

    private static func attachPayload(_ request: inout URLRequest, body: [String: any Sendable], locale: Locale) throws(InnerTubeError) {
        var payload: [String: Any] = body
        payload["context"] = [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": ClientVersion.shared.current,
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
