import Foundation

enum PlayerRules {
    static let playerHost = "music.youtube.com"

    private static let allowedArtworkHostSuffixes = [".googleusercontent.com", ".ggpht.com"]

    static func isAllowedMainFrameNavigation(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", url.host?.lowercased() == playerHost,
              url.user == nil, url.password == nil else { return false }
        return url.port == nil || url.port == 443
    }

    static func isTrustedMessage(isMainFrame: Bool, scheme: String, host: String, port: Int) -> Bool {
        isMainFrame && scheme == "https" && host.lowercased() == playerHost && (port == 0 || port == 443)
    }

    static func isValidID(_ id: String) -> Bool {
        (1...64).contains(id.count) && id.utf8.allSatisfy { $0.isASCIIIDCharacter }
    }

    static func watchURL(videoId: String, playlistId: String? = nil, authUserIndex: Int = 0) -> URL? {
        guard isValidID(videoId), playlistId.map(isValidID) ?? true else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = playerHost
        components.path = "/watch"
        components.queryItems = [URLQueryItem(name: "v", value: videoId)]
        if let playlistId { components.queryItems?.append(URLQueryItem(name: "list", value: playlistId)) }
        if authUserIndex > 0 { components.queryItems?.append(URLQueryItem(name: "authuser", value: String(authUserIndex))) }
        return components.url
    }

    static func isAllowedArtworkHost(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "i.ytimg.com" || allowedArtworkHostSuffixes.contains { host.hasSuffix($0) }
    }

    static func resolveArtwork(stripped: URL?, original: URL?, isReachable: @Sendable (URL) async -> Bool) async -> URL? {
        guard let stripped else { return original }
        return await isReachable(stripped) ? stripped : original
    }
}

private extension UInt8 {
    var isASCIIIDCharacter: Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(self)
            || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(self)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(self)
            || self == UInt8(ascii: "_") || self == UInt8(ascii: "-")
    }
}
