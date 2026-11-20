import Foundation

public struct QueueItem: Sendable, Equatable {
    public let videoId: String
    public let title: String
    public let artist: String
    public let artworkURL: URL?
    public let duration: TimeInterval
    public let isCurrent: Bool
    let playlistSetVideoId: String?

    public init(videoId: String, title: String, artist: String, artworkURL: URL?, duration: TimeInterval, isCurrent: Bool,
                playlistSetVideoId: String? = nil) {
        self.videoId = videoId
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        self.duration = duration
        self.isCurrent = isCurrent
        self.playlistSetVideoId = playlistSetVideoId
    }

    struct Raw: Decodable {
        let videoId: String
        let title: String
        let artist: String
        let artwork: String?
        let length: String?
        let selected: Bool?
        let setId: String?
    }

    private static let maxNameBytes = 1024
    private static let maxSetIdLength = 128

    static func make(_ raw: Raw) -> QueueItem? {
        guard PlayerRules.isValidID(raw.videoId), (raw.setId?.count ?? 0) <= maxSetIdLength else { return nil }
        // A live stream or a localized label has no m:ss length; the row still counts, or every later index would shift.
        let duration = raw.length.flatMap(PlayerRules.parseDuration) ?? 0
        return QueueItem(
            videoId: raw.videoId,
            title: String(decoding: raw.title.utf8.prefix(maxNameBytes), as: UTF8.self),
            artist: String(decoding: raw.artist.utf8.prefix(maxNameBytes), as: UTF8.self),
            artworkURL: raw.artwork.flatMap(URL.init(string:)).flatMap { PlayerRules.isAllowedArtworkHost($0) ? $0 : nil },
            duration: duration,
            isCurrent: raw.selected ?? false,
            playlistSetVideoId: raw.setId
        )
    }

    /// A single invalid row rejects the whole list: dropping it would shift every later index.
    static func parse(_ raws: [Raw]) -> [QueueItem]? {
        guard raws.count <= PlayerRules.maxQueueItems else { return nil }
        var items: [QueueItem] = []
        items.reserveCapacity(raws.count)
        for raw in raws {
            guard let item = make(raw) else { return nil }
            items.append(item)
        }
        return items
    }
}
