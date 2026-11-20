import Foundation
import Testing
@testable import PlayerEngine

struct SongInfoTests {
    private func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "player-response", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func parsesFixture() throws {
        let parsed = try #require(SongInfo.parse(try fixture()))
        let song = parsed.song
        #expect(song.videoId == "dQw4w9WgXcQ")
        #expect(song.title == "Never Gonna Give You Up")
        #expect(song.artist == "Rick Astley")
        #expect(song.duration == 213)
        #expect(song.url == URL(string: "https://music.youtube.com/watch?v=dQw4w9WgXcQ"))
        #expect(song.playlistId == "RDAMVMdQw4w9WgXcQ")
        #expect(song.artworkURL == URL(string: "https://lh3.googleusercontent.com/example-cover=w544-h544-l90-rj"))
        #expect(parsed.artworkWithQuery == URL(string: "https://lh3.googleusercontent.com/example-cover=w544-h544-l90-rj?sqp=large"))
    }

    private func parse(_ json: String) -> SongInfo.Parsed? { SongInfo.parse(Data(json.utf8)) }

    @Test(arguments: ["nan", "inf", "1e999", "-1"])
    func rejectsNonFiniteOrNegativeDuration(_ length: String) throws {
        let parsed = try #require(parse(#"{"videoDetails":{"videoId":"abc","title":"T","author":"A","lengthSeconds":"\#(length)"}}"#))
        #expect(parsed.song.duration == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func capsHugeTitle() throws {
        let title = String(repeating: " ", count: 200_000) + "x"
        let parsed = try #require(parse(#"{"videoDetails":{"videoId":"abc","title":"\#(title)","author":"A"}}"#))
        #expect(parsed.song.title.utf8.count <= 1024)
    }

    @Test func missingMicroformatAndThumbnails() throws {
        let parsed = try #require(parse(#"{"videoDetails":{"videoId":"abc","title":"T","author":"A"}}"#))
        #expect(parsed.song.playlistId == nil)
        #expect(parsed.song.artworkURL == nil)
        #expect(parsed.song.duration == 0)
    }

    @Test func emptyThumbnailsAndZeroLength() throws {
        let parsed = try #require(parse(#"{"videoDetails":{"videoId":"abc","title":"T","author":"A","lengthSeconds":"0","thumbnail":{"thumbnails":[]}}}"#))
        #expect(parsed.song.artworkURL == nil)
        #expect(parsed.song.duration == 0)
    }

    @Test func foreignArtworkHostIsDropped() throws {
        let parsed = try #require(parse(#"{"videoDetails":{"videoId":"abc","title":"T","author":"A","thumbnail":{"thumbnails":[{"url":"https://evil.example/a.jpg?x=1"}]}}}"#))
        #expect(parsed.song.artworkURL == nil)
        #expect(parsed.artworkWithQuery == nil)
    }

    @Test func invalidVideoIdFails() {
        #expect(parse(#"{"videoDetails":{"videoId":"a&list=x","title":"T","author":"A"}}"#) == nil)
    }

    @Test func artworkFallsBackWhenStrippedUnreachable() async {
        let stripped = URL(string: "https://i.ytimg.com/a")!
        let original = URL(string: "https://i.ytimg.com/a?q=1")!
        #expect(await PlayerRules.resolveArtwork(stripped: stripped, original: original) { _ in true } == stripped)
        #expect(await PlayerRules.resolveArtwork(stripped: stripped, original: original) { _ in false } == original)
    }
}
