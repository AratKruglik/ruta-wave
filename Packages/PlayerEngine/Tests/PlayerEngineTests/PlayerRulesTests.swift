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
        "https://www.youtube.com/watch?v=x", "https://accounts.google.com/",
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
    }

    @Test func recoverHasNoBridgeCall() {
        #expect(PlayerRules.bridgeCall(for: .recover, queue: []) == nil)
    }

    @Test func loadURLForGuestIsWatchURL() {
        #expect(PlayerRules.loadURL(videoId: "abc", playlistId: "PL1", signedIn: false)?.absoluteString == "https://music.youtube.com/watch?v=abc&list=PL1")
    }

    @Test func loadURLForAccountGoesThroughSignin() throws {
        let url = try #require(PlayerRules.loadURL(videoId: "abc", playlistId: "PL1", signedIn: true))
        #expect(url.absoluteString == "https://music.youtube.com/signin?action_handle_signin=true&authuser=0&next=/watch%3Fv%3Dabc%26list%3DPL1")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.map(\.name) == ["action_handle_signin", "authuser", "next"])
        #expect(items.last?.value == "/watch?v=abc&list=PL1")
        #expect(PlayerRules.isAllowedMainFrameNavigation(url))
    }

    @Test func loadURLRejectsBadIDs() {
        #expect(PlayerRules.loadURL(videoId: "a&b", playlistId: nil, signedIn: true) == nil)
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

    @Test func remoteCommandMapsKnownActions() {
        #expect(PlayerRules.remoteCommand(from: ["action": "play"]) == .play)
        #expect(PlayerRules.remoteCommand(from: ["action": "pause"]) == .pause)
        #expect(PlayerRules.remoteCommand(from: ["action": "nexttrack"]) == .next)
        #expect(PlayerRules.remoteCommand(from: ["action": "previoustrack"]) == .previous)
        #expect(PlayerRules.remoteCommand(from: ["action": "seekto", "time": 42.5]) == .seek(to: 42.5))
    }

    @Test(arguments: [
        ["action": "seekto"], ["action": "seekto", "time": -1.0],
        ["action": "seekto", "time": Double.infinity], ["action": "seekto", "time": "5"], ["time": 1.0],
    ] as [[String: any Sendable]])
    func remoteCommandRefusesUnknownOrInvalid(_ body: [String: any Sendable]) {
        #expect(PlayerRules.remoteCommand(from: body) == nil)
    }

    @Test(arguments: ["seekbackward", "seekforward"])
    func remoteCommandDropsSkipActions(_ action: String) {
        #expect(PlayerRules.remoteCommand(from: ["action": action]) == nil)
    }

    @Test func remoteCommandRefusesNonDictionary() {
        #expect(PlayerRules.remoteCommand(from: "play") == nil)
    }

    @Test func nowPlayingArgumentsCarryFieldsAndDropForeignArtwork() {
        var info = NowPlayingInfo(
            title: "T", artist: "A", album: "Al", artworkURL: URL(string: "https://i.ytimg.com/x.jpg"), duration: 100,
            elapsed: 5, isPlaying: true)
        let fields = PlayerRules.nowPlayingArguments(info)["info"] as? [String: Any]
        #expect(fields?["title"] as? String == "T")
        #expect(fields?["album"] as? String == "Al")
        #expect(fields?["artwork"] as? String == "https://i.ytimg.com/x.jpg")
        #expect(fields?["elapsed"] as? Double == 5)
        #expect(fields?["playing"] as? Bool == true)
        info.artworkURL = URL(string: "https://evil.example/x.jpg")
        info.album = nil
        let foreign = PlayerRules.nowPlayingArguments(info)["info"] as? [String: Any]
        #expect(foreign?["artwork"] == nil)
        #expect(foreign?["album"] == nil)
        #expect(PlayerRules.nowPlayingArguments(nil)["info"] is NSNull)
    }
}
