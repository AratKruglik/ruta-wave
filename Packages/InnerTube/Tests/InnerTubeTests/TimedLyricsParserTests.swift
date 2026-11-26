import Foundation
import Testing
@testable import InnerTube

@Suite struct TimedLyricsParserTests {
    private static func answer(_ lines: [(text: String, start: String?)]) -> Data {
        let rows = lines.map { line in
            let cue = line.start.map { #","cueRange":{"startTimeMilliseconds":"\#($0)"}"# } ?? ""
            return #"{"lyricLine":"\#(line.text)"\#(cue)}"#
        }
        let model = #"{"timedLyricsModel":{"lyricsData":{"timedLyricsData":[\#(rows.joined(separator: ","))],"sourceMessage":"Source: Test"}}}"#
        return Data(#"{"contents":{"elementRenderer":{"newElement":{"type":{"componentType":{"model":\#(model)}}}}}}"#.utf8)
    }

    @Test func timedFixtureGivesAscendingLines() throws {
        let lyrics = try #require(try TimedLyricsParser.parse(Fixture.data("timed-lyrics")))
        #expect(lyrics.lines.count == 8)
        #expect(lyrics.lines.first == .init(text: "Placeholder line 1", start: 0.17))
        #expect(lyrics.lines.map(\.start) == lyrics.lines.map(\.start).sorted())
        #expect(lyrics.source == "Source: Musixmatch")
    }

    @Test func linesWithoutTimesAreNil() throws {
        #expect(try TimedLyricsParser.parse(Fixture.data("timed-lyrics-untimed")) == nil)
    }

    @Test func messageIsNil() throws {
        #expect(try TimedLyricsParser.parse(Fixture.data("timed-lyrics-none")) == nil)
    }

    @Test func unknownShapeIsUnexpected() {
        #expect(throws: InnerTubeError.unexpectedResponse) { try TimedLyricsParser.parse(Data(#"{"contents":{}}"#.utf8)) }
        #expect(throws: InnerTubeError.unexpectedResponse) { try TimedLyricsParser.parse(Data("nope".utf8)) }
    }

    @Test func nonNumericStartIsUnexpected() {
        #expect(throws: InnerTubeError.unexpectedResponse) { try TimedLyricsParser.parse(Self.answer([("a", "soon")])) }
        for start in ["nan", "1e3", "-1"] {
            #expect(throws: InnerTubeError.unexpectedResponse) { try TimedLyricsParser.parse(Self.answer([("a", start)])) }
        }
    }

    @Test func zeroLinesIsNil() throws {
        #expect(try TimedLyricsParser.parse(Self.answer([])) == nil)
    }

    @Test func blankLinesAreDroppedAndOrderIsSorted() throws {
        let lyrics = try #require(try TimedLyricsParser.parse(Self.answer([("b", "2000"), ("  ", "1500"), ("a", "1000")])))
        #expect(lyrics.lines.map(\.text) == ["a", "b"])
        #expect(lyrics.lines.map(\.start) == [1, 2])
    }

    @Test func lineIndexFindsTheLastStartedLine() {
        let lyrics = TimedLyrics(lines: [.init(text: "a", start: 1), .init(text: "b", start: 3)], source: nil)
        #expect(TimedLyrics(lines: [], source: nil).lineIndex(at: 5) == nil)
        #expect(lyrics.lineIndex(at: 0.5) == nil)
        #expect(lyrics.lineIndex(at: 1) == 0)
        #expect(lyrics.lineIndex(at: 2.9) == 0)
        #expect(lyrics.lineIndex(at: 3) == 1)
        #expect(lyrics.lineIndex(at: 99) == 1)
    }
}
