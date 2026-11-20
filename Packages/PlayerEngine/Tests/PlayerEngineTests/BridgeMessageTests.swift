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
