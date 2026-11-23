import Foundation
import Testing
@testable import InnerTube

@Suite struct PlaylistParserTests {
    @Test func twoColumnPlaylistHasHeaderOwnerTracksAndBothTokens() throws {
        let page = try PlaylistPage(playlist: Fixture.json("playlist"))
        #expect(page.header.title == "Classic Rock's Greatest Hits")
        #expect(page.header.subtitle == "Playlist • 2026")
        #expect(page.header.secondSubtitle == "117 songs • 7+ hours")
        #expect(page.header.artists == [ItemRef(name: "YouTube Music", browseId: nil)])
        #expect(page.tracks.items.map(\.title) == ["Every Breath You Take Video", "Dream On", "Thunderstruck"])
        #expect(page.tracks.items.map(\.isVideo) == [true, false, true])
        #expect(page.tracks.items[1].duration == "4:28")
        #expect(page.tracks.items[1].artists.map(\.name) == ["Aerosmith"])
        #expect(page.tracks.continuation == "PLACEHOLDER_CONTINUATION_1")
        #expect(page.sectionsContinuation == "PLACEHOLDER_CONTINUATION_2")
    }

    @Test func playlistRowsCarryTheirSetVideoId() throws {
        let own = try PlaylistPage(playlist: Fixture.json("playlist-own"))
        #expect(own.tracks.items.map(\.playlistSetVideoId) == ["289F4A46DF0A30D2", "56B44F6D10557CC6"])
        let next = try Page<Song>(playlistContinuation: Fixture.json("playlist-continuation"))
        #expect(next.items.map(\.playlistSetVideoId) == ["780605BC69C6C250", "4949B9D0837AA5B0", "BC50DB7391B7A3A4"])
    }

    @Test func ownershipComesFromTheEditableHeader() throws {
        #expect(try PlaylistPage(playlist: Fixture.json("playlist")).isOwned == false)
        #expect(try PlaylistPage(playlist: Fixture.json("playlist-own")).isOwned == true)
    }

    @Test func savedStateIsTheBookmarkToggle() throws {
        #expect(try PlaylistPage(playlist: Fixture.json("playlist")).header.isSaved == false)
        let text = String(decoding: try Fixture.data("playlist"), as: UTF8.self)
        let bookmark = try #require(text.range(of: "BOOKMARK_BORDER"))
        let toggle = try #require(text.range(of: #""isToggled": false"#, range: bookmark.upperBound..<text.endIndex))
        let saved = text.replacingCharacters(in: toggle, with: #""isToggled": true"#)
        #expect(try PlaylistPage(playlist: JSONValue(response: Data(saved.utf8))).header.isSaved)
    }

    @Test func greyedOutRowsAreMarkedUnavailable() throws {
        #expect(try PlaylistPage(playlist: Fixture.json("playlist")).tracks.items.allSatisfy(\.isAvailable))
        var text = String(decoding: try Fixture.data("playlist"), as: UTF8.self)
        let row = try #require(text.range(of: #""musicResponsiveListItemRenderer": {"#))
        text.replaceSubrange(row, with: #""musicResponsiveListItemRenderer": {"musicItemRendererDisplayPolicy":"MUSIC_ITEM_RENDERER_DISPLAY_POLICY_GREY_OUT","#)
        let items = try PlaylistPage(playlist: JSONValue(response: Data(text.utf8))).tracks.items
        #expect(!items[0].isAvailable)
        #expect(items.dropFirst().allSatisfy { $0.isAvailable })
    }

    @Test func rowsCarryTheCollectionPlaylistId() throws {
        let page = try PlaylistPage(playlist: Fixture.json("playlist"))
        #expect(page.tracks.items.allSatisfy { $0.playlistId == "RDCLAK5uy_nZiG9ehz_MQoWQxY5yElsLHCcG0tv9PRg" })
    }

    @Test func singleColumnTopSongsIsAPlaylist() throws {
        let page = try PlaylistPage(playlist: Fixture.json("playlist-top-songs"))
        #expect(page.header.title == "Top songs")
        #expect(page.tracks.items.count == 3)
        #expect(page.tracks.continuation != nil)
        #expect(page.sectionsContinuation == nil)
    }

    @Test func lastPageHasNoContinuation() throws {
        let page = try Page<Song>(playlistContinuation: Fixture.json("playlist-continuation"))
        #expect(page.items.count == 3)
        #expect(page.continuation == nil)
    }

    @Test func ownPlaylistHeaderIsUnwrappedAndOwnerHasNoLink() throws {
        let page = try PlaylistPage(playlist: Fixture.json("playlist-own"))
        #expect(page.header.title == "Placeholder own playlist")
        #expect(page.header.artists == [ItemRef(name: "Placeholder Owner", browseId: nil)])
        #expect(page.tracks.items.count == 2)
        #expect(page.tracks.continuation == nil)
        #expect(page.sectionsContinuation == "PLACEHOLDER_CONTINUATION_1")
    }

    @Test func suggestionsParseThroughBrowsePage() throws {
        let page = try BrowsePage(browse: Fixture.json("playlist-suggestions"))
        #expect(page.shelves.items.map(\.title) == ["Suggestions"])
        #expect(page.shelves.items[0].layout == .list)
        #expect(page.shelves.items[0].items.count == 2)
    }

    @Test func likedMusicIsATwoColumnPlaylist() throws {
        let page = try PlaylistPage(playlist: Fixture.json("liked-music"))
        #expect(page.header.title == "Liked music")
        #expect(page.tracks.items.count == 2)
        #expect(page.tracks.continuation == "PLACEHOLDER_CONTINUATION_1")
    }

    @Test func missingPlaylistIsNotAvailable() throws {
        #expect(throws: InnerTubeError.notAvailable) { try PlaylistPage(playlist: Fixture.json("playlist-missing")) }
    }

    @Test func contentsWithoutAKnownRootIsUnexpected() {
        #expect(throws: InnerTubeError.unexpectedResponse) { try PlaylistPage(playlist: JSONValue.object(["contents": .object([:])])) }
    }

    @Test func continuationWithoutTheAppendActionIsNotNotAvailable() {
        #expect(throws: InnerTubeError.unexpectedResponse) { try Page<Song>(playlistContinuation: JSONValue.object([:])) }
    }

    @Test func guestLikedMusicIsUnexpected() throws {
        #expect(throws: InnerTubeError.unexpectedResponse) { try PlaylistPage(playlist: Fixture.json("liked-music-guest")) }
    }

    @Test func playlistWithoutAShelfIsAnEmptyPage() throws {
        let own = String(decoding: try Fixture.data("playlist-own"), as: UTF8.self)
            .replacingOccurrences(of: "musicPlaylistShelfRenderer", with: "someFutureRenderer")
        let page = try PlaylistPage(playlist: JSONValue(response: Data(own.utf8)))
        #expect(page.tracks.items.isEmpty)
    }
}
