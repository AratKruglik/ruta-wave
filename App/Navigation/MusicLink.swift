import Foundation
import InnerTube
import Observation

/// What a `rutawave://` or `https://music.youtube.com/…` link asks for. Links are untrusted input, so anything
/// that is not a known path, or fails an ID check, is `nil`.
enum MusicLink: Equatable {
    case section(SidebarSection)
    case route(Route)
    case play(WatchTarget)
    case openInBrowser(URL)

    private static let webHost = "music.youtube.com"
    private static let maxQueryLength = 200

    init?(_ url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.port == nil,
              let segments = Self.segments(of: parts) else { return nil }
        // Form encoding: a literal `+` is a space, while `%2B` stays a plus, so decode from the encoded items.
        let query = Dictionary(
            (parts.percentEncodedQueryItems ?? []).compactMap { item -> (String, String)? in
                guard let name = item.name.removingPercentEncoding,
                      let value = (item.value ?? "").replacingOccurrences(of: "+", with: " ").removingPercentEncoding
                else { return nil }
                return (name, value)
            }, uniquingKeysWith: { first, _ in first })
        guard let link = Self.link(segments: segments, query: query) else { return nil }
        self = link
    }

    static func webloc(_ data: Data) -> URL? {
        let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return ((plist as? [String: Any])?["URL"] as? String).flatMap(URL.init(string:))
    }

    private static func segments(of parts: URLComponents) -> [String]? {
        let scheme = parts.scheme?.lowercased()
        var raw = parts.percentEncodedPath.split(separator: "/").map(String.init)
        switch scheme {
        case "https":
            guard parts.host?.lowercased() == webHost else { return nil }
        case "rutawave":
            if let host = parts.percentEncodedHost, !host.isEmpty { raw.insert(host, at: 0) }
        default:
            return nil
        }
        let decoded = raw.compactMap(\.removingPercentEncoding)
        return decoded.count == raw.count ? decoded : nil
    }

    private static func link(segments: [String], query: [String: String]) -> MusicLink? {
        guard let head = segments.first else { return .section(.home) }
        let id = segments.count == 2 && isID(segments[1]) ? segments[1] : nil
        switch (head, segments.count) {
        case ("explore", 1): return .section(.explore)
        case ("library", 1): return .section(.library)
        case ("history", 1): return .route(.history)
        case ("new_releases", 1): return .route(.explore(.newReleases))
        case ("charts", 1): return .route(.explore(.charts))
        case ("moods_and_genres", 1): return .route(.explore(.moods))
        case ("watch", 1): return watch(query)
        case ("playlist", 1): return playlist(query["list"])
        case ("browse", 2): return id.flatMap(browse)
        case ("channel", 2): return id.flatMap { $0.hasPrefix("UC") ? .route(.artist(channelId: $0)) : nil }
        case ("podcast", 2): return id.flatMap { webURL("podcast/" + $0).map(MusicLink.openInBrowser) }
        case ("search", 1): return search(query["q"])
        default: return nil
        }
    }

    private static func watch(_ query: [String: String]) -> MusicLink? {
        guard let videoId = query["v"], isID(videoId) else { return nil }
        if let list = query["list"], !isID(list) { return nil }
        return .play(WatchTarget(videoId: videoId, playlistId: query["list"]))
    }

    private static func playlist(_ list: String?) -> MusicLink? {
        guard let list, isID(list) else { return nil }
        return list.hasPrefix("RD") ? .play(WatchTarget(playlistId: list)) : .route(.playlist(browseId: "VL" + list))
    }

    private static func browse(_ id: String) -> MusicLink? {
        if id.hasPrefix("MPSP") { return webURL("browse/" + id).map(MusicLink.openInBrowser) }
        let route = Route(target: BrowseTarget(browseId: id))
        if case .more = route { return nil }
        return .route(route)
    }

    private static func search(_ text: String?) -> MusicLink? {
        // Format scalars (bidi overrides, zero-width) can disguise a query; scalar count bounds combining-mark runs.
        let stripped = (text ?? "").unicodeScalars.filter { ![.control, .format].contains($0.properties.generalCategory) }
        let cleaned = String(String.UnicodeScalarView(stripped)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...maxQueryLength).contains(cleaned.unicodeScalars.count) else { return nil }
        return .route(.search(query: cleaned, filter: nil))
    }

    private static func webURL(_ path: String) -> URL? {
        URL(string: "https://\(webHost)/\(path)")
    }

    /// Same rule as the player's own ID check: 1 to 64 ASCII letters, digits, `-` or `_`.
    private static func isID(_ value: String) -> Bool {
        (1...64).contains(value.utf8.count)
            && value.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x2D || $0 == 0x5F }
    }
}

/// Carries a navigation link from the app delegate to the main window, which may not exist yet.
@MainActor @Observable
final class LinkInbox {
    var pending: MusicLink?
}
