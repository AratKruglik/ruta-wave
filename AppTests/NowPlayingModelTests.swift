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
private final class TestClock {
    var instant = ContinuousClock.now
    func advance(_ duration: Duration) { instant += duration }
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
        client: InnerTubeClient? = nil, resolve: (@MainActor (WatchTarget, Credentials?) async throws -> String?)? = nil,
        clock: TestClock = TestClock(), rateVideo: (@MainActor (String, Rating, Credentials) async throws -> Void)? = nil,
        watchNext: (@MainActor (WatchTarget, Credentials?) async throws -> WatchNext)? = nil
    ) {
        let prefs = preferences ?? Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        self.preferences = prefs
        let credentials = Credentials(cookies: [])
        var resolveQueue: (@MainActor (WatchTarget, Credentials?) async throws -> [String])?
        if let resolve {
            resolveQueue = { target, credentials in
                let first = try await resolve(target, credentials)
                return first.map { [$0] } ?? []
            }
        }
        model = NowPlayingModel(
            player: player, toasts: toasts, preferences: prefs,
            credentials: { signedIn ? credentials : nil }, client: client,
            resolveQueue: resolveQueue, watchNext: watchNext,
            rateVideo: rateVideo,
            now: { clock.instant })
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

private func nextResponse(for id: String, lyrics: String?, related: String?) -> WatchNext {
    WatchNext(
        queue: Page(items: [QueueItem(song: Song(videoId: id, title: "T"), isCurrent: true, counterpart: nil)], continuation: nil),
        automix: nil, chips: [], playingFrom: nil, playlistId: nil, lyricsBrowseId: lyrics, relatedBrowseId: related)
}

@MainActor
private final class FailSwitch {
    var isOn = true
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

    @Test func performCancelsPendingSkip() async {
        var h = Harness()
        h.player.queue = [item("a", current: true), item("b", current: false)]
        await h.start()
        h.player.emit(.error(.unavailable(videoId: "a")))
        await h.settle()
        h.model.perform(.next)
        #expect(await !waitUntil(timeout: .seconds(3.5)) { h.player.sent.filter { $0 == .next }.count > 1 })
        #expect(h.player.sent.filter { $0 == .next }.count == 1)
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

    @Test func unavailableSongNeverLoads() {
        let h = Harness()
        let song = Song(videoId: "x", title: "x", isAvailable: false)
        h.model.play(.song(song))
        h.model.startRadio(song)
        #expect(h.player.sent.isEmpty)
    }

    @Test func startRadioFallsBackToTheSongRadioId() {
        let h = Harness()
        h.model.startRadio(Song(videoId: "s1", title: "T"))
        h.model.startRadio(Song(videoId: "s2", playlistId: "RDX", title: "T"))
        #expect(h.player.sent == [.load(videoId: "s1", playlistId: "RDAMVMs1"), .load(videoId: "s2", playlistId: "RDX")])
    }

    @Test func doubleClickOnARowLoadsOnce() {
        let clock = TestClock()
        let h = Harness(clock: clock)
        let song = Song(videoId: "s1", playlistId: "PL1", title: "T")
        h.model.play(.song(song))
        clock.advance(.milliseconds(100))
        h.model.play(.song(song))
        #expect(h.player.sent == [.load(videoId: "s1", playlistId: "PL1")])
        clock.advance(.seconds(10))
        h.model.play(.song(song))
        #expect(h.player.sent.count == 2)
    }

    @Test func aDifferentRowIsNeverSuppressed() {
        let h = Harness()
        h.model.play(.song(Song(videoId: "s1", playlistId: "PL1", title: "T")))
        h.model.play(.song(Song(videoId: "s2", playlistId: "PL1", title: "T")))
        #expect(h.player.sent.count == 2)
    }

    @Test func watchTargetWithAVideoLoadsDirectly() {
        let h = Harness()
        h.model.play(WatchTarget(videoId: "v1", playlistId: "PL1"))
        #expect(h.player.sent == [.load(videoId: "v1", playlistId: "PL1")])
    }

    @Test func playlistOnlyWatchTargetResolvesItsFirstTrack() async {
        let h = Harness(resolve: { _, _ in "first" })
        h.model.play(WatchTarget(playlistId: "PL1"))
        #expect(await waitUntil { !h.player.sent.isEmpty })
        #expect(h.player.sent == [.load(videoId: "first", playlistId: "PL1")])
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

    @Test func enqueueShowsItsToastOnlyAfterTheQueueChanges() async {
        var h = Harness()
        h.player.queue = [item("a", current: true)]
        await h.start()
        h.model.enqueue(["x", "y"], playNext: false)
        #expect(h.player.sent.last == .enqueue(videoIds: ["x", "y"], playNext: false))
        #expect(h.toasts.toast == nil)
        h.player.queue = [item("a", current: true), item("x", current: false), item("y", current: false)]
        h.player.emit(.queueChanged(h.player.queue))
        #expect(await waitUntil { h.toasts.toast?.undo != nil })
    }

    @Test func undoOfPlayNextRemovesTheInsertedRowsDescending() async {
        var h = Harness()
        h.player.queue = [item("a", current: true), item("b", current: false)]
        await h.start()
        h.model.enqueue(["x", "y"], playNext: true)
        h.player.queue = [item("a", current: true), item("x", current: false), item("y", current: false), item("b", current: false)]
        h.player.emit(.queueChanged(h.player.queue))
        #expect(await waitUntil { h.toasts.toast != nil })
        h.toasts.undo()
        #expect(h.player.sent.suffix(2) == [.removeQueueItem(index: 2), .removeQueueItem(index: 1)])
    }

    @Test func removeUndoAppendsThenMovesBack() async {
        var h = Harness()
        h.player.queue = [item("a", current: true), item("b", current: false), item("c", current: false)]
        await h.start()
        h.model.removeQueueItem(at: 1)
        h.player.queue = [item("a", current: true), item("c", current: false)]
        h.player.emit(.queueChanged(h.player.queue))
        #expect(await waitUntil { h.toasts.toast != nil })
        h.toasts.undo()
        #expect(h.player.sent.last == .enqueue(videoIds: ["b"], playNext: false))
        h.player.queue = [item("a", current: true), item("c", current: false), item("b", current: false)]
        h.player.emit(.queueChanged(h.player.queue))
        #expect(await waitUntil { h.player.sent.last == .moveQueueItem(from: 2, to: 1) })
    }

    @Test func removingTheCurrentRowIsRefused() {
        let h = Harness()
        h.player.queue = [item("a", current: true)]
        h.model.removeQueueItem(at: 0)
        #expect(h.player.sent.isEmpty)
    }

    @Test func rateAllReportsPartialFailure() async {
        let h = Harness(signedIn: true, rateVideo: { id, _, _ in if id == "bad" { throw URLError(.badServerResponse) } })
        h.model.rateAll(.like) { ["a", "bad", "c"] }
        #expect(await waitUntil { h.toasts.toast != nil })
        #expect(h.model.rowRatings["a"] == .like && h.model.rowRatings["bad"] == nil)
    }

    @Test func queueRowsKeyRepeatedVideosByIndex() {
        let h = Harness()
        h.player.queue = [item("a", current: true), item("a", current: false)]
        let keys = h.model.queueSongs.map(\.playlistSetVideoId)
        #expect(keys == ["q0", "q1"])
        #expect(NowPlayingModel.queueIndex(of: "q1") == 1)
        #expect(NowPlayingModel.queueIndex(of: "x1") == nil)
    }

    @Test func queueEditsAreRefusedWhileAnAdPlaysOrNotReady() {
        let h = Harness()
        h.player.queue = [item("a", current: true), item("b", current: false)]
        h.player.isAd = true
        h.model.enqueue(["x"], playNext: false)
        h.model.removeQueueItem(at: 1)
        h.model.moveQueueItem(from: 1, to: 0)
        h.model.jump(to: 1)
        h.player.isAd = false
        h.player.isReady = false
        h.model.enqueue(["x"], playNext: true)
        #expect(h.player.sent.isEmpty)
    }

    @Test func enqueueingNothingSendsNothing() {
        let h = Harness()
        h.model.enqueue([String](), playNext: false)
        #expect(h.player.sent.isEmpty)
    }

    @Test func undoOfAddToQueueRemovesTheTailDescending() async {
        var h = Harness()
        h.player.queue = [item("a", current: true)]
        await h.start()
        h.model.enqueue(["x", "y"], playNext: false)
        h.player.queue = [item("a", current: true), item("x", current: false), item("y", current: false)]
        h.player.emit(.queueChanged(h.player.queue))
        #expect(await waitUntil { h.toasts.toast != nil })
        h.toasts.undo()
        #expect(h.player.sent.suffix(2) == [.removeQueueItem(index: 2), .removeQueueItem(index: 1)])
    }

    @Test func undoSkipsRowsThatNoLongerMatch() async {
        var h = Harness()
        h.player.queue = [item("a", current: true)]
        await h.start()
        h.model.enqueue(["x"], playNext: false)
        h.player.queue = [item("a", current: true), item("x", current: false)]
        h.player.emit(.queueChanged(h.player.queue))
        #expect(await waitUntil { h.toasts.toast != nil })
        h.player.queue = [item("a", current: true), item("other", current: false)]
        let sentBefore = h.player.sent.count
        h.toasts.undo()
        #expect(h.player.sent.count == sentBefore)
    }

    @Test func removingSeveralRowsSkipsTheCurrentAndShowsOneToastWithoutUndo() async {
        var h = Harness()
        h.player.queue = [item("a", current: true), item("b", current: false), item("c", current: false), item("d", current: false)]
        await h.start()
        h.model.removeQueueItems(at: [0, 1, 3])
        #expect(h.player.sent.suffix(2) == [.removeQueueItem(index: 3), .removeQueueItem(index: 1)])
        #expect(h.toasts.toast == nil)
        h.player.queue = [item("a", current: true), item("c", current: false)]
        h.player.emit(.queueChanged(h.player.queue))
        #expect(await waitUntil { h.toasts.toast != nil })
        #expect(h.toasts.toast?.undo == nil)
    }

    @Test func movingARowShowsUndoThatMovesItBack() async {
        var h = Harness()
        h.player.queue = [item("a", current: true), item("b", current: false), item("c", current: false)]
        await h.start()
        h.model.moveQueueItem(from: 2, to: 1)
        #expect(h.player.sent.last == .moveQueueItem(from: 2, to: 1))
        h.player.queue = [item("a", current: true), item("c", current: false), item("b", current: false)]
        h.player.emit(.queueChanged(h.player.queue))
        #expect(await waitUntil { h.toasts.toast?.undo != nil })
        h.toasts.undo()
        #expect(h.player.sent.last == .moveQueueItem(from: 1, to: 2))
    }

    @Test func playNextMovesARowRightAfterTheCurrentOne() {
        let h = Harness()
        h.player.queue = [item("a", current: false), item("b", current: true), item("c", current: false), item("d", current: false)]
        h.model.playNext(queueIndex: 3)
        #expect(h.player.sent.last == .moveQueueItem(from: 3, to: 2))
        h.model.playNext(queueIndex: 0)
        #expect(h.player.sent.last == .moveQueueItem(from: 0, to: 1))
    }

    @Test func playNextIsANoOpForTheCurrentOrAlreadyNextRow() {
        let h = Harness()
        h.player.queue = [item("a", current: true), item("b", current: false)]
        h.model.playNext(queueIndex: 0)
        h.model.playNext(queueIndex: 1)
        #expect(h.player.sent.isEmpty)
    }

    @Test func aStaleQueueChangeDoesNotFireTheToast() async {
        var h = Harness()
        h.player.queue = [item("a", current: true)]
        await h.start()
        h.model.enqueue(["x"], playNext: false)
        h.player.emit(.queueChanged([item("a", current: true)]))
        await h.settle()
        #expect(h.toasts.toast == nil)
    }

    @Test func draggedTrackIdsAreEnqueuedDirectly() {
        let h = Harness()
        h.player.queue = [item("a", current: true)]
        h.model.enqueue(TrackDrag(videoIds: ["x", "y"]), playNext: true)
        #expect(h.player.sent.last == .enqueue(videoIds: ["x", "y"], playNext: true))
    }

    @Test func aDraggedCardIsResolvedToItsTracksFirst() async {
        var h = Harness(resolve: { target, _ in target.playlistId == "PL9" ? "first" : nil })
        h.player.queue = [item("a", current: true)]
        await h.start()
        h.model.enqueue(TrackDrag(playlistId: "PL9"), playNext: false)
        #expect(await waitUntil { h.player.sent.last == .enqueue(videoIds: ["first"], playNext: false) })
    }

    @Test func aCardThatResolvesToNothingShowsAnError() async {
        let h = Harness(resolve: { _, _ in nil })
        h.model.enqueue(TrackDrag(playlistId: "PL9"), playNext: false)
        #expect(await waitUntil { h.toasts.toast != nil })
        #expect(h.player.sent.isEmpty)
    }

    @Test func anUnavailableSongIsNotEnqueued() {
        let h = Harness()
        h.player.queue = [item("a", current: true)]
        h.model.enqueue(.song(Song(videoId: "u", title: "T", isAvailable: false)), playNext: false)
        #expect(h.player.sent.isEmpty)
    }

    @Test func selectingAChipReloadsTheCurrentSongWithTheChipPlaylist() {
        let h = Harness()
        h.player.song = song("cur")
        h.model.selectChip(QueueChip(title: "Chill", target: WatchTarget(playlistId: "RDX"), isSelected: false))
        #expect(h.player.sent.last == .load(videoId: "cur", playlistId: "RDX"))
    }

    @Test func rateAllAnnouncesFullSuccess() async {
        let h = Harness(signedIn: true, rateVideo: { _, _, _ in })
        h.model.rateAll(.dislike) { ["a", "b"] }
        #expect(await waitUntil { h.model.rowRatings.count == 2 && h.toasts.toast != nil })
    }

    @Test func rateAllDoesNothingForAGuest() async {
        let h = Harness(rateVideo: { _, _, _ in Issue.record("must not rate") })
        h.model.rateAll(.like) { ["a"] }
        await h.settle()
        #expect(h.model.rowRatings.isEmpty && h.toasts.toast == nil)
    }

    @Test func rateAllStopsWhenTheAccountChangesWhileIdsResolve() async {
        var rated = 0
        let h = Harness(signedIn: true, rateVideo: { _, _, _ in rated += 1 })
        var release: CheckedContinuation<Void, Never>?
        h.model.rateAll(.like) {
            await withCheckedContinuation { release = $0 }
            return ["a", "b"]
        }
        #expect(await waitUntil { release != nil })
        h.model.resetAccountState()
        release?.resume()
        await h.settle()
        #expect(rated == 0 && h.toasts.toast == nil)
    }

    @Test func detailsKeepTheLyricsAndRelatedBrowseIds() async {
        let h = Harness(watchNext: { _, _ in nextResponse(for: "a", lyrics: "MPLYt_a", related: "MPTRt_a") })
        h.player.song = song("a")
        await h.model.loadDetails(for: song("a"))
        #expect(h.model.details?.videoId == "a")
        #expect(h.model.details?.lyricsBrowseId == "MPLYt_a")
        #expect(h.model.details?.relatedBrowseId == "MPTRt_a")
        #expect(!h.model.detailsFailed)
    }

    @Test func unselectableLyricsLeaveDetailsWithoutAnId() async {
        let h = Harness(watchNext: { _, _ in nextResponse(for: "a", lyrics: nil, related: "MPTRt_a") })
        h.player.song = song("a")
        var before: TrackDetails?
        let task = Task { await h.model.loadDetails(for: song("a")) }
        before = h.model.details
        await task.value
        #expect(before == nil)
        #expect(h.model.details != nil && h.model.details?.lyricsBrowseId == nil)
    }

    @Test func aSongChangeBeforeTheResponseLeavesNothingBehind() async {
        let h = Harness(watchNext: { _, _ in nextResponse(for: "a", lyrics: "x", related: "y") })
        h.player.song = song("b")
        await h.model.loadDetails(for: song("a"))
        #expect(h.model.details == nil && !h.model.detailsFailed)
    }

    @Test func aSongChangeLoadsDetailsWithoutAnyView() async {
        var requests: [String] = []
        var h = Harness(watchNext: { target, _ in
            requests.append(target.videoId ?? "")
            return nextResponse(for: target.videoId ?? "", lyrics: nil, related: nil)
        })
        var albums: [String] = []
        h.model.albumChanged = { videoId, _ in albums.append(videoId) }
        await h.start()
        h.player.song = song("a")
        h.player.emit(.songChanged(song("a")))
        #expect(await waitUntil { h.model.details?.videoId == "a" })
        #expect(albums == ["a"])
        #expect(requests == ["a"])
    }

    @Test func aNewSongDropsTheEarlierDetailsLoad() async {
        var release: CheckedContinuation<Void, Never>?
        var h = Harness(watchNext: { target, _ in
            if target.videoId == "a" { await withCheckedContinuation { release = $0 } }
            return nextResponse(for: target.videoId ?? "", lyrics: nil, related: nil)
        })
        await h.start()
        h.player.song = song("a")
        h.player.emit(.songChanged(song("a")))
        #expect(await waitUntil { release != nil })
        h.player.song = song("b")
        h.player.emit(.songChanged(song("b")))
        #expect(await waitUntil { h.model.details?.videoId == "b" })
        release?.resume()
        await h.settle()
        #expect(h.model.details?.videoId == "b")
    }

    @Test func stoppingThePlayerClearsTheDetails() async {
        var h = Harness(watchNext: { target, _ in nextResponse(for: target.videoId ?? "", lyrics: nil, related: nil) })
        await h.start()
        h.player.song = song("a")
        h.player.emit(.songChanged(song("a")))
        #expect(await waitUntil { h.model.details != nil })
        h.player.song = nil
        h.player.emit(.stopped)
        #expect(await waitUntil { h.model.details == nil })
        #expect(!h.model.detailsFailed)
    }

    @Test func aFailedNextSetsTheFlagAndTheNextLoadClearsIt() async {
        struct Boom: Error {}
        let fails = FailSwitch()
        let h = Harness(watchNext: { _, _ in
            if fails.isOn { throw Boom() }
            return nextResponse(for: "a", lyrics: "x", related: "y")
        })
        h.player.song = song("a")
        await h.model.loadDetails(for: song("a"))
        #expect(h.model.detailsFailed && h.model.details == nil)
        fails.isOn = false
        await h.model.loadDetails(for: song("a"))
        #expect(!h.model.detailsFailed && h.model.details != nil)
    }
}


@MainActor
struct NetworkRecoveryTests {
    private func harness(paused: Bool, clock: TestClock = TestClock()) -> Harness {
        let harness = Harness(clock: clock)
        harness.player.song = song("a")
        harness.player.isPaused = paused
        return harness
    }

    @Test func playbackResumesOnceAfterAnOutage() {
        let harness = harness(paused: false)
        harness.model.networkChanged(isOnline: false)
        harness.model.networkChanged(isOnline: true)
        harness.model.networkChanged(isOnline: true)
        #expect(harness.player.sent == [.recover])
    }

    @Test func aPausedPlayerStaysPaused() {
        let harness = harness(paused: true)
        harness.model.networkChanged(isOnline: false)
        harness.model.networkChanged(isOnline: true)
        #expect(harness.player.sent.isEmpty)
    }

    @Test func nothingLoadedMeansNothingToRecover() {
        let harness = Harness()
        harness.model.networkChanged(isOnline: false)
        harness.model.networkChanged(isOnline: true)
        #expect(harness.player.sent.isEmpty)
    }

    @Test func aSecondOutageRecoversAgain() {
        let clock = TestClock()
        let harness = harness(paused: false, clock: clock)
        for _ in 0..<2 {
            harness.model.networkChanged(isOnline: false)
            harness.model.networkChanged(isOnline: true)
            clock.advance(.seconds(31))
        }
        #expect(harness.player.sent == [.recover, .recover])
    }

    @Test func reconnectsWithinThirtySecondsRecoverOnce() {
        let clock = TestClock()
        let harness = harness(paused: false, clock: clock)
        for _ in 0..<2 {
            harness.model.networkChanged(isOnline: false)
            harness.model.networkChanged(isOnline: true)
            clock.advance(.seconds(5))
        }
        #expect(harness.player.sent == [.recover])
    }

    @Test func pausingDuringTheOutageSendsNothing() {
        let harness = harness(paused: false)
        harness.model.networkChanged(isOnline: false)
        harness.player.isPaused = true
        harness.model.networkChanged(isOnline: true)
        #expect(harness.player.sent.isEmpty)
    }

    @Test func anAccountSwitchDuringTheOutageSendsNothing() {
        let harness = harness(paused: false)
        harness.model.networkChanged(isOnline: false)
        harness.model.resetAccountState()
        harness.model.networkChanged(isOnline: true)
        #expect(harness.player.sent.isEmpty)
    }

    @Test func goingOnlineWithoutAnOutageSendsNothing() {
        let harness = harness(paused: false)
        harness.model.networkChanged(isOnline: true)
        #expect(harness.player.sent.isEmpty)
    }
}

@MainActor
struct ResumeOnStartTests {
    private func playing(_ id: String, playlistId: String? = "PL1") -> SongInfo {
        SongInfo(videoId: id, title: "T", artist: "A", duration: 300, playlistId: playlistId,
                 url: URL(string: "https://music.youtube.com/watch?v=\(id)")!)
    }

    private func change(_ h: Harness, to song: SongInfo) async {
        h.player.song = song
        h.player.emit(.songChanged(song))
        await h.settle()
    }

    @Test func resumesTheLastTrackPausedAtItsPosition() async {
        var h = Harness()
        h.preferences.lastPlayback = LastPlayback(videoId: "abc", playlistId: "PL1", elapsed: 42)
        await h.start()
        h.model.resumeLastSession()
        #expect(h.player.sent.last == .resume(videoId: "abc", playlistId: "PL1", at: 42))
    }

    @Test func anAccountChangeForgetsTheLastTrack() async {
        var h = Harness()
        h.preferences.lastPlayback = LastPlayback(videoId: "abc", playlistId: "LM", elapsed: 42)
        h.player.song = playing("abc", playlistId: "LM")
        await h.start()
        h.model.resetAccountState()
        #expect(h.preferences.lastPlayback == nil)
        h.player.emit(.timeChanged(60))
        h.player.emit(.playbackChanged(isPaused: true, elapsed: 61))
        await h.settle()
        h.model.savePosition()
        #expect(h.preferences.lastPlayback == nil, "saving a position never brings the old account's track back")
        h.player.song = nil
        h.model.resumeLastSession()
        #expect(!h.player.sent.contains { if case .resume = $0 { true } else { false } })
    }

    @Test func aLinkOpenedBeforeTheStartReplacesTheResume() async {
        var h = Harness()
        h.preferences.lastPlayback = LastPlayback(videoId: "abc", playlistId: nil, elapsed: 42)
        await h.start()
        h.model.openLink(WatchTarget(videoId: "v", playlistId: "PL1"))
        #expect(h.player.sent == [.setVolume(1)])
        h.model.resumeLastSession()
        #expect(h.player.sent.last == .load(videoId: "v", playlistId: "PL1"))
        #expect(!h.player.sent.contains { if case .resume = $0 { true } else { false } })
    }

    @Test func aLinkOpenedAfterTheStartLoadsAtOnce() async {
        var h = Harness()
        await h.start()
        h.model.resumeLastSession()
        h.model.openLink(WatchTarget(videoId: "v"))
        #expect(h.player.sent.last == .load(videoId: "v", playlistId: nil))
    }

    @Test func aPlaylistLinkResolvesItsFirstTrack() async {
        var h = Harness(resolve: { _, _ in "first" })
        await h.start()
        h.model.resumeLastSession()
        h.model.openLink(WatchTarget(playlistId: "RD1"))
        await h.settle()
        #expect(h.player.sent.last == .load(videoId: "first", playlistId: "RD1"))
    }

    @Test func resumesOnlyOncePerLaunch() async {
        var h = Harness()
        h.preferences.lastPlayback = LastPlayback(videoId: "abc", playlistId: nil, elapsed: 42)
        await h.start()
        h.model.resumeLastSession()
        h.model.resumeLastSession()
        #expect(h.player.sent.filter { if case .resume = $0 { true } else { false } }.count == 1)
    }

    @Test func doesNotResumeWhenSwitchedOff() async {
        var h = Harness()
        h.preferences.resumeOnStart = false
        h.preferences.lastPlayback = LastPlayback(videoId: "abc", playlistId: nil, elapsed: 42)
        await h.start()
        h.model.resumeLastSession()
        #expect(h.player.sent == [.setVolume(1)])
    }

    @Test func doesNotReplaceATrackThatIsAlreadyPlaying() async {
        var h = Harness()
        h.preferences.lastPlayback = LastPlayback(videoId: "abc", playlistId: nil, elapsed: 42)
        h.player.song = playing("xyz")
        await h.start()
        h.model.resumeLastSession()
        #expect(h.player.sent == [.setVolume(1)])
    }

    @Test func remembersTheTrackAndItsPosition() async {
        var h = Harness()
        await h.start()
        await change(h, to: playing("abc"))
        #expect(h.preferences.lastPlayback == LastPlayback(videoId: "abc", playlistId: "PL1", elapsed: 0))
        h.player.emit(.timeChanged(3))
        await h.settle()
        #expect(h.preferences.lastPlayback?.elapsed == 0, "saved every few seconds, not on every tick")
        h.player.emit(.timeChanged(6))
        await h.settle()
        #expect(h.preferences.lastPlayback?.elapsed == 6)
        h.player.emit(.playbackChanged(isPaused: true, elapsed: 7.5))
        await h.settle()
        #expect(h.preferences.lastPlayback?.elapsed == 7.5)
        await change(h, to: playing("def", playlistId: nil))
        #expect(h.preferences.lastPlayback == LastPlayback(videoId: "def", playlistId: nil, elapsed: 0))
    }

    @Test func savePositionWritesTheCurrentTime() async {
        var h = Harness()
        await h.start()
        await change(h, to: playing("abc"))
        h.player.elapsed = 12
        h.model.savePosition()
        #expect(h.preferences.lastPlayback?.elapsed == 12)
    }

    @Test func adTimeIsNotSaved() async {
        var h = Harness()
        await h.start()
        await change(h, to: playing("abc"))
        h.player.isAd = true
        h.player.emit(.timeChanged(20))
        await h.settle()
        #expect(h.preferences.lastPlayback?.elapsed == 0)
    }

    @Test func positionBeforeTheResumeSeekIsNotSaved() async {
        var h = Harness()
        h.preferences.lastPlayback = LastPlayback(videoId: "abc", playlistId: "PL1", elapsed: 42)
        await h.start()
        h.model.resumeLastSession()
        await change(h, to: playing("abc"))
        #expect(h.preferences.lastPlayback?.elapsed == 42, "the resumed track keeps its saved position")
        h.player.emit(.playbackChanged(isPaused: true, elapsed: 0.4))
        await h.settle()
        #expect(h.preferences.lastPlayback?.elapsed == 42)
        h.player.emit(.playbackChanged(isPaused: true, elapsed: 42))
        h.player.emit(.timeChanged(50))
        await h.settle()
        #expect(h.preferences.lastPlayback?.elapsed == 50)
    }
}
