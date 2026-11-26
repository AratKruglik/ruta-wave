import Foundation
import Testing
@testable import PlayerEngine

struct BridgeCallTests {
    private func item(_ id: String, current: Bool = false, setId: String? = nil) -> QueueItem {
        QueueItem(videoId: id, title: "T", artist: "A", artworkURL: nil, duration: 1, isCurrent: current, playlistSetVideoId: setId)
    }

    private var queue: [QueueItem] { [item("aaa", current: true, setId: "S1"), item("bbb"), item("ccc", setId: "S3")] }

    @Test func volumeIsClampedAndScaled() throws {
        #expect(try #require(PlayerRules.bridgeCall(for: .setVolume(0.5), queue: [])).args as? [Double] == [50])
        #expect(try #require(PlayerRules.bridgeCall(for: .setVolume(7), queue: [])).args as? [Double] == [100])
        #expect(try #require(PlayerRules.bridgeCall(for: .setVolume(-3), queue: [])).args as? [Double] == [0])
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteVolumeIsRefused(_ volume: Double) {
        #expect(PlayerRules.bridgeCall(for: .setVolume(volume), queue: []) == nil)
    }

    @Test func seekArguments() throws {
        let to = try #require(PlayerRules.bridgeCall(for: .seek(to: 30), queue: []))
        #expect(to.action == "seekTo" && to.args as? [Double] == [30])
        let by = try #require(PlayerRules.bridgeCall(for: .skip(by: -10), queue: []))
        #expect(by.action == "seekBy" && by.args as? [Double] == [-10])
        #expect(PlayerRules.bridgeCall(for: .seek(to: -1), queue: []) == nil)
        #expect(PlayerRules.bridgeCall(for: .skip(by: .nan), queue: []) == nil)
    }

    @Test func plainCommandsMapToNamedActions() {
        let expected: [(PlayerCommand, String)] = [
            (.play, "play"), (.pause, "pause"), (.togglePlay, "togglePlay"), (.next, "next"), (.previous, "previous"),
            (.toggleMute, "toggleMute"), (.unmute, "unmute"), (.toggleShuffle, "toggleShuffle"), (.cycleRepeat, "cycleRepeat"),
        ]
        for (command, action) in expected {
            #expect(PlayerRules.bridgeCall(for: command, queue: [])?.action == action)
        }
    }

    @Test func swiftOnlyCommandsAreNotPageCalls() {
        #expect(PlayerRules.bridgeCall(for: .setLike(.like), queue: []) == nil)
        #expect(PlayerRules.bridgeCall(for: .load(videoId: "abc", playlistId: nil), queue: []) == nil)
        #expect(PlayerRules.bridgeCall(for: .resume(videoId: "abc", playlistId: nil, at: 30), queue: []) == nil)
    }

    @Test func queueOperationsCarryRowIdentity() throws {
        let jump = try #require(PlayerRules.bridgeCall(for: .playQueueItem(index: 2), queue: queue))
        #expect(jump.action == "jump")
        #expect(jump.args[0] as? Int == 2 && jump.args[1] as? String == "ccc" && jump.args[2] as? String == "S3")
        let remove = try #require(PlayerRules.bridgeCall(for: .removeQueueItem(index: 1), queue: queue))
        #expect(remove.args[1] as? String == "bbb" && remove.args[2] is NSNull)
        let move = try #require(PlayerRules.bridgeCall(for: .moveQueueItem(from: 2, to: 0), queue: queue))
        #expect(move.action == "move" && move.args[0] as? Int == 2 && move.args[3] as? Int == 0)
    }

    @Test func queueWindowOffsetAddressesPageRows() throws {
        let jump = try #require(PlayerRules.bridgeCall(for: .playQueueItem(index: 2), queue: queue, offset: 600))
        #expect(jump.args[0] as? Int == 602)
        let move = try #require(PlayerRules.bridgeCall(for: .moveQueueItem(from: 2, to: 1), queue: queue, offset: 600))
        #expect(move.args[0] as? Int == 602 && move.args[3] as? Int == 601)
    }

    @Test func upcomingRowsFollowTheCurrentOne() {
        #expect(PlayerRules.upcomingVideoIds(queue) == ["bbb", "ccc"])
        #expect(PlayerRules.upcomingVideoIds([]) == [])
    }

    @Test func staleOrCurrentQueueIndexIsRefused() {
        #expect(PlayerRules.bridgeCall(for: .playQueueItem(index: 3), queue: queue) == nil)
        #expect(PlayerRules.bridgeCall(for: .playQueueItem(index: -1), queue: queue) == nil)
        #expect(PlayerRules.bridgeCall(for: .removeQueueItem(index: 0), queue: queue) == nil)
        #expect(PlayerRules.bridgeCall(for: .removeQueueItem(index: 9), queue: queue) == nil)
        #expect(PlayerRules.bridgeCall(for: .moveQueueItem(from: 0, to: 3), queue: queue) == nil)
    }

    @Test func enqueueValidatesTheID() throws {
        let call = try #require(PlayerRules.bridgeCall(for: .enqueue(videoIds: ["abc", "def"], playNext: true), queue: []))
        #expect(call.args[0] as? [String] == ["abc", "def"] && call.args[1] as? Bool == true)
        #expect(PlayerRules.bridgeCall(for: .enqueue(videoIds: ["abc", "a&b"], playNext: false), queue: []) == nil)
        #expect(PlayerRules.bridgeCall(for: .enqueue(videoIds: [], playNext: false), queue: []) == nil)
        let tooMany = (0...PlayerRules.maxRestoredQueueItems).map { "id\($0)" }
        #expect(PlayerRules.bridgeCall(for: .enqueue(videoIds: tooMany, playNext: false), queue: []) == nil)
    }

    @Test func adRefusesNextAndSeeksOnly() {
        #expect(PlayerRules.isRefusedDuringAd(.next))
        #expect(PlayerRules.isRefusedDuringAd(.seek(to: 1)))
        #expect(PlayerRules.isRefusedDuringAd(.skip(by: 1)))
        #expect(!PlayerRules.isRefusedDuringAd(.pause))
        #expect(!PlayerRules.isRefusedDuringAd(.setVolume(0.5)))
    }

    @Test(arguments: [("3:32", 212.0), ("0:05", 5), ("1:02:03", 3723)])
    func parsesDurations(_ text: String, _ seconds: Double) {
        #expect(PlayerRules.parseDuration(text) == seconds)
    }

    @Test(arguments: ["", "5", "a:bc", "1:-2", "1:2:3:4", ":30", "1:"])
    func rejectsBadDurations(_ text: String) {
        #expect(PlayerRules.parseDuration(text) == nil)
    }
}
