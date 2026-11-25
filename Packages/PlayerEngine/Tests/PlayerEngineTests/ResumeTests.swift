import Foundation
import Testing
@testable import PlayerEngine

@MainActor
struct ResumeTests {
    private func makeSong(_ id: String = "abc") -> SongInfo {
        SongInfo(videoId: id, title: "T", artist: "A", album: nil, artworkURL: nil, duration: 100,
                 elapsed: 0, isPaused: true, playlistId: "PL1", url: URL(string: "https://music.youtube.com/watch?v=\(id)")!)
    }

    private func makeEngine() -> PlayerEngine { PlayerEngine { _ in true } }

    @Test func resumeWithoutAPlayerDoesNothing() {
        let engine = makeEngine()
        engine.resume(videoId: "abc", playlistId: nil, at: 42)
        #expect(engine.target == nil)
        #expect(engine.resumeAt == nil)
        #expect(!engine.holdsPause)
    }

    @Test func holdEndsOnceTheResumedTrackIsPausedAtItsPosition() {
        let engine = makeEngine()
        engine.target = ("abc", nil)
        engine.resumeAt = 42
        engine.holdsPause = true
        _ = engine.handle(.playback(isPaused: true, elapsed: 0))
        #expect(engine.holdsPause, "the track is not committed yet")
        engine.commit(makeSong())
        #expect(engine.resumeAt == nil)
        _ = engine.handle(.playback(isPaused: true, elapsed: 42))
        #expect(!engine.holdsPause)
    }

    @Test func playbackStartedDuringTheHoldKeepsIt() {
        let engine = makeEngine()
        engine.target = ("abc", nil)
        engine.holdsPause = true
        engine.commit(makeSong())
        _ = engine.handle(.playback(isPaused: false, elapsed: 0))
        #expect(engine.holdsPause)
    }

    @Test(arguments: [PlayerCommand.play, .togglePlay, .next, .previous, .playQueueItem(index: 0)])
    func userPlaybackCommandsEndTheHold(_ command: PlayerCommand) {
        let engine = makeEngine()
        engine.holdsPause = true
        engine.send(command)
        #expect(!engine.holdsPause)
    }

    @Test(arguments: [PlayerCommand.seek(to: 10), .setVolume(0.5), .toggleMute])
    func otherCommandsKeepTheHold(_ command: PlayerCommand) {
        let engine = makeEngine()
        engine.holdsPause = true
        engine.send(command)
        #expect(engine.holdsPause)
    }

    @Test func stopEndsTheHold() {
        let engine = makeEngine()
        engine.holdsPause = true
        engine.stop()
        #expect(!engine.holdsPause)
    }

    @Test func resumeHasNoBridgeCall() {
        #expect(PlayerRules.bridgeCall(for: .resume(videoId: "abc", playlistId: nil, at: 1), queue: []) == nil)
    }
}
