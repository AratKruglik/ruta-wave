import Foundation
import PlayerEngine
import Testing

@testable import SystemKit

struct TrackNotificationRulesTests {
    static func song(_ id: String) -> SongInfo {
        NowPlayingRulesTests.song(id)
    }

    static func apply(_ events: [PlayerEvent], from state: TrackNotificationState = .init()) -> (TrackNotificationState, [String]) {
        var state = state
        var announced: [String] = []
        for event in events {
            let result = TrackNotificationRules.reduce(state, event)
            state = result.state
            if let song = result.announce { announced.append(song.videoId) }
        }
        return (state, announced)
    }

    @Test func aNewTrackIsAnnouncedOnce() {
        let (_, announced) = Self.apply([.songChanged(Self.song("a")), .songChanged(Self.song("a")), .songChanged(Self.song("b"))])
        #expect(announced == ["a", "b"])
    }

    @Test func aReloadAfterStopDoesNotRepeat() {
        let (_, announced) = Self.apply([.songChanged(Self.song("a")), .stopped, .songChanged(Self.song("a"))])
        #expect(announced == ["a"])
    }

    @Test func theRestoredTrackIsSkipped() {
        var state = TrackNotificationState()
        state.announcedVideoId = "a"
        let (_, announced) = Self.apply([.songChanged(Self.song("a")), .songChanged(Self.song("b"))], from: state)
        #expect(announced == ["b"])
    }

    @Test func aTrackThatStartsUnderAnAdIsAnnouncedWhenTheAdEnds() {
        let (state, announced) = Self.apply([.adChanged(true), .songChanged(Self.song("a"))])
        #expect(announced.isEmpty)
        #expect(state.pending?.videoId == "a")
        let (_, afterAd) = Self.apply([.adChanged(false)], from: state)
        #expect(afterAd == ["a"])
    }

    @Test func stoppedDropsThePendingTrackButKeepsTheAnnouncedOne() {
        let (state, announced) = Self.apply([.songChanged(Self.song("a")), .adChanged(true), .songChanged(Self.song("b")), .stopped])
        #expect(announced == ["a"])
        #expect(state.pending == nil)
        #expect(!state.isAd)
        #expect(state.announcedVideoId == "a")
    }

    @Test func aStopDuringAnAdDoesNotMuteTheNextSession() {
        let (_, announced) = Self.apply([.adChanged(true), .stopped, .songChanged(Self.song("b"))])
        #expect(announced == ["b"])
    }

    @Test(arguments: [
        (true, false, NotificationAuthorization.authorized, true),
        (false, false, .authorized, false),
        (true, true, .authorized, false),
        (true, false, .denied, false),
        (true, false, .notDetermined, false),
    ])
    func shouldPost(isEnabled: Bool, isFrontmost: Bool, authorization: NotificationAuthorization, expected: Bool) {
        #expect(TrackNotificationRules.shouldPost(isEnabled: isEnabled, isFrontmost: isFrontmost, authorization: authorization) == expected)
    }

    @Test func artworkRulesRefuseUnsafeSources() {
        #expect(TrackNotificationRules.isAcceptableArtwork(URL(string: "https://i.ytimg.com/a.jpg")!))
        #expect(!TrackNotificationRules.isAcceptableArtwork(URL(string: "http://i.ytimg.com/a.jpg")!))
        #expect(!TrackNotificationRules.isAcceptableArtwork(URL(string: "https://example.com/a.jpg")!))
        #expect(TrackNotificationRules.isAcceptableImage(mimeType: "image/jpeg", byteCount: 1000))
        #expect(!TrackNotificationRules.isAcceptableImage(mimeType: "text/html", byteCount: 1000))
        #expect(!TrackNotificationRules.isAcceptableImage(mimeType: nil, byteCount: 1000))
        #expect(!TrackNotificationRules.isAcceptableImage(mimeType: "image/png", byteCount: TrackNotificationRules.maxArtworkBytes + 1))
        #expect(!TrackNotificationRules.isAcceptableImage(mimeType: "image/png", byteCount: 0))
    }
}
