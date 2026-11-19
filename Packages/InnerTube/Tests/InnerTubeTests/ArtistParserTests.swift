import Foundation
import Testing
@testable import InnerTube

@Suite struct ArtistParserTests {
    @Test func headerAndSubscribeState() throws {
        let artist = try ArtistPage(artist: Fixture.json("artist"))
        #expect(artist.name == "Radiohead")
        #expect(artist.thumbnailURL != nil)
        #expect(artist.subscriberCountText == "5.47M subscribers")
        #expect(artist.isSubscribed == false)
        #expect(artist.channelId == "UCq19-LqvG35A-30oyAiPiqA")
        #expect(artist.channelId != "UCr_iyUANcn9OX_yy9piYoLw")
        #expect(artist.shuffle?.videoId != nil || artist.shuffle?.playlistId != nil)
        #expect(artist.radio?.playlistId?.hasPrefix("RD") == true)
    }

    @Test func topSongsIsTheListShelfWithAPlaylistTarget() throws {
        let top = try #require(ArtistPage(artist: Fixture.json("artist")).shelves.first)
        #expect(top.title == "Top songs")
        #expect(top.layout == .list)
        #expect(top.items.count == 2)
        #expect(top.more?.browseId.hasPrefix("VLOLAK5uy_") == true)
        #expect(top.more?.params == "ggMCCAI%3D")
    }

    @Test func shelvesKeepServerOrderAndTheirMoreTarget() throws {
        let shelves = try ArtistPage(artist: Fixture.json("artist")).shelves
        #expect(shelves.map(\.title) == [
            "Top songs", "Albums", "Singles & EPs", "Videos", "Live performances", "Featured on", "Playlists by Radiohead", "Fans might also like",
        ])
        let more = Dictionary(uniqueKeysWithValues: shelves.compactMap { shelf in shelf.title.map { ($0, shelf.more?.browseId.prefix(4)) } })
        #expect(more["Albums"] == "MPAD")
        #expect(more["Videos"] == "VLOL")
        #expect(more["Live performances"] == "UCr_")
        #expect(shelves.first { $0.title == "Featured on" }?.more == nil)
    }

    @Test func aboutCarriesDescriptionAndViews() throws {
        let artist = try ArtistPage(artist: Fixture.json("artist"))
        #expect(artist.description?.hasPrefix("Radiohead are an English rock band") == true)
        #expect(artist.viewCountText == "5,409,889,352 views")
    }

    @Test func unknownShelfIsSkipped() throws {
        let text = String(decoding: try Fixture.data("artist"), as: UTF8.self)
            .replacingOccurrences(of: "\"musicCarouselShelfRenderer\"", with: "\"someFutureShelfRenderer\"")
        let artist = try ArtistPage(artist: JSONValue(response: Data(text.utf8)))
        #expect(artist.shelves.map(\.title) == ["Top songs"])
    }

    @Test func showAllParsesThroughBrowsePage() throws {
        let page = try BrowsePage(browse: Fixture.json("artist-albums"))
        #expect(page.shelves.items.count == 1)
        #expect(page.shelves.items[0].layout == .grid)
        #expect(page.shelves.items[0].items.count == 3)
    }

    @Test func missingArtistIsNotAvailable() throws {
        #expect(throws: InnerTubeError.notAvailable) { try ArtistPage(artist: Fixture.json("playlist-missing")) }
    }
}
