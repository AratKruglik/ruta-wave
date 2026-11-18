import Auth
import Foundation
import Testing
@testable import InnerTube

private func parse(_ json: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}

private func cookie(_ name: String, _ value: String, domain: String, expires: Date? = nil) -> HTTPCookie {
    var props: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: "/"]
    if let expires { props[.expires] = expires }
    return HTTPCookie(properties: props)!
}

private let now = Date(timeIntervalSince1970: 1_700_000_000)
private let en = Locale(identifier: "en_US")

@Suite struct JSONValueEdgeTests {
    @Test func topLevelScalarsAndEmptyContainers() throws {
        #expect(try parse("null") == .null)
        #expect(try parse(#""s""#) == .string("s"))
        #expect(try parse("[]") == .array([]))
        #expect(try parse("{}") == .object([:]))
    }

    @Test func stringsThatLookLikeOtherTypesStayStrings() throws {
        let value = try parse(#"{"a":"true","b":"1","c":"null"}"#)
        #expect(value["a"] == .string("true"))
        #expect(value["b"]?.double == nil)
        #expect(value["c"]?.bool == nil)
    }

    @Test func negativeIndexAndNullAccess() throws {
        let value = try parse(#"{"a":[1],"n":null}"#)
        #expect(value["a"]?[-1] == nil)
        #expect(value["n"]?["x"] == nil)
        #expect(value["n"]?.string == nil)
    }

    @Test func unicodeAndEscapesSurvive() throws {
        #expect(try parse(#"{"k":"Ж \"q\""}"#)["k"]?.string == "Ж \"q\"")
    }

    @Test func malformedJSONThrows() {
        #expect(throws: (any Error).self) { try parse("{") }
        #expect(throws: (any Error).self) { try parse("") }
    }
}

@Suite struct SAPISIDHashEdgeTests {
    private let origin = "https://music.youtube.com"

    @Test func eachInputChangesTheDigest() {
        let base = SAPISIDHash.make(sapisid: "a", timestamp: 1, origin: origin)
        #expect(base != SAPISIDHash.make(sapisid: "b", timestamp: 1, origin: origin))
        #expect(base != SAPISIDHash.make(sapisid: "a", timestamp: 2, origin: origin))
        #expect(base != SAPISIDHash.make(sapisid: "a", timestamp: 1, origin: "https://www.youtube.com"))
    }

    @Test func zeroTimestampAndEmptySapisidKeepFormat() {
        for hash in [SAPISIDHash.make(sapisid: "", timestamp: 0, origin: origin),
                     SAPISIDHash.make(sapisid: "Ж/+=", timestamp: 0, origin: origin)] {
            #expect(hash.wholeMatch(of: /0_[0-9a-f]{40}/) != nil)
        }
    }

    // printf '%s' '0  https://music.youtube.com' | shasum -a 1
    @Test func emptySapisidMatchesIndependentVector() {
        #expect(SAPISIDHash.make(sapisid: "", timestamp: 0, origin: origin) == "0_\(sha1OfEmptySapisid)")
    }
}

private let sha1OfEmptySapisid = "0eb41bc5ca54cb1b817a11d7817b406798ea2ab5"

@Suite struct RequestEdgeTests {
    private let base = [cookie("SAPISID", "test-root", domain: ".youtube.com")]

    @Test func userAgentAndContentType() throws {
        let request = try InnerTubeRequest.make(endpoint: "x", cookies: base, authUserIndex: 0, now: now, locale: en)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains(SignInRules.safariApplicationName) == true)
    }

    @Test func bareYoutubeDomainSAPISIDIsAccepted() throws {
        let request = try InnerTubeRequest.make(
            endpoint: "x", cookies: [cookie("SAPISID", "test-bare", domain: "youtube.com")], authUserIndex: 0, now: now, locale: en)
        let expected = SAPISIDHash.make(sapisid: "test-bare", timestamp: 1_700_000_000, origin: InnerTubeRequest.origin)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "SAPISIDHASH \(expected)")
    }

    @Test func emptyCookieListThrows() {
        #expect(throws: InnerTubeError.missingSAPISID) {
            try InnerTubeRequest.make(endpoint: "x", cookies: [], authUserIndex: 0, now: now, locale: en)
        }
    }

    @Test func cookieExpiringExactlyNowIsDropped() throws {
        let cookies = base + [cookie("EDGE", "test-edge", domain: ".youtube.com", expires: now)]
        let request = try InnerTubeRequest.make(endpoint: "x", cookies: cookies, authUserIndex: 0, now: now, locale: en)
        #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("test-edge") != true)
    }

    @Test func futureExpiryAndSessionCookiesAreKept() throws {
        let cookies = base + [cookie("FUT", "test-future", domain: ".youtube.com", expires: now.addingTimeInterval(3600))]
        let request = try InnerTubeRequest.make(endpoint: "x", cookies: cookies, authUserIndex: 0, now: now, locale: en)
        let header = try #require(request.value(forHTTPHeaderField: "Cookie"))
        #expect(header.contains("FUT=test-future"))
        #expect(header.contains("SAPISID=test-root"))
    }

    @Test func authUserIndexIsWrittenVerbatim() throws {
        for index in [0, 7, 12] {
            let request = try InnerTubeRequest.make(endpoint: "x", cookies: base, authUserIndex: index, now: now, locale: en)
            #expect(request.value(forHTTPHeaderField: "X-Goog-AuthUser") == "\(index)")
        }
    }

    @Test func languageOnlyLocaleKeepsDefaultRegion() throws {
        let request = try InnerTubeRequest.make(endpoint: "x", cookies: base, authUserIndex: 0, now: now, locale: Locale(identifier: "de"))
        let client = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))["context"]?["client"]
        #expect(client?["hl"]?.string == "de")
        #expect(client?["gl"]?.string == "US")
    }

    @Test func contextCannotBeOverriddenByBody() throws {
        let request = try InnerTubeRequest.make(
            endpoint: "x", body: ["context": "evil"], cookies: base, authUserIndex: 0, now: now, locale: en)
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(body["context"]?["client"]?["clientName"]?.string == "WEB_REMIX")
    }
}

@Suite struct ParsingEdgeTests {
    private func menu(_ header: String) throws -> JSONValue {
        try parse(#"{"actions":[{"openPopupAction":{"popup":{"multiPageMenuRenderer":{"header":{"activeAccountHeaderRenderer":\#(header)}}}}}]}"#)
    }

    @Test func malformedMenusThrow() throws {
        for json in [#"{"actions":[]}"#, #"{"actions":"x"}"#, "[]", "null"] {
            #expect(throws: InnerTubeError.unexpectedResponse) { try AccountInfo(accountMenu: parse(json)) }
        }
        #expect(throws: InnerTubeError.unexpectedResponse) { try AccountInfo(accountMenu: menu(#"{"accountName":{"runs":[]}}"#)) }
        #expect(throws: InnerTubeError.unexpectedResponse) { try AccountInfo(accountMenu: menu(#"{"accountName":{"runs":[{"text":5}]}}"#)) }
        #expect(throws: InnerTubeError.unexpectedResponse) { try AccountInfo(accountMenu: menu(#"{"accountName":"plain"}"#)) }
    }

    @Test func emptyThumbnailsAndInvalidURLGiveNoAvatar() throws {
        let empty = try AccountInfo(accountMenu: menu(#"{"accountName":{"simpleText":"T"},"accountPhoto":{"thumbnails":[]}}"#))
        let wrongType = try AccountInfo(accountMenu: menu(#"{"accountName":{"simpleText":"T"},"accountPhoto":{"thumbnails":[{"url":5}]}}"#))
        #expect(empty.avatarURL == nil)
        #expect(wrongType.avatarURL == nil)
    }

    @Test func handleWithEmptyRunsIsNil() throws {
        let info = try AccountInfo(accountMenu: menu(#"{"accountName":{"simpleText":"T"},"channelHandle":{"runs":[]}}"#))
        #expect(info.handle == nil)
    }
}
