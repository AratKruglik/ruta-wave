#if DEBUG
import AppSettings
import Foundation
import InnerTube
import Observation
import PlayerEngine

@MainActor @Observable
final class PreviewPlayer: PlayerControlling {
    var song: SongInfo? = PreviewFixtures.song
    var elapsed: TimeInterval = 67
    var isPaused = false
    var isReady = true
    var isBuffering = false
    var isAd = false
    var volume = 0.6
    var isMuted = false
    var like = LikeStatus.indifferent
    var repeatMode = RepeatMode.off
    var isShuffled = false
    var queue: [PlayerQueueItem] = []

    func send(_ command: PlayerCommand) {}
    func events() -> AsyncStream<PlayerEvent> { AsyncStream { $0.finish() } }
}

@MainActor
enum PreviewFixtures {
    static let song = SongInfo(
        videoId: "preview0001", title: "A Very Long Track Title That Must Truncate In The Player Bar",
        artist: "Test Artist", album: "Test Album", duration: 227, elapsed: 67,
        url: URL(string: "https://music.youtube.com/watch?v=preview0001")!)

    static let playlists = [
        Playlist(browseId: "VLLM", title: "Liked music"),
        Playlist(browseId: "VLPL1", title: "Test Playlist 1", subtitle: "Test Owner"),
        Playlist(browseId: "VLPL2", title: "Test Playlist 2", subtitle: "Test Owner"),
    ]

    static let account = AccountInfo(name: "Test User", handle: "@testhandle", avatarURL: nil)

    static let preferences = Preferences(defaults: UserDefaults(suiteName: "RutawavePreview") ?? .standard)

    static func nowPlaying(_ player: PreviewPlayer = PreviewPlayer(), signedIn: Bool = true) -> NowPlayingModel {
        NowPlayingModel(
            player: player, toasts: ToastCenter(), preferences: preferences,
            credentials: { signedIn ? Credentials(cookies: [], authUserIndex: 0) : nil }, client: nil)
    }

    static func details(for song: SongInfo = song) -> TrackDetails {
        TrackDetails(
            videoId: song.videoId, artists: [ItemRef(name: "Test Artist", browseId: "UCpreview")],
            album: ItemRef(name: "Test Album", browseId: "MPREbpreview"), isVideo: false)
    }

    static let songs: [Song] = (1...8).map { index in
        Song(
            videoId: "preview\(index)", title: "Track \(index) With A Fairly Long Name", artists: [ItemRef(name: "Test Artist", browseId: "UCpreview")],
            album: ItemRef(name: "Test Album", browseId: "MPREbpreview"), duration: "3:\(10 + index)", isExplicit: index % 3 == 0,
            rank: ChartRank(position: index, trend: [.up, .down, .neutral, nil][index % 4]))
    }

    static let cardItems: [MusicItem] = [
        .album(Album(browseId: "MPREb1", title: "Test Album", subtitle: "Album • Test Artist", playTarget: WatchTarget(playlistId: "OLAK1"))),
        .playlist(Playlist(browseId: "RDCLAK1", title: "Test Mix", subtitle: "Mix", playTarget: WatchTarget(playlistId: "RDCLAK1"))),
        .artist(Artist(browseId: "UC1", name: "Test Artist", subtitle: "1.2M subscribers")),
        .song(Song(videoId: "video1", title: "Test Video", subtitle: "Video • Test Artist", isVideo: true)),
    ]

    static let shelves: [Shelf] = [
        Shelf(
            title: nil, layout: .grid,
            items: [
                .link(NavigationLink(title: "New releases", target: .newReleases)),
                .link(NavigationLink(title: "Charts", target: .charts)),
                .link(NavigationLink(title: "Moods & genres", target: .moodsAndGenres)),
            ]),
        Shelf(title: "Quick picks", strapline: "START RADIO FROM A SONG", layout: .rows, items: songs.map(MusicItem.song)),
        Shelf(title: "Mixed for you", strapline: "TEST USER", more: BrowseTarget(browseId: "FEmusic_mixed_for_you"), layout: .cards, items: cardItems + cardItems + cardItems),
        Shelf(title: "Moods & genres", layout: .grid, items: [
            .link(NavigationLink(title: "Chill", target: .moodCategory(params: "p1"), stripeColor: 4288988671)),
            .link(NavigationLink(title: "Commute", target: .moodCategory(params: "p2"), stripeColor: 4294951424)),
            .link(NavigationLink(title: "Energize", target: .moodCategory(params: "p3"))),
        ]),
        Shelf(title: "Top songs", layout: .list, items: songs.map(MusicItem.song)),
    ]

    static let chips = [Chip(title: "Relax"), Chip(title: "Workout", isSelected: true), Chip(title: "Focus"), Chip(title: "Commute")]

    enum BrowseVariant { case signedIn, guest, loading, failing, empty }

    static func browseModel(_ variant: BrowseVariant) -> BrowseModel {
        let items = switch variant {
        case .signedIn: shelves
        case .guest: Array(shelves.dropFirst())
        default: [Shelf]()
        }
        let pageChips = items.isEmpty ? [] : chips
        let loader = BrowseLoader(
            page: { _, _ in
                if variant == .loading { try await Task.sleep(for: .seconds(3600)) }
                if variant == .failing { throw InnerTubeError.unexpectedResponse }
                return ChartsPage(
                    page: BrowsePage(title: nil, chips: pageChips, shelves: Page(items: items, continuation: nil)),
                    countries: [], selectedCountry: nil)
            },
            more: { _, _ in Page(items: [], continuation: nil) })
        return BrowseModel(source: .home(chipParams: nil), loader: loader, credentials: { nil }, preferences: preferences)
    }

    enum EntityVariant { case album, artist, playlist, ownPlaylist, guest, loading, notAvailable, partialError }

    static func entityModel(_ variant: EntityVariant) -> EntityModel {
        let kind: EntityModel.Kind = switch variant {
        case .album: .album(BrowseTarget(browseId: "MPREb1"))
        case .artist: .artist(browseId: "UCpreview")
        default: .playlist(browseId: "VLPL1")
        }
        let tracks = songs.enumerated().map { index, song in
            index == 2 ? Song(videoId: song.videoId, title: song.title, artists: song.artists, album: song.album, duration: song.duration, isAvailable: false) : song
        }
        let cards = cardItems
        let header = PageHeader(
            title: "Test Playlist With A Fairly Long Title", subtitle: "Playlist • 2026", secondSubtitle: "8 songs • 31 minutes",
            description: String(repeating: "A long description sentence. ", count: 12),
            artists: [ItemRef(name: "Test Owner", browseId: "UCpreview")], play: WatchTarget(playlistId: "PL1"))
        let isOwned = variant == .ownPlaylist
        let isPartial = variant == .partialError
        let loader = EntityLoader(
            album: { _, _ in
                AlbumPage(
                    header: header, type: "Album", year: "1997", audioPlaylistId: "OLAK1",
                    tracks: tracks.enumerated().map { AlbumTrack(number: $0 + 1, song: $1) },
                    shelves: [Shelf(title: "Other versions", layout: .cards, items: cards)])
            },
            artist: { _, _ in
                ArtistPage(
                    name: "Test Artist", thumbnailURL: nil, subscriberCountText: "1.2M subscribers", isSubscribed: false,
                    channelId: "UCpreview", shuffle: WatchTarget(playlistId: "RDshuffle"), radio: WatchTarget(playlistId: "RDradio"),
                    shelves: [
                        Shelf(title: "Top songs", more: BrowseTarget(browseId: "VLOLAK1"), layout: .list, items: tracks.prefix(5).map(MusicItem.song)),
                        Shelf(title: "Albums", more: BrowseTarget(browseId: "UCpreview", params: "p"), layout: .cards, items: cards),
                    ],
                    description: String(repeating: "A long description sentence. ", count: 12), viewCountText: "12,345,678 views")
            },
            playlist: { _, _ in
                switch variant {
                case .loading: try await Task.sleep(for: .seconds(3600))
                case .notAvailable: throw InnerTubeError.notAvailable
                default: break
                }
                return PlaylistPage(
                    header: header, tracks: Page(items: tracks, continuation: isPartial ? "t1" : nil), sectionsContinuation: "s1",
                    isOwned: isOwned)
            },
            moreTracks: { _, _ in throw InnerTubeError.unexpectedResponse },
            sections: { _, _ in
                Page(items: [Shelf(title: "Suggestions", layout: .list, items: tracks.suffix(3).map(MusicItem.song))], continuation: nil)
            },
            save: { _, _, _ in }, subscribe: { _, _, _ in }, add: { _, _, _ in })
        let isGuest = variant == .guest
        return EntityModel(
            kind: kind, loader: loader, credentials: { isGuest ? nil : Credentials(cookies: [], authUserIndex: 0) }, toasts: ToastCenter())
    }

    enum SearchVariant { case all, filtered, loading, empty, failing }

    static let searchChips = [
        Chip(title: "Songs", searchParams: "EgWKAQIIAWoK"),
        Chip(title: "Videos", searchParams: "EgWKAQIQAWoK"),
        Chip(title: "Albums", searchParams: "EgWKAQIYAWoK"),
        Chip(title: "Artists", searchParams: "EgWKAQIgAWoK"),
        Chip(title: "Community playlists", searchParams: "EgeKAQQoAEABag"),
    ]

    static func searchModel(_ variant: SearchVariant) -> SearchModel {
        let filtered = variant == .filtered
        let chips = filtered
            ? searchChips.enumerated().map { Chip(title: $1.title, searchParams: $1.searchParams, isSelected: $0 == 0) }
            : searchChips
        let items = songs.prefix(6).map(MusicItem.song) + cardItems
        let filteredItems = songs.map(MusicItem.song)
        let topResult = cardItems[2]
        let loader = SearchLoader(
            suggestions: { _, _ in SearchSuggestions() },
            search: { _, _, _ in
                if variant == .loading { try await Task.sleep(for: .seconds(3600)) }
                if variant == .failing { throw InnerTubeError.unexpectedResponse }
                let page = variant == .empty ? [] : (filtered ? filteredItems : items)
                return SearchResults(
                    chips: chips, topResult: variant == .all ? topResult : nil, items: Page(items: page, continuation: nil),
                    correction: variant == .all
                        ? SearchCorrection(correctedQuery: "radiohead", originalQuery: "radioheed", originalParams: "EgIQAQ%3D%3D") : nil)
            },
            more: { _, _ in Page(items: [], continuation: nil) }, feedback: { _, _ in })
        return SearchModel(
            query: "radiohead", filter: filtered ? searchChips[0].searchParams : nil, chips: variant == .loading ? searchChips : [],
            loader: loader, credentials: { nil })
    }

    enum SearchFieldVariant { case empty, history, suggestions }

    static func searchFieldModel(_ variant: SearchFieldVariant) -> SearchFieldModel {
        let suggestions = SearchSuggestions(
            queries: variant == .suggestions ? ["radiohead", "radio ga ga", "radio"] : [],
            items: variant == .suggestions ? [cardItems[2], cardItems[0]] : [],
            history: variant == .history ? ["daft punk", "boards of canada", "burial"].map { SearchHistoryEntry(query: $0, feedbackToken: $0) } : [])
        let loader = SearchLoader(
            suggestions: { _, _ in suggestions }, search: { _, _, _ in throw InnerTubeError.unexpectedResponse },
            more: { _, _ in Page(items: [], continuation: nil) }, feedback: { _, _ in })
        let model = SearchFieldModel(
            loader: loader, credentials: { Credentials(cookies: [], authUserIndex: 0) }, toasts: ToastCenter(), sleep: { _ in })
        model.focusChanged(true)
        return model
    }

    enum SidebarVariant { case loaded, loading, failed, guest }

    static func sidebarModel(_ variant: SidebarVariant) -> SidebarModel {
        let list = playlists
        let loader = SidebarLoader(
            playlists: { _ in
                if variant == .loading { try await Task.sleep(for: .seconds(3600)) }
                if variant == .failed { throw InnerTubeError.unexpectedResponse }
                return list
            },
            create: { _, _ in "VLNEW" }, delete: { _, _ in }, removeFromLibrary: { _, _ in }, isOwned: { _, _ in false })
        return SidebarModel(
            loader: loader, credentials: { variant == .guest ? nil : Credentials(cookies: [], authUserIndex: 0) }, toasts: ToastCenter())
    }

    enum LibraryVariant { case playlists, songs, albums, artists, empty, loading, failed }

    static func libraryModel(_ variant: LibraryVariant) -> LibraryModel {
        let chips = [
            Chip(title: "Playlists", target: .likedPlaylists), Chip(title: "Songs", target: .likedSongs),
            Chip(title: "Albums", target: .likedAlbums), Chip(title: "Artists", target: .libraryArtists),
            Chip(title: "Subscriptions", target: .librarySubscriptions),
        ]
        let section: BrowseTarget
        let items: [MusicItem]
        switch variant {
        case .playlists, .loading, .failed:
            section = .likedPlaylists
            items = (1...6).map { .playlist(Playlist(browseId: "VLPL\($0)", title: "Test Playlist \($0)", subtitle: "Test Owner")) }
        case .songs:
            section = .likedSongs
            items = songs.map(MusicItem.song)
        case .albums:
            section = .likedAlbums
            items = (1...6).map { .album(Album(browseId: "MPREb\($0)", title: "Test Album \($0)", subtitle: "Album • Test Artist")) }
        case .artists:
            section = .libraryArtists
            items = (1...6).map { .artist(Artist(browseId: "UC\($0)", name: "Test Artist \($0)", subtitle: "\($0)M subscribers")) }
        case .empty:
            section = .likedSongs
            items = []
        }
        let sorts = variant == .playlists
            ? ["Recent activity", "A to Z", "Z to A"].enumerated().map {
                LibrarySort(title: $1, continuation: "p\($0)", isSelected: $0 == 0)
            } : []
        let loader = LibraryLoader(
            page: { _, _ in
                if variant == .loading { try await Task.sleep(for: .seconds(3600)) }
                if variant == .failed { throw InnerTubeError.unexpectedResponse }
                return LibraryPage(sections: chips, sortOptions: sorts, items: Page(items: items, continuation: nil))
            },
            reload: { _, _ in LibraryPage(sections: chips, sortOptions: sorts, items: Page(items: items, continuation: nil)) },
            more: { _, _ in Page(items: [], continuation: nil) }, history: { _ in [] }, feedback: { _, _ in })
        preferences.librarySection = section.browseId
        return LibraryModel(loader: loader, credentials: { Credentials(cookies: [], authUserIndex: 0) }, preferences: preferences)
    }

    enum HistoryVariant { case loaded, empty, loading, failed }

    static func historyModel(_ variant: HistoryVariant) -> HistoryModel {
        let days = [
            HistoryDay(title: "Today", entries: songs.prefix(3).map { HistoryEntry(song: $0, feedbackToken: "tok-\($0.videoId)") }),
            HistoryDay(title: "Yesterday", entries: songs.dropFirst(3).prefix(3).map { HistoryEntry(song: $0, feedbackToken: nil) }),
        ]
        let loader = LibraryLoader(
            page: { _, _ in throw InnerTubeError.unexpectedResponse }, reload: { _, _ in throw InnerTubeError.unexpectedResponse }, more: { _, _ in throw InnerTubeError.unexpectedResponse },
            history: { _ in
                if variant == .loading { try await Task.sleep(for: .seconds(3600)) }
                if variant == .failed { throw InnerTubeError.unexpectedResponse }
                return variant == .empty ? [] : days
            },
            feedback: { _, _ in })
        return HistoryModel(loader: loader, credentials: { Credentials(cookies: [], authUserIndex: 0) }, toasts: ToastCenter())
    }
}
#endif
