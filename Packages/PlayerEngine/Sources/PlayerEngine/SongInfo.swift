import Foundation

public struct SongInfo: Equatable, Sendable {
    public let videoId: String
    public let title: String
    public let artist: String
    public let album: String?
    public let artworkURL: URL?
    public let duration: TimeInterval
    public let elapsed: TimeInterval
    public let isPaused: Bool
    public let playlistId: String?
    public let url: URL

    // Rebuilt per call because Regex is not Sendable and songs change rarely. Order matters and each pattern replaces its first match only, as in the original app.
    private static var cleanupPatterns: [Regex<AnyRegexOutput>] { ([
        #"\s*(- topic)$"#,
        #"\s*vevo$"#,
        #"\s*[(|\[]official(.*?)[)|\]]"#,
        #"\s*[(|\[]((lyrics?|visualizer|audio)\s*(video)?)[)|\]]"#,
        #"\s*[(|\[](performance video)[)|\]]"#,
        #"\s*[(|\[](clip official)[)|\]]"#,
        #"\s*[(|\[](video version)[)|\]]"#,
        #"\s*[(|\[](HD|HQ)\s*?(?:audio)?[)|\]]$"#,
        #"\s*[(|\[](live)[)|\]]$"#,
        #"\s*[(|\[]4K\s*?(?:upgrade)?[)|\]]$"#,
    ] as [String]).map { try! Regex($0).ignoresCase() } }

    static func cleanupName(_ name: String) -> String {
        var result = name
        for pattern in cleanupPatterns {
            if let range = result.firstRange(of: pattern) { result.replaceSubrange(range, with: "") }
        }
        return result
    }

    private static let maxNameBytes = 1024

    private struct Response: Decodable {
        struct Details: Decodable {
            let videoId: String
            let title: String
            let author: String
            let lengthSeconds: String?
            let thumbnail: Thumbnails?
        }
        struct Thumbnails: Decodable {
            struct Item: Decodable { let url: String }
            let thumbnails: [Item]
        }
        struct Microformat: Decodable {
            struct Data: Decodable { let urlCanonical: String? }
            let microformatDataRenderer: Data?
        }
        let videoDetails: Details
        let microformat: Microformat?
    }

    struct Parsed: Equatable {
        let song: SongInfo
        let artworkWithQuery: URL?
    }

    static func parse(_ data: Data) -> Parsed? {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        return make(response)
    }

    private static func make(_ response: Response) -> Parsed? {
        let details = response.videoDetails
        guard let url = PlayerRules.watchURL(videoId: details.videoId) else { return nil }
        let original = details.thumbnail?.thumbnails.last
            .flatMap { URL(string: $0.url) }
            .flatMap { PlayerRules.isAllowedArtworkHost($0) ? $0 : nil }
        var stripped = original.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        stripped?.query = nil
        let song = SongInfo(
            videoId: details.videoId,
            title: cleanupName(String(decoding: details.title.utf8.prefix(maxNameBytes), as: UTF8.self)),
            artist: cleanupName(String(decoding: details.author.utf8.prefix(maxNameBytes), as: UTF8.self)),
            album: nil,
            artworkURL: stripped?.url ?? original,
            duration: details.lengthSeconds.flatMap(Double.init).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 0,
            elapsed: 0,
            isPaused: false,
            playlistId: playlistId(from: response.microformat?.microformatDataRenderer?.urlCanonical),
            url: url
        )
        return Parsed(song: song, artworkWithQuery: original)
    }

    private static func playlistId(from canonical: String?) -> String? {
        guard let canonical, let components = URLComponents(string: canonical) else { return nil }
        let list = components.queryItems?.first { $0.name == "list" }?.value
        return list.flatMap { PlayerRules.isValidID($0) ? $0 : nil }
    }

    func with(artworkURL: URL?, elapsed: TimeInterval, isPaused: Bool) -> SongInfo {
        SongInfo(videoId: videoId, title: title, artist: artist, album: album, artworkURL: artworkURL,
                 duration: duration, elapsed: elapsed, isPaused: isPaused, playlistId: playlistId, url: url)
    }
}
