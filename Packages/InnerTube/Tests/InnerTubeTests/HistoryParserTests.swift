import Testing
@testable import InnerTube

@Suite struct HistoryParserTests {
    @Test func daysKeepOrderAndTitles() throws {
        let days = try [HistoryDay](history: Fixture.json("history"))
        #expect(days.map(\.title) == ["Today", "Yesterday"])
        #expect(days.map(\.entries.count) == [2, 1])
    }

    @Test func rowsCarryTheRemovalToken() throws {
        let today = try [HistoryDay](history: Fixture.json("history"))[0]
        #expect(today.entries.map(\.feedbackToken) == ["PLACEHOLDER_FEEDBACK_1", "PLACEHOLDER_FEEDBACK_2"])
        #expect(today.entries.map(\.song.isVideo) == [false, true])
        #expect(today.entries.allSatisfy { !$0.song.videoId.isEmpty })
    }

    @Test func rowWithoutATokenIsKept() throws {
        let yesterday = try [HistoryDay](history: Fixture.json("history"))[1]
        #expect(yesterday.entries.map(\.feedbackToken) == [nil])
    }

    @Test func guestHistoryHasNoDays() throws {
        #expect(try [HistoryDay](history: Fixture.json("history-guest")).isEmpty)
    }

    @Test func unknownRootIsUnexpected() {
        #expect(throws: InnerTubeError.unexpectedResponse) { try [HistoryDay](history: JSONValue.object([:])) }
    }
}
