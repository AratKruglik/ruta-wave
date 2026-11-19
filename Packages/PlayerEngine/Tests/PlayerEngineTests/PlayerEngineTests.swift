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
}
