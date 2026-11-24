import Foundation
import Testing

struct TrackDragTests {
    @Test func aSongDragsAsItsWatchURL() {
        #expect(TrackDrag(videoIds: ["v1", "v2"]).externalURL.absoluteString == "https://music.youtube.com/watch?v=v1")
    }

    @Test func aPlaylistOrAlbumDragsAsItsPlaylistURL() {
        #expect(TrackDrag(playlistId: "PL1").externalURL.absoluteString == "https://music.youtube.com/playlist?list=PL1")
        #expect(TrackDrag(playlistId: "OLAK1").externalURL.absoluteString == "https://music.youtube.com/playlist?list=OLAK1")
    }

    @Test func roundTripsThroughCodable() throws {
        let drag = TrackDrag(videoIds: ["a"], sourcePlaylistId: "PL1", setVideoIds: ["s1"])
        let data = try JSONEncoder().encode(drag)
        #expect(try JSONDecoder().decode(TrackDrag.self, from: data) == drag)
    }
}
