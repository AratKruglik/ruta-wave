import Foundation
import Testing
@testable import InnerTube

@Suite struct SuggestionsParserTests {
    @Test func guestSuggestionsHaveTextsThenEntities() throws {
        let suggestions = try SearchSuggestions(suggestions: Fixture.json("suggestions"))
        #expect(suggestions.queries == ["radiohead", "radioactive", "radio"])
        #expect(suggestions.history.isEmpty)
        #expect(suggestions.items.count == 3)
        guard case .artist(let artist) = suggestions.items[0], case .song(let song) = suggestions.items[1] else {
            Issue.record("expected an artist then a song")
            return
        }
        #expect(artist.name == "Radiohead")
        #expect(song.title == "Radioactive")
        #expect(song.artists.map(\.name) == ["Imagine Dragons"])
    }

    @Test func historyEntriesCarryTheirFeedbackToken() throws {
        let suggestions = try SearchSuggestions(suggestions: Fixture.json("suggestions-history"))
        #expect(suggestions.history == [
            SearchHistoryEntry(query: "placeholder query 1", feedbackToken: "PLACEHOLDER_FEEDBACK_1"),
            SearchHistoryEntry(query: "placeholder query 2", feedbackToken: "PLACEHOLDER_FEEDBACK_2"),
        ])
        #expect(suggestions.queries.isEmpty)
    }

    @Test(arguments: [#"{}"#, #"{"contents":[]}"#, #"{"contents":[{"unknownRenderer":{}}]}"#])
    func emptyOrUnknownResponseGivesEmptySuggestions(_ raw: String) throws {
        let json = try JSONValue(response: Data(raw.utf8))
        #expect(SearchSuggestions(suggestions: json) == SearchSuggestions())
    }

    @Test func historyWithoutTokenIsDropped() throws {
        let raw = #"{"contents":[{"searchSuggestionsSectionRenderer":{"contents":[{"historySuggestionRenderer":{"navigationEndpoint":{"searchEndpoint":{"query":"q"}}}}]}}]}"#
        #expect(SearchSuggestions(suggestions: try JSONValue(response: Data(raw.utf8))).history.isEmpty)
    }
}
