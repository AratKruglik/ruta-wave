import Foundation
import Testing
@testable import PlayerEngine

struct PlayerRulesTests {
    @Test func allowsPlayerHost() {
        #expect(PlayerRules.isAllowedMainFrameNavigation(URL(string: "https://music.youtube.com/watch?v=x")))
        #expect(PlayerRules.isAllowedMainFrameNavigation(URL(string: "https://music.youtube.com:443/")))
    }

    @Test(arguments: [
        "http://music.youtube.com", "https://evil.example", "https://music.youtube.com.evil.example",
        "https://music.youtube.com@evil.example", "https://user@music.youtube.com", "https://music.youtube.com:8443",
        "javascript:alert(1)", "data:text/html,x", "file:///etc/passwd",
    ])
    func rejects(_ url: String) {
        #expect(!PlayerRules.isAllowedMainFrameNavigation(URL(string: url)))
    }

    @Test func rejectsNilURL() {
        #expect(!PlayerRules.isAllowedMainFrameNavigation(nil))
    }

    @Test func trustsOnlyMainFramePlayerOrigin() {
        #expect(PlayerRules.isTrustedMessage(isMainFrame: true, scheme: "https", host: "music.youtube.com", port: 0))
        #expect(PlayerRules.isTrustedMessage(isMainFrame: true, scheme: "https", host: "music.youtube.com", port: 443))
        #expect(!PlayerRules.isTrustedMessage(isMainFrame: false, scheme: "https", host: "music.youtube.com", port: 0))
        #expect(!PlayerRules.isTrustedMessage(isMainFrame: true, scheme: "https", host: "evil.example", port: 0))
        #expect(!PlayerRules.isTrustedMessage(isMainFrame: true, scheme: "http", host: "music.youtube.com", port: 0))
        #expect(!PlayerRules.isTrustedMessage(isMainFrame: true, scheme: "https", host: "music.youtube.com", port: 8443))
    }

    @Test func watchURLShape() {
        #expect(PlayerRules.watchURL(videoId: "abc")?.absoluteString == "https://music.youtube.com/watch?v=abc")
        #expect(PlayerRules.watchURL(videoId: "abc", playlistId: "PL1")?.absoluteString == "https://music.youtube.com/watch?v=abc&list=PL1")
        #expect(PlayerRules.watchURL(videoId: "abc", playlistId: "PL1", authUserIndex: 2)?.absoluteString == "https://music.youtube.com/watch?v=abc&list=PL1&authuser=2")
        #expect(PlayerRules.watchURL(videoId: "abc", authUserIndex: 0)?.query == "v=abc")
    }

    @Test(arguments: ["a&list=evil", "a#b", "a=b", "", "a b", String(repeating: "a", count: 65)])
    func watchURLRejectsBadIDs(_ id: String) {
        #expect(PlayerRules.watchURL(videoId: id) == nil)
        #expect(PlayerRules.watchURL(videoId: "ok", playlistId: id) == nil)
    }

    @Test func artworkHosts() {
        #expect(PlayerRules.isAllowedArtworkHost(URL(string: "https://i.ytimg.com/a")!))
        #expect(PlayerRules.isAllowedArtworkHost(URL(string: "https://lh3.googleusercontent.com/a")!))
        #expect(PlayerRules.isAllowedArtworkHost(URL(string: "https://yt3.ggpht.com/a")!))
        #expect(!PlayerRules.isAllowedArtworkHost(URL(string: "http://i.ytimg.com/a")!))
        #expect(!PlayerRules.isAllowedArtworkHost(URL(string: "https://googleusercontent.com.evil.example/a")!))
        #expect(!PlayerRules.isAllowedArtworkHost(URL(string: "https://evilggpht.com/a")!))
    }
}
