import Foundation
import Testing
@testable import InnerTube

@Suite struct AlbumParserTests {
    @Test func headerTypeYearAndAudioPlaylist() throws {
        let album = try AlbumPage(album: Fixture.json("album"))
        #expect(album.header.title == "OK Computer")
        #expect(album.header.subtitle == "Album • 1997")
        #expect(album.header.secondSubtitle == "12 songs • 53 minutes")
        #expect(album.header.artists.map(\.name) == ["Radiohead"])
        #expect(album.header.artists.first?.browseId == "UCr_iyUANcn9OX_yy9piYoLw")
        #expect(album.header.thumbnailURL?.host == "yt3.googleusercontent.com")
        #expect(album.type == "Album")
        #expect(album.year == "1997")
        #expect(album.audioPlaylistId?.hasPrefix("OLAK5uy_") == true)
        #expect(album.header.play == WatchTarget(playlistId: album.audioPlaylistId))
    }

    @Test func shuffleAndMixAreFoundByIcon() throws {
        let header = try AlbumPage(album: Fixture.json("album")).header
        #expect(header.shuffle?.playlistId == header.play?.playlistId)
        #expect(header.shuffle?.params != nil)
        #expect(header.radio?.playlistId?.hasPrefix("RDAMPL") == true)
    }

    @Test func tracksAreNumberedAndTakeTheirDurationFromTheFixedColumn() throws {
        let tracks = try AlbumPage(album: Fixture.json("album")).tracks
        #expect(tracks.map(\.number) == [1, 2, 3])
        #expect(tracks.map(\.song.title) == ["Airbag", "Paranoid Android", "Subterranean Homesick Alien"])
        #expect(tracks[0].song.duration == "4:48")
        #expect(tracks[0].song.videoId == "jNY_wLukVW0")
        #expect(tracks[0].song.artists.isEmpty)
        #expect(tracks.map(\.song.isVideo) == [false, true, false])
    }

    @Test func otherShelvesAreKeptInOrderWithoutTheTrackList() throws {
        let shelves = try AlbumPage(album: Fixture.json("album")).shelves
        #expect(shelves.count == 2)
        #expect(shelves.allSatisfy { $0.layout == .cards && !$0.items.isEmpty && $0.title != nil })
    }

    @Test func rowsCarryTheAudioPlaylistAndOtherVersionsCarryParams() throws {
        let album = try AlbumPage(album: Fixture.json("album"))
        #expect(album.header.isSaved == false)
        #expect(album.tracks.allSatisfy { $0.song.playlistId == album.audioPlaylistId })
        let versions = album.shelves.flatMap(\.items).compactMap { item -> Album? in
            if case .album(let value) = item, value.browseId == "MPREb_b9Yfli6Cg79" { value } else { nil }
        }
        #expect(versions.first?.params != nil)
    }

    @Test func unknownShelfIsSkipped() throws {
        let before = try AlbumPage(album: Fixture.json("album"))
        let text = String(decoding: try Fixture.data("album"), as: UTF8.self).replacingOccurrences(
            of: "\"musicCarouselShelfRenderer\"", with: "\"someFutureShelfRenderer\"")
        let after = try AlbumPage(album: JSONValue(response: Data(text.utf8)))
        #expect(after.tracks == before.tracks)
        #expect(after.shelves.isEmpty)
    }

    @Test func missingAlbumIsNotAvailable() throws {
        #expect(throws: InnerTubeError.notAvailable) { try AlbumPage(album: Fixture.json("playlist-missing")) }
    }

    @Test func unknownRootIsUnexpected() {
        #expect(throws: InnerTubeError.unexpectedResponse) { try AlbumPage(album: JSONValue.object(["contents": .object([:])])) }
    }
}
