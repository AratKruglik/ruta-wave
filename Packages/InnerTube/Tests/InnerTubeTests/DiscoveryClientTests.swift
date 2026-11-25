import Foundation
import Testing
@testable import InnerTube

private let credentials = Credentials(
    cookies: [HTTPCookie(properties: [.name: "SAPISID", .value: "test-sapisid", .domain: ".youtube.com", .path: "/"])!])

private func body(_ request: URLRequest) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
}

// Fixtures carry no visitor data, so these tests never touch GuestVisitor.shared and never assert on its header.
@Suite struct DiscoveryClientTests {
    @Test func guestHomeSendsBrowseIdWithoutAuthAndParsesTheFixture() async throws {
        let script = Script([try .fixture("home")])
        let home = try await script.client().home(credentials: nil)
        let request = script.requests[0]
        #expect(request.url?.path == "/youtubei/v1/browse")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        let sent = try body(request)
        #expect(sent["browseId"]?.string == "FEmusic_home")
        #expect(sent["params"] == nil)
        #expect(home.shelves.items.count == 2)
    }

    @Test func homeChipParamsAreSent() async throws {
        let script = Script([try .fixture("home")])
        _ = try await script.client().home(params: "chip-params", credentials: nil)
        #expect(try body(script.requests[0])["params"]?.string == "chip-params")
    }

    @Test func signedInRequestIsSignedForTheChosenAccount() async throws {
        let script = Script([try .fixture("home-signed-in")])
        let home = try await script.client().home(credentials: credentials)
        let request = script.requests[0]
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("SAPISIDHASH ") == true)
        #expect(request.value(forHTTPHeaderField: "X-Goog-AuthUser") == "0")
        #expect(home.shelves.items.map(\.title) == ["Listen again", "Mixed for you"])
    }

    @Test func unauthorizedSurfacesForSignedRequests() async {
        let script = Script([.status(401, "")])
        await #expect(throws: InnerTubeError.unauthorized) { try await script.client().home(credentials: credentials) }
    }

    @Test func browseSendsTargetIdAndParams() async throws {
        let script = Script([try .fixture("mood-category")])
        let page = try await script.client().browse(BrowseTarget(browseId: "FEmusic_moods_and_genres_category", params: "p1"), credentials: nil)
        let sent = try body(script.requests[0])
        #expect(sent["browseId"]?.string == "FEmusic_moods_and_genres_category")
        #expect(sent["params"]?.string == "p1")
        #expect(page.title == "Chill")
    }

    @Test func browseContinuationSendsOnlyTheToken() async throws {
        let script = Script([try .fixture("home-continuation")])
        let page = try await script.client().browseContinuation("tok", credentials: nil)
        let sent = try body(script.requests[0])
        #expect(sent["continuation"]?.string == "tok")
        #expect(sent["browseId"] == nil)
        #expect(page.items.count == 3)
        #expect(page.continuation == "PLACEHOLDER_CONTINUATION_1")
    }

    @Test func chartsSendsNestedFormDataForTheCountry() async throws {
        let script = Script([try .fixture("charts")])
        let page = try await script.client().charts(country: "US", credentials: nil)
        let sent = try body(script.requests[0])
        #expect(sent["browseId"]?.string == "FEmusic_charts")
        #expect(sent["formData"]?["selectedValues"]?.array == [.string("US")])
        #expect(page.selectedCountry == "US")
    }

    @Test func chartsWithoutCountrySendsNoFormData() async throws {
        let script = Script([try .fixture("charts")])
        _ = try await script.client().charts(credentials: nil)
        #expect(try body(script.requests[0])["formData"] == nil)
    }

    @Test func searchSendsQueryAndFilterParams() async throws {
        let script = Script([try .fixture("search-songs")])
        let results = try await script.client().search("radiohead", params: "songs-params", credentials: nil)
        let sent = try body(script.requests[0])
        #expect(script.requests[0].url?.path == "/youtubei/v1/search")
        #expect(sent["query"]?.string == "radiohead")
        #expect(sent["params"]?.string == "songs-params")
        #expect(results.items.items.count == 3)
    }

    @Test func searchContinuationSendsOnlyTheToken() async throws {
        let script = Script([try .fixture("search-songs-continuation")])
        let page = try await script.client().searchContinuation("tok", credentials: nil)
        let sent = try body(script.requests[0])
        #expect(sent["continuation"]?.string == "tok")
        #expect(sent["query"] == nil)
        #expect(page.items.count == 3)
    }

    @Test func suggestionsSendInput() async throws {
        let script = Script([try .fixture("suggestions")])
        let suggestions = try await script.client().searchSuggestions("radi", credentials: nil)
        #expect(script.requests[0].url?.path == "/youtubei/v1/music/get_search_suggestions")
        #expect(try body(script.requests[0])["input"]?.string == "radi")
        #expect(suggestions.queries.count == 3)
    }

    @Test func pageWithoutExpectedRootThrows() async {
        let script = Script([.status(200, #"{"contents":{}}"#)])
        await #expect(throws: InnerTubeError.unexpectedResponse) { try await script.client().search("x", credentials: nil) }
    }

    // Run manually against the real service: INNERTUBE_LIVE=1 swift test --filter DiscoveryClientTests
    @Test(.enabled(if: ProcessInfo.processInfo.environment["INNERTUBE_LIVE"] == "1"))
    func liveHomeAndSearch() async throws {
        let client = InnerTubeClient()
        let home = try await client.home(credentials: nil)
        #expect(!home.shelves.items.isEmpty)
        let results = try await client.search("radiohead", credentials: nil)
        #expect(results.topResult != nil)
        #expect(!results.items.items.isEmpty)
    }
}
