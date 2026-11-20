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

    init(signedIn: Bool = false, preferences: Preferences? = nil) {
        let prefs = preferences ?? Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        self.preferences = prefs
        let credentials = Credentials(cookies: [], authUserIndex: 0)
        model = NowPlayingModel(
            player: player, toasts: toasts, preferences: prefs,
            credentials: { signedIn ? credentials : nil }, client: nil)
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
}
