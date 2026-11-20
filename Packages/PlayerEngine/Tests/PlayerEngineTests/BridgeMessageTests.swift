import Foundation
import Testing
@testable import PlayerEngine

struct BridgeMessageTests {
    @Test func decodesKnownTypes() {
        #expect(BridgeMessage.decode(#"{"type":"ready"}"#) == .ready)
        #expect(BridgeMessage.decode(#"{"type":"time","time":4.5}"#) == .time(4.5))
        #expect(BridgeMessage.decode(#"{"type":"playback","paused":true,"time":1}"#) == .playback(isPaused: true, elapsed: 1))
    }

    @Test func decodesSong() throws {
        let body = #"{"type":"song","videoDetails":{"videoId":"abc","title":"T (Official Video)","author":"A"}}"#
        guard case .song(let song, _) = try #require(BridgeMessage.decode(body)) else { Issue.record("not a song"); return }
        #expect(song.title == "T")
    }

    @Test(arguments: [
        #"{"type":"unknown"}"#, #"{"type":"time"}"#, #"{"type":"time","time":-1}"#,
        #"{"type":"playback","time":1}"#, #"{"type":"song","videoDetails":{"videoId":"a&b","title":"T","author":"A"}}"#,
        #"{"type":"song"}"#, "not json", "",
    ])
    func dropsMalformed(_ body: String) {
        #expect(BridgeMessage.decode(body) == nil)
    }

    @Test func dropsNonFiniteTime() {
        #expect(BridgeMessage.decode(#"{"type":"time","time":1e999}"#) == nil)
    }

    @Test func dropsNonStringBody() {
        #expect(BridgeMessage.decode(["type": "ready"]) == nil)
        #expect(BridgeMessage.decode(42) == nil)
    }

    @Test func dropsOversizeBody() {
        let body = #"{"type":"ready","pad":""# + String(repeating: "a", count: BridgeMessage.maxBytes) + #""}"#
        #expect(BridgeMessage.decode(body) == nil)
    }
}

struct NewBridgeMessageTests {
    private func queueBody(rows: Int, override: String? = nil) -> String {
        let row = override ?? #"{"videoId":"abc","title":"T","artist":"A","length":"3:00"}"#
        return #"{"type":"queue","items":["# + Array(repeating: row, count: rows).joined(separator: ",") + "]}"
    }

    @Test func decodesNewTypes() {
        #expect(BridgeMessage.decode(#"{"type":"volume","volume":50,"muted":true}"#) == .volume(0.5, muted: true))
        #expect(BridgeMessage.decode(#"{"type":"like","status":"DISLIKE"}"#) == .like(.dislike))
        #expect(BridgeMessage.decode(#"{"type":"repeat","repeatMode":"ONE"}"#) == .repeatMode(.one))
        #expect(BridgeMessage.decode(#"{"type":"shuffle","shuffle":true}"#) == .shuffle(true))
        #expect(BridgeMessage.decode(#"{"type":"ad","ad":true}"#) == .ad(true))
        #expect(BridgeMessage.decode(#"{"type":"error","kind":"unavailable","videoId":"abc"}"#) == .unavailable(videoId: "abc"))
    }

    @Test(arguments: [
        #"{"type":"volume","volume":101,"muted":false}"#, #"{"type":"volume","volume":-1,"muted":false}"#,
        #"{"type":"volume","volume":1e999,"muted":false}"#, #"{"type":"volume","volume":5}"#,
        #"{"type":"like","status":"MAYBE"}"#, #"{"type":"like"}"#,
        #"{"type":"repeat","repeatMode":"all"}"#, #"{"type":"shuffle"}"#, #"{"type":"ad"}"#,
        #"{"type":"error","kind":"other","videoId":"abc"}"#, #"{"type":"error","kind":"unavailable","videoId":"a&b"}"#,
        #"{"type":"error","kind":"unavailable"}"#,
    ])
    func dropsMalformedNewTypes(_ body: String) {
        #expect(BridgeMessage.decode(body) == nil)
    }

    @Test func decodesQueueFixture() throws {
        let url = try #require(Bundle.module.url(forResource: "queue", withExtension: "json", subdirectory: "Fixtures"))
        let body = try String(contentsOf: url, encoding: .utf8)
        guard case .queue(let items) = try #require(BridgeMessage.decode(body)) else { Issue.record("not a queue"); return }
        #expect(items.map(\.videoId) == ["aaaaaaaaaaa", "bbbbbbbbbbb", "ccccccccccc"])
        #expect(items.map(\.isCurrent) == [true, false, false])
        #expect(items.map(\.duration) == [212, 3723, 0])
        #expect(items[0].artworkURL != nil)
        #expect(items[0].playlistSetVideoId == "SET1")
    }

    @Test func acceptsExactlyMaxQueueRows() {
        guard case .queue(let items)? = BridgeMessage.decode(queueBody(rows: PlayerRules.maxQueueItems)) else {
            Issue.record("expected queue"); return
        }
        #expect(items.count == PlayerRules.maxQueueItems)
    }

    @Test func rejectsTooManyRows() {
        #expect(BridgeMessage.decode(queueBody(rows: PlayerRules.maxQueueItems + 1)) == nil)
    }

    @Test(arguments: [
        #"{"videoId":"a&b","title":"T","artist":"A"}"#, #"{"videoId":"abc","title":"T","artist":"A","length":"x:yz"}"#,
        #"{"videoId":"abc","title":"T","artist":"A","length":"-1:00"}"#, #"{"videoId":"abc","title":"T"}"#,
    ])
    func oneBadRowRejectsWholeQueue(_ row: String) {
        let body = #"{"type":"queue","items":[{"videoId":"abc","title":"T","artist":"A"},"# + row + "]}"
        #expect(BridgeMessage.decode(body) == nil)
    }

    @Test func dropsOversizeQueue() {
        let row = #"{"videoId":"abc","title":"\#(String(repeating: "x", count: 2000))","artist":"A"}"#
        #expect(BridgeMessage.decode(queueBody(rows: 200, override: row)) == nil)
    }

    @Test func capsLongNamesAndDropsForeignArtwork() throws {
        let row = #"{"videoId":"abc","title":"\#(String(repeating: "x", count: 2000))","artist":"A","artwork":"https://evil.example/a.jpg"}"#
        guard case .queue(let items)? = BridgeMessage.decode(queueBody(rows: 1, override: row)) else { Issue.record("expected queue"); return }
        #expect(items[0].title.utf8.count == 1024)
        #expect(items[0].artworkURL == nil)
    }
}
