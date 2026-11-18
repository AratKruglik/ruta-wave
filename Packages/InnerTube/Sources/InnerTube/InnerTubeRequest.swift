import Auth
import Foundation

enum InnerTubeRequest {
    static let origin = "https://music.youtube.com"
    // shortcut: fixed version, replaced by page discovery in 2.1.
    static let clientVersion = "1.20261115.14.00"

    static func make(
        endpoint: String,
        body: [String: String] = [:],
        cookies: [HTTPCookie],
        authUserIndex: Int,
        now: Date,
        locale: Locale
    ) throws(InnerTubeError) -> URLRequest {
        guard let sapisid = cookies.first(where: { $0.name == "SAPISID" && isYouTubeRoot($0.domain) })?.value else {
            throw .missingSAPISID
        }
        let live = SignInRules.musicCookies(cookies).filter { ($0.expiresDate ?? .distantFuture) > now }
        var payload: [String: Any] = body
        payload["context"] = [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": clientVersion,
                "hl": locale.language.languageCode?.identifier ?? "en",
                "gl": locale.region?.identifier ?? "US",
            ],
        ]

        var request = URLRequest(url: URL(string: "\(origin)/youtubei/v1/\(endpoint)?prettyPrint=false")!)
        request.httpMethod = "POST"
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw .unexpectedResponse
        }
        request.httpShouldHandleCookies = false
        let hash = SAPISIDHash.make(sapisid: sapisid, timestamp: Int(now.timeIntervalSince1970), origin: origin)
        var headers = HTTPCookie.requestHeaderFields(with: live)
        headers["Authorization"] = "SAPISIDHASH \(hash)"
        headers["X-Goog-AuthUser"] = "\(authUserIndex)"
        headers["Origin"] = origin
        headers["X-Origin"] = origin
        headers["Content-Type"] = "application/json"
        headers["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + SignInRules.safariApplicationName
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    private static func isYouTubeRoot(_ domain: String) -> Bool {
        ["youtube.com", ".youtube.com"].contains(domain.lowercased())
    }
}
