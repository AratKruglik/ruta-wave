import Foundation
import PlayerEngine
import Testing

@testable import SystemKit

@MainActor
struct SystemNowPlayingTests {
    @MainActor final class Recorder {
        var published: [NowPlayingInfo?] = []
        var sent: [PlayerCommand] = []
    }

    private func make(_ recorder: Recorder) -> SystemNowPlaying {
        SystemNowPlaying(send: { recorder.sent.append($0) }, publish: { recorder.published.append($0) })
    }

    private func song(_ id: String) -> SongInfo {
        SongInfo(
            videoId: id, title: "T", artist: "A", artworkURL: URL(string: "https://i.ytimg.com/x.jpg"), duration: 100,
            url: URL(string: "https://music.youtube.com/watch?v=\(id)")!)
    }

    @Test func remoteCommandsReachSendWhenPlaying() {
        let recorder = Recorder()
        let service = make(recorder)
        service.handle(.songChanged(song("a")))
        let commands: [PlayerCommand] = [.play, .pause, .next, .previous, .seek(to: 5)]
        for command in commands { service.handle(.remoteCommand(command)) }
        #expect(recorder.sent == commands)
    }

    @Test func commandsAreRefusedWhenStopped() {
        let recorder = Recorder()
        let service = make(recorder)
        #expect(!service.perform(.play))
        service.handle(.songChanged(song("a")))
        service.handle(.stopped)
        service.handle(.remoteCommand(.togglePlay))
        #expect(recorder.sent.isEmpty)
    }

    @Test func nextAndSeekRefusedDuringAdButPauseAllowed() {
        let recorder = Recorder()
        let service = make(recorder)
        service.handle(.songChanged(song("a")))
        service.handle(.adChanged(true))
        for command in [PlayerCommand.next, .seek(to: 1)] { #expect(!service.perform(command)) }
        #expect(service.perform(.pause))
        #expect(recorder.sent == [.pause])
    }

    @Test func remoteCommandIsNotPublished() {
        let recorder = Recorder()
        let service = make(recorder)
        service.handle(.songChanged(song("a")))
        let count = recorder.published.count
        service.handle(.remoteCommand(.pause))
        #expect(recorder.published.count == count)
    }

    @Test func albumForOtherVideoIsIgnored() {
        let recorder = Recorder()
        let service = make(recorder)
        service.handle(.songChanged(song("a")))
        let count = recorder.published.count
        service.setAlbum("X", for: "other")
        #expect(recorder.published.count == count)
    }

    @Test func albumForCurrentVideoRepublishes() {
        let recorder = Recorder()
        let service = make(recorder)
        service.handle(.songChanged(song("a")))
        service.setAlbum("X", for: "a")
        #expect(recorder.published.last??.album == "X")
    }

    @Test func timeTicksAreNotPublishedButSeekIsWithNewElapsed() {
        let recorder = Recorder()
        let service = make(recorder)
        service.handle(.songChanged(song("a")))
        let baseline = recorder.published.count
        for t in [1.0, 2.0, 3.0] { service.handle(.timeChanged(t)) }
        #expect(recorder.published.count == baseline)
        service.handle(.playbackChanged(isPaused: false, elapsed: 80))
        #expect(recorder.published.count == baseline + 1)
        #expect(recorder.published.last??.elapsed == 80)
    }

    @Test func restartOfSameTrackResetsPublishedElapsed() {
        let recorder = Recorder()
        let service = make(recorder)
        service.handle(.songChanged(song("a")))
        service.handle(.playbackChanged(isPaused: false, elapsed: 90))
        service.handle(.playbackChanged(isPaused: false, elapsed: 0))
        #expect(recorder.published.last??.elapsed == 0)
    }

    @Test func adNeverLeaksIntoPublishedPositionAndTrackResumesAfter() {
        let recorder = Recorder()
        let service = make(recorder)
        service.handle(.songChanged(song("a")))
        service.handle(.timeChanged(40))
        service.handle(.adChanged(true))
        service.handle(.timeChanged(3))
        service.handle(.playbackChanged(isPaused: false, elapsed: 4))
        #expect(recorder.published.last??.elapsed == 40)
        #expect(recorder.published.last??.isPlaying == false)
        service.handle(.adChanged(false))
        service.handle(.playbackChanged(isPaused: false, elapsed: 41))
        #expect(recorder.published.last??.elapsed == 41)
        #expect(recorder.published.last??.isPlaying == true)
    }

    @Test func stoppedPublishesNil() {
        let recorder = Recorder()
        let service = make(recorder)
        service.handle(.songChanged(song("a")))
        service.handle(.stopped)
        #expect(recorder.published.last == .some(nil))
    }
}
