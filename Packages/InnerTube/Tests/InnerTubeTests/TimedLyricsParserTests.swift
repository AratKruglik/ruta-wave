import Foundation
import Testing
@testable import InnerTube

@Suite struct TimedLyricsParserTests {
    private static func answer(_ lines: [(text: String, start: String?)], ends: [String?] = []) -> Data {
        let rows = lines.enumerated().map { index, line in
            let end = index < ends.count ? ends[index].map { #","endTimeMilliseconds":"\#($0)""# } ?? "" : ""
            let cue = line.start.map { #","cueRange":{"startTimeMilliseconds":"\#($0)"\#(end)}"# } ?? ""
            return #"{"lyricLine":"\#(line.text)"\#(cue)}"#
        }
        let model = #"{"timedLyricsModel":{"lyricsData":{"timedLyricsData":[\#(rows.joined(separator: ","))],"sourceMessage":"Source: Test"}}}"#
        return Data(#"{"contents":{"elementRenderer":{"newElement":{"type":{"componentType":{"model":\#(model)}}}}}}"#.utf8)
    }

    @Test func timedFixtureGivesAscendingLines() throws {
        let lyrics = try #require(try TimedLyricsParser.parse(Fixture.data("timed-lyrics")))
        #expect(lyrics.lines.count == 8)
        #expect(lyrics.lines.first?.text == "Placeholder line 1")
        #expect(lyrics.lines.first?.start == 0.17)
        #expect(lyrics.lines.first?.end == 7.12)
        #expect(lyrics.lines.first?.words.isEmpty == false)
        #expect(lyrics.timing == .estimated)
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

    @Test func endsFallBackToTheNextStart() throws {
        let data = Self.answer([("a b", "1000"), ("c d", "3000"), ("e f", "5000"), ("g h", "7000")], ends: ["1000", "2500", "9000", "soon"])
        let lines = try #require(try TimedLyricsParser.parse(data)).lines
        #expect(lines[0].end == 3)
        #expect(lines[1].end == 5)
        #expect(lines[2].end == 7)
        #expect(lines[3].end == nil)
        #expect(lines[3].words.isEmpty)
    }

    @Test func nonStringEndFallsBackToTheNextStart() throws {
        let json = try #require(String(data: Self.answer([("a b", "1000"), ("c", "3000")], ends: ["2000"]), encoding: .utf8))
        let data = Data(json.replacingOccurrences(of: "\"endTimeMilliseconds\":\"2000\"", with: "\"endTimeMilliseconds\":2000").utf8)
        let lines = try #require(try TimedLyricsParser.parse(data)).lines
        #expect(lines.count == 2)
        #expect(lines[0].end == 3)
    }

    @Test func lastLineWithoutEndIsLineOnly() throws {
        let lines = try #require(try TimedLyricsParser.parse(Self.answer([("a", "1000")]))).lines
        #expect(lines[0].end == nil)
        #expect(lines[0].words.isEmpty)
    }

    @Test func estimatesWordsByLength() {
        let words = WordTiming.estimate("a bb cccc", start: 10, end: 14)
        #expect(words.map(\.text) == ["a", "bb", "cccc"])
        let cuts: [Double] = [10, 10 + 4.0 / 7, 10 + 12.0 / 7, 14]
        #expect(words.map(\.start) == Array(cuts.dropLast()))
        #expect(words.map(\.end) == Array(cuts.dropFirst()))
    }

    @Test func estimateEdges() {
        #expect(WordTiming.estimate("", start: 0, end: 5).isEmpty)
        #expect(WordTiming.estimate("  a   b  ", start: 0, end: 2).map(\.text) == ["a", "b"])
        #expect(WordTiming.estimate("solo", start: 1, end: 3) == [.init(text: "solo", start: 1, end: 3)])
        #expect(WordTiming.estimate("hi, you!", start: 0, end: 1).map(\.text) == ["hi,", "you!"])
    }

    @Test func positionLookup() {
        let first = TimedLyrics.Line(text: "a b", start: 10, end: 14, words: WordTiming.estimate("a b", start: 10, end: 14))
        let second = TimedLyrics.Line(text: "plain", start: 20)
        let lyrics = TimedLyrics(lines: [first, second], source: nil)
        #expect(lyrics.position(at: 9) == nil)
        #expect(lyrics.position(at: 10) == .init(line: 0, word: 0))
        #expect(lyrics.position(at: 12) == .init(line: 0, word: 1))
        #expect(lyrics.position(at: 16) == .init(line: 0, word: nil))
        #expect(lyrics.position(at: 20) == .init(line: 1, word: nil))
        #expect(lyrics.position(at: 99) == .init(line: 1, word: nil))
    }

    @Test func wordProgressIsClamped() {
        let word = TimedLyrics.Word(text: "a", start: 2, end: 4)
        #expect(word.progress(at: 1) == 0)
        #expect(word.progress(at: 3) == 0.5)
        #expect(word.progress(at: 9) == 1)
        #expect(TimedLyrics.Word(text: "a", start: 2, end: 2).progress(at: 2) == 1)
    }

    private static let enhanced = """
    [ar:Placeholder]
    [00:10.00]<00:10.00>one <00:10.50>two <00:11.20>three<00:12.00>
    [00:13.00]<00:13.00>four <00:13.40>five
    """

    @Test func enhancedLRCGivesMeasuredWords() throws {
        let lyrics = try #require(EnhancedLRCParser.parse(Self.enhanced))
        #expect(lyrics.timing == .measured)
        #expect(lyrics.lines.count == 2)
        #expect(lyrics.lines[0].words.map(\.text) == ["one", "two", "three"])
        #expect(lyrics.lines[0].words.map(\.start) == [10, 10.5, 11.2])
        #expect(lyrics.lines[0].end == 12)
        #expect(lyrics.lines[1].words.last?.end == 13.4)
    }

    @Test func enhancedLRCMeetsTheDriftTarget() throws {
        let lyrics = try #require(EnhancedLRCParser.parse(Self.enhanced))
        let words = lyrics.lines[0].words
        #expect(lyrics.position(at: words[0].start + 0.149) == .init(line: 0, word: 0))
        #expect(lyrics.position(at: words[1].start) == .init(line: 0, word: 1))
    }

    @Test func enhancedLRCWithoutWordTagsIsEstimated() throws {
        let lyrics = try #require(EnhancedLRCParser.parse("[00:01.00]a b\n[00:03.00]<bad>c d\n[x]skip\n[00:05.00]  "))
        #expect(lyrics.timing == .estimated)
        #expect(lyrics.lines.map(\.text) == ["a b", "c d"])
        #expect(lyrics.lines[0].words.map(\.start) == [1, 2])
        #expect(EnhancedLRCParser.parse("") == nil)
        #expect(EnhancedLRCParser.parse("[ar:x]") == nil)
    }

    @Test func positionAtLineEndAndAfterLastLineEnd() {
        let line = TimedLyrics.Line(text: "a b", start: 10, end: 14, words: WordTiming.estimate("a b", start: 10, end: 14))
        let lyrics = TimedLyrics(lines: [line], source: nil)
        #expect(lyrics.position(at: 13.999) == .init(line: 0, word: 1))
        #expect(lyrics.position(at: 14) == .init(line: 0, word: nil))
        #expect(lyrics.position(at: 500) == .init(line: 0, word: nil))
    }

    @Test func sameStartLinesLoseTheZeroLengthOneToLineOnly() throws {
        let data = Self.answer([("a b", "1000"), ("c d", "1000")], ends: ["2000", "3000"])
        let lines = try #require(try TimedLyricsParser.parse(data)).lines
        #expect(lines.count == 2)
        #expect(lines.filter { $0.words.isEmpty }.count == 1)
    }

    @Test func enhancedLRCSortsRowsAndReadsThreeDigitFractions() throws {
        let lyrics = try #require(EnhancedLRCParser.parse("[01:05.000]<01:05.000>late\n[01:02.250]<01:02.250>early <01:02.750>bird"))
        #expect(lyrics.lines.map(\.text) == ["early bird", "late"])
        #expect(lyrics.lines[0].words.map(\.start) == [62.25, 62.75])
        #expect(lyrics.lines[0].words[1].end == 65)
    }

    @Test func enhancedLRCIgnoresInvalidLineTags() {
        #expect(EnhancedLRCParser.parse("[00:5.5]a\n[00:60.00]b\n[-1:00.00]c\n[00:01.00.00]d\n[999999999999999999:00.00]e\n[00:01.-5]f") == nil)
    }

    @Test func enhancedLRCKeepsLeadingTextAndDropsMalformedWordTags() throws {
        let lead = try #require(EnhancedLRCParser.parse("[00:01.00]lead <00:02.00>tail"))
        #expect(lead.lines[0].words.map(\.text) == ["lead", "tail"])
        #expect(lead.lines[0].words.map(\.start) == [1, 2])
        let bad = try #require(EnhancedLRCParser.parse("[00:01.00]<00:01.00>a <zz>b <00:02.00>c"))
        #expect(bad.lines[0].text == "a b c")
        #expect(bad.lines[0].words.map(\.text) == ["a b", "c"])
    }

    @Test func enhancedLRCMixedLinesAreEstimated() throws {
        let lyrics = try #require(EnhancedLRCParser.parse("[00:01.00]<00:01.00>a <00:01.50>b\n[00:03.00]c d"))
        #expect(lyrics.timing == .estimated)
        #expect(lyrics.lines[0].words.map(\.start) == [1, 1.5])
        #expect(lyrics.lines[1].words.isEmpty)
    }
}
