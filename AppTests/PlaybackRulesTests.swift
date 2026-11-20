import Foundation
import PlayerEngine
import Testing

struct PlaybackRulesTests {
    @Test(arguments: [
        (RepeatMode.off, RepeatMode.off, 0), (.off, .all, 1), (.off, .one, 2),
        (.all, .off, 2), (.all, .all, 0), (.all, .one, 1),
        (.one, .off, 1), (.one, .all, 2), (.one, .one, 0),
    ])
    func repeatSteps(from: RepeatMode, to: RepeatMode, steps: Int) {
        #expect(PlaybackRules.repeatSteps(from: from, to: to) == steps)
    }

    private func queue(currentIndex: Int?, count: Int) -> [QueueItem] {
        (0..<count).map {
            QueueItem(videoId: "v\($0)", title: "T", artist: "A", artworkURL: nil, duration: 1, isCurrent: $0 == currentIndex)
        }
    }

    @Test func skipsWhenNotLast() {
        #expect(PlaybackRules.shouldSkipUnavailable(queue: queue(currentIndex: 0, count: 3), repeatMode: .off))
    }

    @Test func stopsAtLastUnlessRepeatAll() {
        let last = queue(currentIndex: 2, count: 3)
        #expect(!PlaybackRules.shouldSkipUnavailable(queue: last, repeatMode: .off))
        #expect(!PlaybackRules.shouldSkipUnavailable(queue: last, repeatMode: .one))
        #expect(PlaybackRules.shouldSkipUnavailable(queue: last, repeatMode: .all))
    }

    @Test func doesNotSkipWithoutKnownCurrent() {
        #expect(!PlaybackRules.shouldSkipUnavailable(queue: [], repeatMode: .all))
        #expect(!PlaybackRules.shouldSkipUnavailable(queue: queue(currentIndex: nil, count: 2), repeatMode: .all))
    }

    @Test func volumeStepsClamp() {
        #expect(PlaybackRules.volume(0.5, steppedBy: 1) == 0.55)
        #expect(PlaybackRules.volume(0.97, steppedBy: 1) == 1)
        #expect(PlaybackRules.volume(0.02, steppedBy: -1) == 0)
        #expect(PlaybackRules.volume(0.3, steppedBy: 3) == 0.45)
    }

    @Test func formatsTime() {
        #expect(PlaybackRules.formatTime(7) == "0:07")
        #expect(PlaybackRules.formatTime(227) == "3:47")
        #expect(PlaybackRules.formatTime(3723) == "1:02:03")
        #expect(PlaybackRules.formatTime(-5) == "0:00")
        #expect(PlaybackRules.formatTime(.infinity) == "0:00")
        #expect(PlaybackRules.formatTime(1e300) == "277777:46:39")
        #expect(PlaybackRules.formatRemaining(7, duration: 227) == "-3:40")
        #expect(PlaybackRules.formatRemaining(300, duration: 227) == "-0:00")
    }
}
