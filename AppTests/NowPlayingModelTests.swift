import AppSettings
import Foundation
import InnerTube
import PlayerEngine
import Testing

@MainActor
private final class FakePlayer: PlayerControlling {
    var song: SongInfo?
    var elapsed: TimeInterval = 0
    var isPaused = false
    var isReady = true
    var isBuffering = false
    var isAd = false
    var volume = 0.5
    var isMuted = false
    var like: LikeStatus = .indifferent
    var repeatMode: RepeatMode = .off
    var isShuffled = false
    var queue: [PlayerQueueItem] = []
    private(set) var sent: [PlayerCommand] = []
    private var continuation: AsyncStream<PlayerEvent>.Continuation?

    func send(_ command: PlayerCommand) { sent.append(command) }

    func events() -> AsyncStream<PlayerEvent> {
        let (stream, continuation) = AsyncStream<PlayerEvent>.makeStream()
        self.continuation = continuation
        return stream
    }

    func emit(_ event: PlayerEvent) { continuation?.yield(event) }
}

@MainActor
private struct Harness {
    let player = FakePlayer()
    let toasts = ToastCenter()
    let preferences: Preferences
    let model: NowPlayingModel
    var task: Task<Void, Never>?

    init(
        signedIn: Bool = false, preferences: Preferences? = nil,
        client: InnerTubeClient? = nil, resolve: (@MainActor (WatchTarget, Credentials?) async throws -> String?)? = nil
    ) {
        let prefs = preferences ?? Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        self.preferences = prefs
        let credentials = Credentials(cookies: [], authUserIndex: 0)
        model = NowPlayingModel(
            player: player, toasts: toasts, preferences: prefs,
            credentials: { signedIn ? credentials : nil }, client: client, resolveFirstVideo: resolve)
    }

    mutating func start() async {
        let model = model
        task = Task { await model.run() }
        await settle()
    }

    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

private func item(_ id: String, current: Bool) -> PlayerQueueItem {
    PlayerQueueItem(videoId: id, title: "T", artist: "A", artworkURL: nil, duration: 1, isCurrent: current)
}

private func song(_ id: String) -> SongInfo {
    SongInfo(videoId: id, title: "T", artist: "A", duration: 1, url: URL(string: "https://music.youtube.com/watch?v=\(id)")!)
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(6), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

@MainActor
struct NowPlayingModelTests {
    @Test func sendsSavedVolumeAtLaunch() async {
        var h = Harness()
        h.preferences.volume = 0.3
        await h.start()
        #expect(h.player.sent == [.setVolume(0.3)])
    }

    @Test func restoresRepeatAndShuffleOncePerPageLoad() async {
        var h = Harness()
        h.preferences.repeatMode = "one"
        h.preferences.shuffle = true
        await h.start()
        h.player.emit(.ready)
        h.player.emit(.repeatChanged(.off))
        h.player.emit(.shuffleChanged(false))
        h.player.emit(.repeatChanged(.all))
        h.player.emit(.shuffleChanged(true))
        await h.settle()
        #expect(h.player.sent == [.setVolume(1), .cycleRepeat, .cycleRepeat, .toggleShuffle])
    }

    @Test func doesNotRestoreBeforeReady() async {
        var h = Harness()
        h.preferences.repeatMode = "all"
        await h.start()
        h.player.emit(.repeatChanged(.off))
        await h.settle()
        #expect(h.player.sent == [.setVolume(1)])
    }

    @Test func userActionsPersistOnlyWhenReady() {
        let h = Harness()
        h.player.repeatMode = .off
        h.model.cycleRepeat()
        h.model.toggleShuffle()
        h.model.setVolume(0.4)
        #expect(h.preferences.repeatMode == "all")
        #expect(h.preferences.shuffle)
        #expect(h.preferences.volume == 0.4)

        let cold = Harness()
        cold.player.isReady = false
        cold.model.cycleRepeat()
        cold.model.toggleShuffle()
        cold.model.setVolume(0.2)
        #expect(cold.preferences.repeatMode == "off")
        #expect(!cold.preferences.shuffle)
        #expect(cold.preferences.volume == 1)
        #expect(cold.player.sent == [.cycleRepeat, .toggleShuffle, .setVolume(0.2)])
    }

    @Test func guestLikeAndDislikePromptInsteadOfSending() {
        let h = Harness(signedIn: false)
        h.model.toggleLike()
        #expect(h.model.likePrompt == .like)
        h.model.toggleDislike()
        #expect(h.model.likePrompt == .dislike)
        #expect(h.player.sent.isEmpty)
    }

    @Test func signedInLikeTogglesBackToIndifferent() {
        let h = Harness(signedIn: true)
        h.model.toggleLike()
        h.player.like = .like
        h.model.toggleLike()
        h.model.toggleDislike()
        #expect(h.player.sent == [.setLike(.like), .setLike(.indifferent), .setLike(.dislike)])
        #expect(h.model.likePrompt == nil)
    }

    @Test func adjustVolumeStepsFromCurrentLevel() {
        let h = Harness()
        h.player.volume = 0.5
        h.model.adjustVolume(steps: 2)
        #expect(h.player.sent == [.setVolume(0.6)])
    }

    @Test func unavailableTrackShowsToastAndSkipsAfterDelay() async {
        var h = Harness()
        h.player.queue = [item("a", current: true), item("b", current: false)]
        await h.start()
        h.player.emit(.error(.unavailable(videoId: "a")))
        await h.settle()
        #expect(h.toasts.message != nil)
        #expect(!h.player.sent.contains(.next))
        #expect(await waitUntil { h.player.sent.contains(.next) })
    }

    @Test func unavailableLastTrackShowsToastButDoesNotSkip() async {
        var h = Harness()
        h.player.queue = [item("a", current: false), item("b", current: true)]
        await h.start()
        h.player.emit(.error(.unavailable(videoId: "b")))
        await h.settle()
        #expect(h.toasts.message != nil)
        #expect(await !waitUntil(timeout: .seconds(3.5)) { h.player.sent.contains(.next) })
    }

    @Test func userActionCancelsPendingSkip() async {
        var h = Harness()
        h.player.queue = [item("a", current: true), item("b", current: false)]
        await h.start()
        h.player.emit(.error(.unavailable(videoId: "a")))
        await h.settle()
        h.model.togglePlay()
        #expect(await !waitUntil(timeout: .seconds(3.5)) { h.player.sent.contains(.next) })
        #expect(h.player.sent.contains(.togglePlay))
    }

    @Test func differentSongCancelsPendingSkip() async {
        var h = Harness()
        h.player.queue = [item("a", current: true), item("b", current: false)]
        await h.start()
        h.player.emit(.error(.unavailable(videoId: "a")))
        h.player.emit(.songChanged(song("b")))
        await h.settle()
        #expect(await !waitUntil(timeout: .seconds(3.5)) { h.player.sent.contains(.next) })
    }

    @Test func allUnavailableQueueStopsSkippingUnderRepeatAll() async {
        var h = Harness()
        h.player.queue = [item("a", current: true), item("b", current: false)]
        h.player.repeatMode = .all
        await h.start()
        h.player.emit(.error(.unavailable(videoId: "a")))
        #expect(await waitUntil { h.player.sent.contains(.next) })
        h.player.emit(.error(.unavailable(videoId: "b")))
        await h.settle()
        #expect(await !waitUntil(timeout: .seconds(3.5)) { h.player.sent.filter { $0 == .next }.count > 1 })
    }

    @Test func songAndVideoLoadWithTheirPlaylist() {
        let h = Harness()
        h.model.play(.song(Song(videoId: "s1", playlistId: "PL1", title: "T")))
        h.model.play(.song(Song(videoId: "v1", title: "V", isVideo: true)))
        #expect(h.player.sent == [.load(videoId: "s1", playlistId: "PL1"), .load(videoId: "v1", playlistId: nil)])
    }

    @Test func startRadioFallsBackToTheSongRadioId() {
        let h = Harness()
        h.model.startRadio(Song(videoId: "s1", title: "T"))
        h.model.startRadio(Song(videoId: "s2", playlistId: "RDX", title: "T"))
        #expect(h.player.sent == [.load(videoId: "s1", playlistId: "RDAMVMs1"), .load(videoId: "s2", playlistId: "RDX")])
    }

    @Test func playlistOnlyAlbumResolvesItsFirstTrack() async {
        var requested: WatchTarget?
        let h = Harness(resolve: { target, _ in
            requested = target
            return "first"
        })
        h.model.play(.album(Album(browseId: "MPREb1", title: "A", playTarget: WatchTarget(playlistId: "OLAK1", params: "wAEB"))))
        #expect(await waitUntil { !h.player.sent.isEmpty })
        #expect(h.player.sent == [.load(videoId: "first", playlistId: "OLAK1")])
        #expect(requested == WatchTarget(playlistId: "OLAK1", params: "wAEB"))
    }

    @Test func playlistCardFallsBackToItsBrowseId() async {
        var requested: WatchTarget?
        let h = Harness(resolve: { target, _ in
            requested = target
            return "first"
        })
        h.model.play(.playlist(Playlist(browseId: "VLPL1", title: "P")))
        #expect(await waitUntil { !h.player.sent.isEmpty })
        #expect(requested == WatchTarget(playlistId: "PL1"))
    }

    @Test func resetClearsRowRatings() {
        let h = Harness(signedIn: true, client: InnerTubeClient())
        h.model.rate(videoId: "v1", .like)
        #expect(h.model.rowRatings["v1"] == .like)
        h.model.resetAccountState()
        #expect(h.model.rowRatings.isEmpty)
    }

    @Test func rateWithoutCredentialsDoesNotWrite() {
        let h = Harness(signedIn: false, client: InnerTubeClient())
        h.model.rate(videoId: "v1", .like)
        #expect(h.model.rowRatings.isEmpty)
    }

    @Test func resetCancelsAPendingCollectionPlay() async {
        let h = Harness(resolve: { _, _ in
            try? await Task.sleep(for: .milliseconds(50))
            return "first"
        })
        h.model.play(.album(Album(browseId: "MPREb1", title: "A", playTarget: WatchTarget(playlistId: "OLAK1"))))
        h.model.resetAccountState()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(h.player.sent.isEmpty)
    }

    @Test func targetWithAVideoLoadsDirectly() {
        let h = Harness(resolve: { _, _ in Issue.record("resolver must not run"); return nil })
        h.model.play(.playlist(Playlist(browseId: "RD1", title: "Mix", playTarget: WatchTarget(videoId: "v9", playlistId: "RD1"))))
        #expect(h.player.sent == [.load(videoId: "v9", playlistId: "RD1")])
    }

    @Test func failedOrEmptyResolveShowsAToastAndSendsNothing() async {
        let empty = Harness(resolve: { _, _ in nil })
        empty.model.play(.album(Album(browseId: "MPREb1", title: "A", playTarget: WatchTarget(playlistId: "OLAK1"))))
        #expect(await waitUntil { empty.toasts.message != nil })
        #expect(empty.player.sent.isEmpty)

        let failing = Harness(resolve: { _, _ in throw URLError(.notConnectedToInternet) })
        failing.model.play(.album(Album(browseId: "MPREb1", title: "A", playTarget: WatchTarget(playlistId: "OLAK1"))))
        #expect(await waitUntil { failing.toasts.message != nil })
        #expect(failing.player.sent.isEmpty)

        let noTarget = Harness()
        noTarget.model.play(.album(Album(browseId: "MPREb1", title: "A")))
        #expect(noTarget.toasts.message != nil)
    }

    @Test func artistAndLinkDoNotPlay() {
        let h = Harness()
        h.model.play(.artist(Artist(browseId: "UC1", name: "N")))
        h.model.play(.link(NavigationLink(title: "L", target: BrowseTarget(browseId: "FEx"))))
        #expect(h.player.sent.isEmpty)
    }
}
