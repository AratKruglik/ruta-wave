import Foundation
import Testing
@testable import PlayerEngine

@MainActor
struct PlayerEngineTests {
    private func makeSong(_ id: String = "abc") -> SongInfo {
        SongInfo(videoId: id, title: "T", artist: "A", album: nil, artworkURL: nil, duration: 100,
                 elapsed: 0, isPaused: false, playlistId: nil, url: URL(string: "https://music.youtube.com/watch?v=\(id)")!)
    }

    private func makeEngine() -> PlayerEngine { PlayerEngine { _ in true } }

    @Test func timeUpdateKeepsSong() {
        let engine = makeEngine()
        let song = makeSong()
        engine.commit(song)
        let event = engine.handle(.time(12))
        #expect(event == .timeChanged(12))
        #expect(engine.song == song)
        #expect(engine.elapsed == 12)
    }

    @Test func readyAndPlayback() {
        let engine = makeEngine()
        #expect(engine.handle(.ready) == .ready)
        #expect(engine.isReady)
        #expect(engine.handle(.playback(isPaused: false, elapsed: 3)) == .playbackChanged(isPaused: false, elapsed: 3))
        #expect(!engine.isPaused)
        #expect(engine.elapsed == 3)
    }

    @Test func duplicateVideoIdEmitsNothing() {
        let engine = makeEngine()
        engine.commit(makeSong("abc"))
        #expect(engine.handle(.song(makeSong("abc"), artworkWithQuery: nil)) == nil)
    }

    @Test func songMessageCommitsAfterArtworkResolves() async throws {
        let engine = makeEngine()
        var iterator = engine.events().makeAsyncIterator()
        _ = engine.handle(.song(makeSong("xyz"), artworkWithQuery: nil))
        let event = await iterator.next()
        guard case .songChanged(let song) = event else { Issue.record("expected songChanged"); return }
        #expect(song.videoId == "xyz")
        #expect(engine.song?.videoId == "xyz")
    }

    @Test func eventsFanOutToAllConsumers() async {
        let engine = makeEngine()
        var first = engine.events().makeAsyncIterator()
        var second = engine.events().makeAsyncIterator()
        _ = engine.handle(.ready)
        #expect(await first.next() == .ready)
        #expect(await second.next() == .ready)
    }

    @Test func loadBeforeStartIsIgnored() {
        let engine = makeEngine()
        engine.load(videoId: "abc", playlistId: nil)
        #expect(engine.webView == nil)
    }

    @Test func unchangedLikeStatusEmitsNothing() {
        let engine = makeEngine()
        #expect(engine.handle(.like(.indifferent, videoId: nil)) == nil)
        #expect(engine.handle(.like(.like, videoId: nil)) == .likeChanged(.like))
        #expect(engine.handle(.like(.like, videoId: nil)) == nil)
        #expect(engine.like == .like)
    }

    @Test func newMessagesUpdateStateAndEmitOneEvent() {
        let engine = makeEngine()
        #expect(engine.handle(.volume(0.4, muted: true)) == .volumeChanged(volume: 0.4, isMuted: true))
        #expect(engine.volume == 0.4 && engine.isMuted)
        #expect(engine.handle(.like(.like, videoId: nil)) == .likeChanged(.like))
        #expect(engine.like == .like)
        #expect(engine.handle(.repeatMode(.all)) == .repeatChanged(.all))
        #expect(engine.repeatMode == .all)
        #expect(engine.handle(.shuffle(true)) == .shuffleChanged(true))
        #expect(engine.isShuffled)
        let items = [QueueItem(videoId: "abc", title: "T", artist: "A", artworkURL: nil, duration: 1, isCurrent: true)]
        #expect(engine.handle(.queue(items)) == .queueChanged(items))
        #expect(engine.queue == items)
        #expect(engine.handle(.ad(true)) == .adChanged(true))
        #expect(engine.isAd)
        #expect(engine.handle(.unavailable(videoId: "abc")) == .error(.unavailable(videoId: "abc")))
    }

    @Test func guestLikeIsRefusedWithoutCallingRate() async {
        let engine = makeEngine()
        var calls = 0
        engine.rate = { _, _ in calls += 1 }
        engine.commit(makeSong())
        var iterator = engine.events().makeAsyncIterator()
        engine.send(.setLike(.like))
        #expect(await iterator.next() == .error(.signInRequired))
        #expect(calls == 0)
        #expect(engine.like == .indifferent)
    }

    @Test func signedInLikeGoesThroughRate() async {
        let engine = makeEngine()
        engine.isEphemeral = false
        var rated: [String] = []
        engine.rate = { id, _ in rated.append(id) }
        engine.commit(makeSong("abc"))
        var iterator = engine.events().makeAsyncIterator()
        engine.send(.setLike(.dislike))
        #expect(await iterator.next() == .likeChanged(.dislike))
        #expect(rated == ["abc"])
        #expect(engine.like == .dislike)
        #expect(engine.handle(.like(.indifferent, videoId: "abc")) == nil)
        #expect(engine.like == .dislike)
        #expect(engine.handle(.like(.like, videoId: "def")) == .likeChanged(.like))
    }

    @Test func commandsBeforeStartAreIgnored() {
        let engine = makeEngine()
        engine.send(.play)
        engine.send(.seek(to: 10))
        engine.send(.removeQueueItem(index: 0))
        #expect(engine.webView == nil)
    }
}
