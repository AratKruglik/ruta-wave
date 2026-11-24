import Foundation
import PlayerEngine
import Testing

@testable import SystemKit

struct NowPlayingRulesTests {
    static func song(_ id: String = "a", duration: TimeInterval = 200, paused: Bool = false) -> SongInfo {
        SongInfo(
            videoId: id, title: "T", artist: "A", artworkURL: URL(string: "https://i.ytimg.com/x.jpg"),
            duration: duration, isPaused: paused, url: URL(string: "https://music.youtube.com/watch?v=\(id)")!)
    }

    static func playing(_ id: String = "a") -> NowPlayingState {
        NowPlayingRules.reduce(nil, .songChanged(song(id))).state!
    }

    @Test func songChangedBuildsFullState() {
        let result = NowPlayingRules.reduce(nil, .songChanged(Self.song(paused: true)))
        #expect(result.publish)
        #expect(result.state?.title == "T")
        #expect(result.state?.artist == "A")
        #expect(result.state?.duration == 200)
        #expect(result.state?.elapsed == 0)
        #expect(result.state?.isPaused == true)
    }

    @Test func playbackChangedSetsRateAndElapsed() {
        let playing = NowPlayingRules.reduce(Self.playing(), .playbackChanged(isPaused: false, elapsed: 12))
        let info = NowPlayingRules.info(playing.state!)
        #expect(playing.publish)
        #expect(info.isPlaying)
        #expect(info.elapsed == 12)
        let paused = NowPlayingRules.reduce(playing.state, .playbackChanged(isPaused: true, elapsed: 13))
        #expect(!NowPlayingRules.info(paused.state!).isPlaying)
    }

    @Test func plainTimeTickDoesNotPublishButUpdatesElapsed() {
        let tick = NowPlayingRules.reduce(Self.playing(), .timeChanged(5))
        #expect(!tick.publish)
        #expect(tick.state?.elapsed == 5)
    }

    @Test func adFreezesPositionAndRate() {
        var state = NowPlayingRules.reduce(Self.playing(), .timeChanged(30)).state
        state = NowPlayingRules.reduce(state, .adChanged(true)).state
        state = NowPlayingRules.reduce(state, .timeChanged(2)).state
        state = NowPlayingRules.reduce(state, .playbackChanged(isPaused: false, elapsed: 3)).state
        let info = NowPlayingRules.info(state!)
        #expect(state?.elapsed == 30)
        #expect(!info.isPlaying)
        #expect(info.title == "T")
        state = NowPlayingRules.reduce(state, .adChanged(false)).state
        state = NowPlayingRules.reduce(state, .playbackChanged(isPaused: false, elapsed: 31)).state
        #expect(state?.elapsed == 31)
        #expect(NowPlayingRules.info(state!).isPlaying)
    }

    @Test func stoppedClearsState() {
        let result = NowPlayingRules.reduce(Self.playing(), .stopped)
        #expect(result.state == nil)
        #expect(result.publish)
    }

    @Test func eventsBeforeAnySongStayCleared() {
        for event in [PlayerEvent.ready, .playbackChanged(isPaused: false, elapsed: 1), .timeChanged(1), .adChanged(true)] {
            let result = NowPlayingRules.reduce(nil, event)
            #expect(result.state == nil)
            #expect(!result.publish)
        }
    }

    @Test(arguments: [PlayerError.contentProcessCrashed, .playerTimeout])
    func crashPausesExtrapolation(_ error: PlayerError) {
        let playing = NowPlayingRules.reduce(Self.playing(), .playbackChanged(isPaused: false, elapsed: 4)).state
        let result = NowPlayingRules.reduce(playing, .error(error))
        #expect(result.publish)
        #expect(!NowPlayingRules.info(result.state!).isPlaying)
    }

    @Test func albumOnlyWhenPresent() {
        var state = Self.playing()
        #expect(NowPlayingRules.info(state).album == nil)
        state.album = "Al"
        #expect(NowPlayingRules.info(state).album == "Al")
    }
}
