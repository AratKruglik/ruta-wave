import Foundation

public struct BrowseTarget: Sendable, Equatable, Hashable {
    public let browseId: String
    public let params: String?

    public init(browseId: String, params: String? = nil) {
        self.browseId = browseId
        self.params = params
    }

    public static let home = BrowseTarget(browseId: "FEmusic_home")
    public static let explore = BrowseTarget(browseId: "FEmusic_explore")
    public static let newReleases = BrowseTarget(browseId: "FEmusic_new_releases")
    public static let moodsAndGenres = BrowseTarget(browseId: "FEmusic_moods_and_genres")
    public static let charts = BrowseTarget(browseId: "FEmusic_charts")
}

/// An artist (`UC…`) or album (`MPREb…`) link inside a subtitle.
public struct ItemRef: Sendable, Equatable {
    public let name: String
    public let browseId: String?

    public init(name: String, browseId: String?) {
        self.name = name
        self.browseId = browseId
    }
}

public struct ChartRank: Sendable, Equatable {
    public enum Trend: Sendable, Equatable { case up, down, neutral }

    public let position: Int
    public let trend: Trend?

    public init(position: Int, trend: Trend?) {
        self.position = position
        self.trend = trend
    }
}

public struct Song: Sendable, Equatable {
    public let videoId: String
    public let playlistId: String?
    public let title: String
    public let subtitle: String?
    public let artists: [ItemRef]
    public let album: ItemRef?
    public let duration: String?
    public let thumbnailURL: URL?
    public let isExplicit: Bool
    public let isVideo: Bool
    public let rank: ChartRank?

    public init(
        videoId: String, playlistId: String? = nil, title: String, subtitle: String? = nil,
        artists: [ItemRef] = [], album: ItemRef? = nil, duration: String? = nil, thumbnailURL: URL? = nil,
        isExplicit: Bool = false, isVideo: Bool = false, rank: ChartRank? = nil
    ) {
        self.videoId = videoId
        self.playlistId = playlistId
        self.title = title
        self.subtitle = subtitle
        self.artists = artists
        self.album = album
        self.duration = duration
        self.thumbnailURL = thumbnailURL
        self.isExplicit = isExplicit
        self.isVideo = isVideo
        self.rank = rank
    }
}

public struct Album: Sendable, Equatable {
    public let browseId: String
    public let title: String
    public let subtitle: String?
    public let artists: [ItemRef]
    public let thumbnailURL: URL?
    public let isExplicit: Bool

    public init(
        browseId: String, title: String, subtitle: String? = nil, artists: [ItemRef] = [],
        thumbnailURL: URL? = nil, isExplicit: Bool = false
    ) {
        self.browseId = browseId
        self.title = title
        self.subtitle = subtitle
        self.artists = artists
        self.thumbnailURL = thumbnailURL
        self.isExplicit = isExplicit
    }
}

public struct Artist: Sendable, Equatable {
    public let browseId: String
    public let name: String
    public let subtitle: String?
    public let thumbnailURL: URL?
    public let rank: ChartRank?

    public init(browseId: String, name: String, subtitle: String? = nil, thumbnailURL: URL? = nil, rank: ChartRank? = nil) {
        self.browseId = browseId
        self.name = name
        self.subtitle = subtitle
        self.thumbnailURL = thumbnailURL
        self.rank = rank
    }
}

/// `browseId` is `VL…` (or `RD…` for radio cards).
public struct Playlist: Sendable, Equatable {
    public let browseId: String
    public let title: String
    public let subtitle: String?
    public let thumbnailURL: URL?

    public init(browseId: String, title: String, subtitle: String? = nil, thumbnailURL: URL? = nil) {
        self.browseId = browseId
        self.title = title
        self.subtitle = subtitle
        self.thumbnailURL = thumbnailURL
    }
}

/// Explore tiles and mood / genre buttons.
public struct NavigationLink: Sendable, Equatable {
    public let title: String
    public let target: BrowseTarget

    public init(title: String, target: BrowseTarget) {
        self.title = title
        self.target = target
    }
}

public enum MusicItem: Sendable, Equatable {
    case song(Song)
    case album(Album)
    case artist(Artist)
    case playlist(Playlist)
    case link(NavigationLink)
}
