import Foundation
import Testing
@testable import InnerTube

private func cookie(_ name: String, _ value: String, domain: String, expires: Date? = nil) -> HTTPCookie {
    var props: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: "/"]
    if let expires { props[.expires] = expires }
    return HTTPCookie(properties: props)!
}

private let now = Date(timeIntervalSince1970: 1_700_000_000)
private let cookies = [
    cookie("SAPISID", "test-root", domain: ".youtube.com"),
    cookie("SAPISID", "test-music", domain: "music.youtube.com"),
    cookie("SID", "test-sid", domain: ".youtube.com"),
    cookie("OLD", "test-old", domain: ".youtube.com", expires: now.addingTimeInterval(-10)),
    cookie("GOOG", "test-google", domain: ".google.com"),
]

@Suite struct InnerTubeRequestTests {
    @Test func buildsRequestLineAndBody() throws {
        let request = try InnerTubeRequest.make(
            endpoint: "account/account_menu", cookies: cookies, authUserIndex: 0, now: now, locale: Locale(identifier: "uk_UA"))
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://music.youtube.com/youtubei/v1/account/account_menu?prettyPrint=false")
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        let client = body["context"]?["client"]
        #expect(client?["clientName"]?.string == "WEB_REMIX")
        #expect(client?["clientVersion"]?.string?.isEmpty == false)
        #expect(client?["hl"]?.string == "uk")
        #expect(client?["gl"]?.string == "UA")
    }

    @Test func fallsBackToEnglishUS() throws {
        let request = try InnerTubeRequest.make(
            endpoint: "x", cookies: cookies, authUserIndex: 0, now: now, locale: Locale(identifier: ""))
        let client = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))["context"]?["client"]
        #expect(client?["hl"]?.string == "en")
        #expect(client?["gl"]?.string == "US")
    }

    @Test func mergesExtraBodyFields() throws {
        let request = try InnerTubeRequest.make(
            endpoint: "x", body: ["requestType": "R"], cookies: cookies, authUserIndex: 0, now: now, locale: .init(identifier: "en_US"))
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(body["requestType"]?.string == "R")
        #expect(body["context"] != nil)
    }

    @Test func setsAuthHeadersFromRootSAPISID() throws {
        let request = try InnerTubeRequest.make(
            endpoint: "x", cookies: cookies, authUserIndex: 1, now: now, locale: .init(identifier: "en_US"))
        let expected = SAPISIDHash.make(sapisid: "test-root", timestamp: 1_700_000_000, origin: "https://music.youtube.com")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "SAPISIDHASH \(expected)")
        #expect(request.value(forHTTPHeaderField: "X-Goog-AuthUser") == "1")
        #expect(request.value(forHTTPHeaderField: "Origin") == "https://music.youtube.com")
        #expect(request.value(forHTTPHeaderField: "X-Origin") == "https://music.youtube.com")
        #expect(request.httpShouldHandleCookies == false)
    }

    @Test func cookieHeaderDropsExpiredAndForeignDomains() throws {
        let request = try InnerTubeRequest.make(
            endpoint: "x", cookies: cookies, authUserIndex: 0, now: now, locale: .init(identifier: "en_US"))
        let header = try #require(request.value(forHTTPHeaderField: "Cookie"))
        #expect(header.contains("SID=test-sid"))
        #expect(!header.contains("test-old"))
        #expect(!header.contains("test-google"))
    }

    @Test func throwsWithoutRootSAPISID() {
        let onlyMusic = [cookie("SAPISID", "test-music", domain: "music.youtube.com")]
        #expect(throws: InnerTubeError.missingSAPISID) {
            try InnerTubeRequest.make(endpoint: "x", cookies: onlyMusic, authUserIndex: 0, now: now, locale: .init(identifier: "en_US"))
        }
    }
}
