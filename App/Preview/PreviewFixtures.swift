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
}
#endif
