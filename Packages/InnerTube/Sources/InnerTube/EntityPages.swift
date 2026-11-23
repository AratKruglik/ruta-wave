import Foundation

/// The target of a `watchEndpoint` or `watchPlaylistEndpoint`. It is the input of `InnerTubeClient.watchNext(_:credentials:)`.
public struct WatchTarget: Sendable, Equatable, Hashable {
    public let videoId: String?
    public let playlistId: String?
    public let params: String?

    public init(videoId: String? = nil, playlistId: String? = nil, params: String? = nil) {
        self.videoId = videoId
        self.playlistId = playlistId
        self.params = params
    }
}

/// The header shared by album and playlist pages.
public struct PageHeader: Sendable, Equatable {
    public let title: String
    public let subtitle: String?
    public let secondSubtitle: String?
    public let description: String?
    public let thumbnailURL: URL?
    /// Album artists, or the playlist owner (`browseId` is `nil` when the owner has no link).
    public let artists: [ItemRef]
    public let play: WatchTarget?
    public let shuffle: WatchTarget?
    public let radio: WatchTarget?
    public let isExplicit: Bool
    /// Whether the signed-in account has the page in its library (the bookmark toggle). A guest gets `false`.
    public let isSaved: Bool

    public init(
        title: String, subtitle: String? = nil, secondSubtitle: String? = nil, description: String? = nil,
        thumbnailURL: URL? = nil, artists: [ItemRef] = [], play: WatchTarget? = nil, shuffle: WatchTarget? = nil,
        radio: WatchTarget? = nil, isExplicit: Bool = false, isSaved: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.secondSubtitle = secondSubtitle
        self.description = description
        self.thumbnailURL = thumbnailURL
        self.artists = artists
        self.play = play
        self.shuffle = shuffle
        self.radio = radio
        self.isExplicit = isExplicit
        self.isSaved = isSaved
    }
}

/// `song.artists` is usually empty on album rows: show `PageHeader.artists`.
public struct AlbumTrack: Sendable, Equatable {
    public let number: Int?
    public let song: Song

    public init(number: Int?, song: Song) {
        self.number = number
        self.song = song
    }
}

public struct AlbumPage: Sendable, Equatable {
    public let header: PageHeader
    /// Display text of the first subtitle run ("Album", "Single").
    public let type: String?
    public let year: String?
    /// The `OLAK5uy_…` audio playlist.
    public let audioPlaylistId: String?
    public let tracks: [AlbumTrack]
    public let shelves: [Shelf]

    public init(
        header: PageHeader, type: String?, year: String?, audioPlaylistId: String?, tracks: [AlbumTrack], shelves: [Shelf]
    ) {
        self.header = header
        self.type = type
        self.year = year
        self.audioPlaylistId = audioPlaylistId
        self.tracks = tracks
        self.shelves = shelves
    }
}

public struct ArtistPage: Sendable, Equatable {
    public let name: String
    public let thumbnailURL: URL?
    public let subscriberCountText: String?
    /// `nil` only when the page has no subscribe button. A guest gets `false`.
    public let isSubscribed: Bool?
    /// The channel to subscribe to. It differs from the page's `browseId`.
    public let channelId: String?
    public let shuffle: WatchTarget?
    public let radio: WatchTarget?
    /// In server order. "Top songs" is the `.list` shelf, whose `more` is a `VL…` playlist target.
    public let shelves: [Shelf]
    public let description: String?
    public let viewCountText: String?

    public init(
        name: String, thumbnailURL: URL?, subscriberCountText: String?, isSubscribed: Bool?, channelId: String?,
        shuffle: WatchTarget?, radio: WatchTarget?, shelves: [Shelf], description: String?, viewCountText: String?
    ) {
        self.name = name
        self.thumbnailURL = thumbnailURL
        self.subscriberCountText = subscriberCountText
        self.isSubscribed = isSubscribed
        self.channelId = channelId
        self.shuffle = shuffle
        self.radio = radio
        self.shelves = shelves
        self.description = description
        self.viewCountText = viewCountText
    }
}

public struct PlaylistPage: Sendable, Equatable {
    public let header: PageHeader
    public let tracks: Page<Song>
    /// Pass to `InnerTubeClient.browseContinuation(_:credentials:)` for Suggestions or Related playlists.
    public let sectionsContinuation: String?
    /// The signed-in account owns and can edit the playlist.
    public let isOwned: Bool

    public init(header: PageHeader, tracks: Page<Song>, sectionsContinuation: String?, isOwned: Bool = false) {
        self.header = header
        self.tracks = tracks
        self.sectionsContinuation = sectionsContinuation
        self.isOwned = isOwned
    }
}

public struct LibraryPage: Sendable, Equatable {
    public let sections: [Chip]
    /// `isSelected` marks the current order.
    public let sortOptions: [Chip]
    public let items: Page<MusicItem>

    public init(sections: [Chip], sortOptions: [Chip], items: Page<MusicItem>) {
        self.sections = sections
        self.sortOptions = sortOptions
        self.items = items
    }
}

public struct HistoryEntry: Sendable, Equatable {
    public let song: Song
    /// For the remove-from-history mutation. `nil` means the row is not removable.
    public let feedbackToken: String?

    public init(song: Song, feedbackToken: String?) {
        self.song = song
        self.feedbackToken = feedbackToken
    }
}

public struct HistoryDay: Sendable, Equatable {
    public let title: String
    public let entries: [HistoryEntry]

    public init(title: String, entries: [HistoryEntry]) {
        self.title = title
        self.entries = entries
    }
}

public struct QueueItem: Sendable, Equatable {
    public let song: Song
    public let isCurrent: Bool
    /// The other version of the track (video for a song or the reverse). Only present for signed-in callers in practice.
    public let counterpart: Song?

    public init(song: Song, isCurrent: Bool, counterpart: Song?) {
        self.song = song
        self.isCurrent = isCurrent
        self.counterpart = counterpart
    }
}

/// The Up next queue is for the initial display and chip switching. The bridge stays the source of truth for the live queue.
public struct WatchNext: Sendable, Equatable {
    public let queue: Page<QueueItem>
    public let automix: WatchTarget?
    public let chips: [Chip]
    public let playingFrom: String?
    public let playlistId: String?
    /// `nil` when the Lyrics tab is `unselectable`.
    public let lyricsBrowseId: String?
    public let relatedBrowseId: String?

    public init(
        queue: Page<QueueItem>, automix: WatchTarget?, chips: [Chip], playingFrom: String?, playlistId: String?,
        lyricsBrowseId: String?, relatedBrowseId: String?
    ) {
        self.queue = queue
        self.automix = automix
        self.chips = chips
        self.playingFrom = playingFrom
        self.playlistId = playlistId
        self.lyricsBrowseId = lyricsBrowseId
        self.relatedBrowseId = relatedBrowseId
    }
}

/// `text` uses `\n` line breaks and keeps blank lines.
public struct Lyrics: Sendable, Equatable {
    public let text: String
    public let source: String?

    public init(text: String, source: String?) {
        self.text = text
        self.source = source
    }
}
