import Foundation
import Testing
@testable import InnerTube

private let credentials = Credentials(
    cookies: [HTTPCookie(properties: [.name: "SAPISID", .value: "test-sapisid", .domain: ".youtube.com", .path: "/"])!])

private func body(_ request: URLRequest) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
}

@Suite struct EntityClientTests {
    @Test func albumSendsBrowseIdAndParams() async throws {
        let script = Script([try .fixture("album")])
        let album = try await script.client().album(BrowseTarget(browseId: "MPREb_x", params: "p"), credentials: nil)
        let sent = try body(script.requests[0])
        #expect(script.requests[0].url?.path == "/youtubei/v1/browse")
        #expect(sent["browseId"]?.string == "MPREb_x")
        #expect(sent["params"]?.string == "p")
        #expect(album.header.title == "OK Computer")
    }

    @Test func artistParsesTheFixture() async throws {
        let script = Script([try .fixture("artist")])
        let artist = try await script.client().artist(BrowseTarget(browseId: "UCr_iyUANcn9OX_yy9piYoLw"), credentials: nil)
        #expect(artist.name == "Radiohead")
        #expect(try body(script.requests[0])["params"] == nil)
    }

    @Test func playlistAndItsContinuationShareTheBrowseEndpoint() async throws {
        let script = Script([try .fixture("playlist"), try .fixture("playlist-continuation")])
        let client = script.client()
        let page = try await client.playlist(BrowseTarget(browseId: "VLRDCLAK"), credentials: nil)
        let next = try await client.playlistContinuation(#require(page.tracks.continuation), credentials: nil)
        #expect(try body(script.requests[1])["continuation"]?.string == "PLACEHOLDER_CONTINUATION_1")
        #expect(try body(script.requests[1])["browseId"] == nil)
        #expect(next.continuation == nil)
    }

    @Test func playlistSectionsTokenGoesThroughBrowseContinuation() async throws {
        let script = Script([try .fixture("playlist-own"), try .fixture("playlist-suggestions")])
        let client = script.client()
        let page = try await client.playlist(BrowseTarget(browseId: "VLPLx"), credentials: credentials)
        let shelves = try await client.browseContinuation(#require(page.sectionsContinuation), credentials: credentials)
        #expect(shelves.items.map(\.title) == ["Suggestions"])
    }

    @Test func missingPlaylistIsNotAvailable() async throws {
        let script = Script([try .fixture("playlist-missing")])
        await #expect(throws: InnerTubeError.notAvailable) { try await script.client().playlist(BrowseTarget(browseId: "VLPLx"), credentials: nil) }
    }

    @Test func notFoundStatusStaysAnHTTPError() async {
        let script = Script([.status(404, "{}")])
        await #expect(throws: InnerTubeError.httpStatus(404)) { try await script.client().playlist(BrowseTarget(browseId: "VLPLx"), credentials: nil) }
    }

    @Test func signedInLibraryIsSignedForTheChosenAccount() async throws {
        let script = Script([try .fixture("library-playlists")])
        let page = try await script.client().library(.likedPlaylists, credentials: credentials)
        let request = script.requests[0]
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("SAPISIDHASH ") == true)
        #expect(request.value(forHTTPHeaderField: "X-Goog-AuthUser") == "0")
        #expect(try body(request)["browseId"]?.string == "FEmusic_liked_playlists")
        #expect(!page.items.items.isEmpty)
    }

    @Test func libraryContinuationSendsOnlyTheToken() async throws {
        let script = Script([try .fixture("library-continuation")])
        let page = try await script.client().libraryContinuation("PLACEHOLDER_CONTINUATION_1", credentials: credentials)
        #expect(try body(script.requests[0])["continuation"]?.string == "PLACEHOLDER_CONTINUATION_1")
        #expect(page.items.count == 1)
    }

    @Test func sidebarUsesTheGuideWhenItHasPlaylists() async throws {
        let script = Script([try .fixture("guide")])
        let playlists = try await script.client().sidebarPlaylists(credentials: credentials)
        #expect(script.requests.count == 1)
        #expect(script.requests[0].url?.path == "/youtubei/v1/guide")
        #expect(playlists.count == 3)
    }

    @Test func sidebarFallsBackToTheLibraryPlaylists() async throws {
        let script = Script([try .fixture("guide-guest"), try .fixture("library-playlists")])
        let playlists = try await script.client().sidebarPlaylists(credentials: credentials)
        #expect(script.requests.map { $0.url?.path } == ["/youtubei/v1/guide", "/youtubei/v1/browse"])
        #expect(playlists.map(\.browseId).first == BrowseTarget.likedMusic.browseId)
    }

    @Test func guestSidebarIsEmpty() async throws {
        let script = Script([try .fixture("guide-guest"), try .fixture("library-guest")])
        #expect(try await script.client().sidebarPlaylists(credentials: nil).isEmpty)
    }

    @Test func historyParsesDays() async throws {
        let script = Script([try .fixture("history")])
        let days = try await script.client().history(credentials: credentials)
        #expect(try body(script.requests[0])["browseId"]?.string == "FEmusic_history")
        #expect(days.count == 2)
    }

    @Test func watchNextSendsOnlyTheGivenKeys() async throws {
        let script = Script([try .fixture("next-radio"), try .fixture("next-continuation")])
        let client = script.client()
        let next = try await client.watchNext(WatchTarget(videoId: "v", playlistId: "RDx"), credentials: nil)
        let sent = try body(script.requests[0])
        #expect(script.requests[0].url?.path == "/youtubei/v1/next")
        #expect(sent["videoId"]?.string == "v")
        #expect(sent["playlistId"]?.string == "RDx")
        #expect(sent["params"] == nil)
        let more = try await client.watchNextContinuation(#require(next.queue.continuation), credentials: nil)
        #expect(try body(script.requests[1])["continuation"]?.string == "PLACEHOLDER_CONTINUATION_1")
        #expect(more.items.count == 2)
    }

    @Test func timedLyricsRetriesATransientFailureAndSendsNoVisitor() async throws {
        let script = Script([.status(503, ""), try .fixture("timed-lyrics")])
        let lyrics = try await script.client().timedLyrics("MPLYt_a")
        #expect(lyrics?.lines.count == 8)
        #expect(script.requests.count == 2)
        #expect(try body(script.requests[1])["browseId"]?.string == "MPLYt_a")
        #expect(script.requests[1].value(forHTTPHeaderField: "X-Goog-Visitor-Id") == nil)
    }

    @Test func lyricsReturnsTextOrNil() async throws {
        let script = Script([try .fixture("lyrics"), try .fixture("lyrics-none")])
        let client = script.client()
        #expect(try await client.lyrics("MPLYt_a", credentials: nil)?.source == "Source: LyricFind")
        #expect(try await client.lyrics("MPLYt_b", credentials: nil) == nil)
        #expect(try body(script.requests[0])["browseId"]?.string == "MPLYt_a")
    }

    // Run manually against the real service: INNERTUBE_LIVE=1 swift test --filter EntityClientTests
    @Test(.enabled(if: ProcessInfo.processInfo.environment["INNERTUBE_LIVE"] == "1"))
    func livePlaylistPagesPastOneHundredTracks() async throws {
        let client = InnerTubeClient()
        let first = try await client.playlist(BrowseTarget(browseId: "VLRDCLAK5uy_nZiG9ehz_MQoWQxY5yElsLHCcG0tv9PRg"), credentials: nil)
        let token = try #require(first.tracks.continuation)
        let second = try await client.playlistContinuation(token, credentials: nil)
        #expect(first.tracks.items.count == 100)
        #expect(!second.items.isEmpty)
        #expect(Set(first.tracks.items.map(\.videoId)).isDisjoint(with: second.items.map(\.videoId)))
    }
}
