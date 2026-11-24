import Testing
@testable import InnerTube

@Suite struct LyricsParserTests {
    @Test func textKeepsBlankLinesAndUsesNewlinesOnly() throws {
        let lyrics = try #require(try LyricsParser.parse(Fixture.json("lyrics")))
        #expect(lyrics.text == "Placeholder line 1\nPlaceholder line 2\n\nPlaceholder line 3")
        #expect(!lyrics.text.contains("\r"))
        #expect(lyrics.source == "Source: LyricFind")
    }

    @Test func noLyricsIsNil() throws {
        #expect(try LyricsParser.parse(Fixture.json("lyrics-none")) == nil)
    }

    @Test func unknownRootIsUnexpected() {
        #expect(throws: InnerTubeError.unexpectedResponse) { try LyricsParser.parse(JSONValue.object(["contents": .object([:])])) }
    }

    @Test func relatedParsesThroughBrowsePage() throws {
        let page = try BrowsePage(browse: Fixture.json("related"))
        #expect(page.shelves.items.count == 3)
        #expect(page.shelves.items.first?.title == "You might also like")
        #expect(page.shelves.items.first?.layout == .rows)
        #expect(page.about?.title == "About the artist")
        #expect(page.about?.text.contains("Radiohead are an English rock band") == true)
        #expect(page.about?.text.contains("CC-BY-SA") == true)
    }
}
