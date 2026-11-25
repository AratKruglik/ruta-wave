import Foundation
import InnerTube
import Testing

@MainActor
struct MusicLinkTests {
    private func link(_ string: String) -> MusicLink? { URL(string: string).flatMap(MusicLink.init) }

    @Test(arguments: [
        ("rutawave://", MusicLink.section(.home)),
        ("rutawave://explore", .section(.explore)),
        ("https://music.youtube.com/library", .section(.library)),
        ("https://MUSIC.youtube.com/", .section(.home)),
        ("rutawave://history", .route(.history)),
        ("rutawave://charts", .route(.explore(.charts))),
        ("https://music.youtube.com/new_releases", .route(.explore(.newReleases))),
        ("rutawave://moods_and_genres", .route(.explore(.moods))),
        ("rutawave://watch?v=abc_-1", .play(WatchTarget(videoId: "abc_-1"))),
        ("https://music.youtube.com/watch?v=abc&list=PL1&si=x", .play(WatchTarget(videoId: "abc", playlistId: "PL1"))),
        ("https://music.youtube.com/playlist?list=RDCLAK5uy", .play(WatchTarget(playlistId: "RDCLAK5uy"))),
        ("https://music.youtube.com/playlist?list=OLAK5uy_x", .route(.playlist(browseId: "VLOLAK5uy_x"))),
        ("rutawave://playlist?list=PL1", .route(.playlist(browseId: "VLPL1"))),
        ("https://music.youtube.com/browse/MPREb_abc", .route(.album(browseId: "MPREb_abc"))),
        ("https://music.youtube.com/browse/UCabc", .route(.artist(channelId: "UCabc"))),
        ("rutawave://channel/UCabc", .route(.artist(channelId: "UCabc"))),
        ("rutawave://search?q=%20daft%20punk%0A", .route(.search(query: "daft punk", filter: nil))),
        ("rutawave://search?q=daft+punk", .route(.search(query: "daft punk", filter: nil))),
        ("https://music.youtube.com/podcast/PCx", .openInBrowser(URL(string: "https://music.youtube.com/podcast/PCx")!)),
        ("https://music.youtube.com/browse/MPSPabc", .openInBrowser(URL(string: "https://music.youtube.com/browse/MPSPabc")!)),
    ])
    func accepts(_ string: String, expected: MusicLink) {
        #expect(link(string) == expected)
    }

    @Test(arguments: [
        "http://music.youtube.com/watch?v=abc",
        "https://music.youtube.com./watch?v=abc",
        "https://music.youtube.com.evil.com/watch?v=abc",
        "https://www.youtube.com/watch?v=abc",
        "https://youtu.be/abc",
        "https://user@music.youtube.com/watch?v=abc",
        "https://music.youtube.com:8443/watch?v=abc",
        "redwave://watch?v=abc",
        "file:///etc/passwd",
        "rutawave://watch",
        "rutawave://watch?v=a%2Fb",
        "rutawave://watch?v=abc&list=%3Cx%3E",
        "rutawave://watch?v=" + String(repeating: "a", count: 65),
        "rutawave://playlist",
        "rutawave://browse/%2e%2e",
        "rutawave://browse/FEunknown",
        "rutawave://browse/VLPL1/extra",
        "rutawave://channel/abc",
        "rutawave://search",
        "rutawave://search?q=%0A%0A",
        "rutawave://search?q=" + String(repeating: "a", count: 201),
        "rutawave://search?q=e" + String(repeating: "%CC%81", count: 201),
        "rutawave://search?q=%E2%80%8B%E2%80%8E%E2%81%A0",
        "rutawave://unknown",
        "rutawave://explore/extra",
        "rutawave://watch?v=",
        "rutawave://watch?v=a%20b",
        "rutawave://watch?v=caf%C3%A9",
        "rutawave://watch?v=abc&list=",
        "rutawave://watch?list=PL1",
        "rutawave://playlist?list=a.b",
        "rutawave://podcast/a%2Fb",
        "rutawave://podcast/",
        "rutawave://channel/UC%2e%2e",
        "https://music.youtube.com/browse/",
        "https://music.youtube.com/%zz",
    ])
    func rejects(_ string: String) {
        #expect(link(string) == nil)
    }

    @Test func usesTheFirstValueOfARepeatedParameter() {
        #expect(link("rutawave://watch?v=a&v=b") == .play(WatchTarget(videoId: "a")))
    }

    @Test func readsAWeblocFile() {
        let plist = "<plist version=\"1.0\"><dict><key>URL</key><string>https://music.youtube.com/watch?v=abc</string></dict></plist>"
        #expect(MusicLink.webloc(Data(plist.utf8)) == URL(string: "https://music.youtube.com/watch?v=abc"))
        #expect(MusicLink.webloc(Data("nope".utf8)) == nil)
        let noURL = "<plist version=\"1.0\"><dict><key>Other</key><string>x</string></dict></plist>"
        #expect(MusicLink.webloc(Data(noURL.utf8)) == nil)
    }
}
