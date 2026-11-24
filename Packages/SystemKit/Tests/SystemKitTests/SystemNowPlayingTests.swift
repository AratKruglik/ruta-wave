import AppKit
import Foundation
import MediaPlayer
import PlayerEngine
import Testing

@testable import SystemKit

@MainActor
struct SystemNowPlayingTests {
    @MainActor final class Recorder {
        var published: [(info: [String: Any]?, state: MPNowPlayingPlaybackState)] = []
        var sent: [PlayerCommand] = []
        var fetched: [URL] = []
    }

    private func make(
        _ recorder: Recorder, fetch: @escaping @Sendable (URL) async -> Data? = { _ in nil }
    ) -> SystemNowPlaying {
        SystemNowPlaying(
            send: { recorder.sent.append($0) }, publish: { recorder.published.append(($0, $1)) }, fetchArtwork: fetch)
    }

    private func song(_ id: String, artwork: String = "https://i.ytimg.com/x.jpg") -> SongInfo {
        SongInfo(
            videoId: id, title: "T", artist: "A", artworkURL: URL(string: artwork), duration: 100,
            url: URL(string: "https://music.youtube.com/watch?v=\(id)")!)
    }

    @Test func commandsReachSendWhenPlaying() {
        let recorder = Recorder()
        let service = make(recorder)
        service.handle(.songChanged(song("a")))
        let commands: [PlayerCommand] = [.play, .pause, .togglePlay, .next, .previous, .seek(to: 5), .skip(by: 10), .skip(by: -10)]
        for command in commands { #expect(service.perform(command) == .success) }
        #expect(recorder.sent == commands)
    }

    @Test func commandsAreRefusedWhenStopped() {
        let recorder = Recorder()
        let service = make(recorder)
        #expect(service.perform(.play) == .noActionableNowPlayingItem)
        service.handle(.songChanged(song("a")))
        service.handle(.stopped)
        #expect(service.perform(.togglePlay) == .noActionableNowPlayingItem)
        #expect(recorder.sent.isEmpty)
    }

    @Test func nextSeekSkipRefusedDuringAdButToggleAllowed() {
        let recorder = Recorder()
        let service = make(recorder)
        service.handle(.songChanged(song("a")))
        service.handle(.adChanged(true))
        for command in [PlayerCommand.next, .seek(to: 1), .skip(by: 10)] { #expect(service.perform(command) == .commandFailed) }
        #expect(service.perform(.togglePlay) == .success)
        #expect(recorder.sent == [.togglePlay])
    }

    @Test func rejectedArtworkHostIsNeverFetched() async {
        let recorder = Recorder()
        let service = make(recorder) { url in
            await MainActor.run { recorder.fetched.append(url) }
            return nil
        }
        service.handle(.songChanged(song("a", artwork: "https://evil.example/x.jpg")))
        for _ in 0..<20 { await Task.yield() }
        #expect(recorder.fetched.isEmpty)
        service.handle(.songChanged(song("b")))
        for _ in 0..<20 { await Task.yield() }
        #expect(recorder.fetched == [URL(string: "https://i.ytimg.com/x.jpg")!])
    }

    @Test func lateArtworkForPreviousTrackIsDropped() async {
        let recorder = Recorder()
        let gate = Gate()
        let png = Self.pngData()
        let service = make(recorder) { _ in
            await gate.wait()
            return png
        }
        service.handle(.songChanged(song("a")))
        service.handle(.songChanged(song("b", artwork: "https://evil.example/x.jpg")))
        await gate.open()
        for _ in 0..<20 { await Task.yield() }
        #expect(recorder.published.allSatisfy { $0.info?[MPMediaItemPropertyArtwork] == nil })
    }

    @Test func currentArtworkIsPublished() async {
        let recorder = Recorder()
        let png = Self.pngData()
        let service = make(recorder) { _ in png }
        service.handle(.songChanged(song("a")))
        for _ in 0..<20 { await Task.yield() }
        #expect(recorder.published.last?.info?[MPMediaItemPropertyArtwork] != nil)
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
        #expect(recorder.published.last?.info?[MPMediaItemPropertyAlbumTitle] as? String == "X")
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
        #expect(recorder.published.last?.info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 80)
    }

    @Test func restartOfSameTrackResetsPublishedElapsed() {
        let recorder = Recorder()
        let service = make(recorder)
        service.handle(.songChanged(song("a")))
        service.handle(.playbackChanged(isPaused: false, elapsed: 90))
        service.handle(.playbackChanged(isPaused: false, elapsed: 0))
        #expect(recorder.published.last?.info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 0)
    }

    @Test func adNeverLeaksIntoPublishedPositionAndTrackResumesAfter() {
        let recorder = Recorder()
        let service = make(recorder)
        service.handle(.songChanged(song("a")))
        service.handle(.timeChanged(40))
        service.handle(.adChanged(true))
        service.handle(.timeChanged(3))
        service.handle(.playbackChanged(isPaused: false, elapsed: 4))
        #expect(recorder.published.last?.info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 40)
        service.handle(.adChanged(false))
        service.handle(.playbackChanged(isPaused: false, elapsed: 41))
        let info = recorder.published.last?.info
        #expect(info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 41)
        #expect(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1)
    }

    @Test func stoppedPublishesNil() {
        let recorder = Recorder()
        let service = make(recorder)
        service.handle(.songChanged(song("a")))
        service.handle(.stopped)
        #expect(recorder.published.last?.info == nil)
        #expect(recorder.published.last?.state == .stopped)
    }

    private actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isOpen = false
        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }

    private static func pngData() -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }
}
