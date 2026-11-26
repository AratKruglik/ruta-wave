import Foundation
import Testing
@testable import InnerTube

private let syntheticVisitor = "CgtTWU5USEVUSUMxMjM%3D"

@Suite struct GuestRequestTests {
    @Test func guestRequestCarriesNoCredentials() throws {
        let request = try InnerTubeRequest.makeGuest(
            endpoint: "browse", body: ["browseId": "FEmusic_home"], visitorData: nil, locale: Locale(identifier: "uk_UA"))
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false")
        for header in ["Cookie", "Authorization", "X-Goog-AuthUser", "X-Goog-Visitor-Id"] {
            #expect(request.value(forHTTPHeaderField: header) == nil)
        }
        #expect(request.httpShouldHandleCookies == false)
        #expect(request.value(forHTTPHeaderField: "Origin") == "https://music.youtube.com")
        #expect(request.value(forHTTPHeaderField: "X-Origin") == "https://music.youtube.com")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.isEmpty == false)
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(body["browseId"]?.string == "FEmusic_home")
        #expect(body["context"]?["client"]?["clientName"]?.string == "WEB_REMIX")
        #expect(body["context"]?["client"]?["hl"]?.string == "uk")
        #expect(body["context"]?["client"]?["gl"]?.string == "UA")
        #expect(body["visitorData"] == nil)
        #expect(body["context"]?["client"]?["visitorData"] == nil)
    }

    @Test func visitorHeaderFollowsStoredValue() throws {
        let visitor = GuestVisitor()
        let before = try InnerTubeRequest.makeGuest(endpoint: "x", visitorData: visitor.snapshot().value, locale: .current)
        #expect(before.value(forHTTPHeaderField: "X-Goog-Visitor-Id") == nil)
        visitor.accept(syntheticVisitor, generation: visitor.snapshot().generation)
        let after = try InnerTubeRequest.makeGuest(endpoint: "x", visitorData: visitor.snapshot().value, locale: .current)
        #expect(after.value(forHTTPHeaderField: "X-Goog-Visitor-Id") == syntheticVisitor)
    }

    @Test func guestRequestDropsInvalidVisitor() throws {
        let request = try InnerTubeRequest.makeGuest(endpoint: "x", visitorData: "a\r\nCookie: x", locale: .current)
        #expect(request.value(forHTTPHeaderField: "X-Goog-Visitor-Id") == nil)
    }

    @Test(arguments: ["", String(repeating: "a", count: 513), "a\r\nb", "a b", "Жabc", "١٢٣"])
    func rejectsInvalid(_ raw: String) {
        #expect(GuestVisitor.validated(raw) == nil)
    }

    @Test(arguments: [syntheticVisitor, "abc_-=", String(repeating: "a", count: 512)])
    func acceptsValid(_ raw: String) {
        #expect(GuestVisitor.validated(raw) == raw)
    }

    @Test func invalidAcceptKeepsPrevious() {
        let visitor = GuestVisitor()
        visitor.accept(syntheticVisitor, generation: 0)
        visitor.accept("bad value", generation: 0)
        visitor.accept(nil, generation: 0)
        #expect(visitor.snapshot().value == syntheticVisitor)
    }

    @Test func staleGenerationIsDropped() {
        let visitor = GuestVisitor()
        let stale = visitor.snapshot().generation
        visitor.accept(syntheticVisitor, generation: stale)
        visitor.reset()
        #expect(visitor.snapshot().value == nil)
        visitor.accept(syntheticVisitor, generation: stale)
        #expect(visitor.snapshot().value == nil)
    }

    @Test func authenticatedRequestHasNoVisitorHeader() throws {
        let cookie = try #require(HTTPCookie(properties: [.name: "SAPISID", .value: "test-root", .domain: ".youtube.com", .path: "/"]))
        let request = try InnerTubeRequest.make(
            endpoint: "x", cookies: [cookie], now: Date(timeIntervalSince1970: 1_700_000_000), locale: .current)
        #expect(request.value(forHTTPHeaderField: "X-Goog-Visitor-Id") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") != nil)
    }

    @Test func lastValidVisitorWins() {
        let visitor = GuestVisitor()
        visitor.accept("first", generation: 0)
        visitor.accept("second", generation: 0)
        #expect(visitor.snapshot().value == "second")
    }

    @Test func eachResetAdvancesGeneration() {
        let visitor = GuestVisitor()
        visitor.reset()
        visitor.reset()
        #expect(visitor.snapshot().generation == 2)
    }

    @Test func guestRequestIgnoresAmbientSessionCookies() throws {
        let cookie = try #require(HTTPCookie(properties: [.name: "SAPISID", .value: "test-root", .domain: ".youtube.com", .path: "/"]))
        let signed = try InnerTubeRequest.make(endpoint: "browse", cookies: [cookie], now: Date(timeIntervalSince1970: 1_700_000_000), locale: .current)
        let guest = try InnerTubeRequest.makeGuest(endpoint: "browse", visitorData: syntheticVisitor, locale: .current)
        #expect(signed.value(forHTTPHeaderField: "X-Goog-AuthUser") == "0")
        for header in ["Cookie", "Authorization", "X-Goog-AuthUser"] {
            #expect(guest.value(forHTTPHeaderField: header) == nil)
        }
    }

    @Test func mobileGuestRequestLooksLikeTheAndroidAppAndCarriesNothingElse() throws {
        let request = try InnerTubeRequest.makeMobileGuest(endpoint: "browse", body: ["browseId": "MPLYt_x"], locale: Locale(identifier: "uk_UA"))
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(body["context"]?["client"]?["clientName"]?.string == "ANDROID_MUSIC")
        #expect(body["context"]?["client"]?["clientVersion"]?.string?.isEmpty == false)
        #expect(body["browseId"]?.string == "MPLYt_x")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("com.google.android.apps.youtube.music/") == true)
        for header in ["Cookie", "Authorization", "X-Goog-AuthUser", "X-Goog-Visitor-Id", "Origin", "X-Origin"] {
            #expect(request.value(forHTTPHeaderField: header) == nil)
        }
        #expect(request.httpShouldHandleCookies == false)
    }

    @Test func mobileGuestRequestIgnoresAmbientSessionCookies() throws {
        let cookie = try #require(HTTPCookie(properties: [.name: "SAPISID", .value: "test-root", .domain: ".youtube.com", .path: "/"]))
        let signed = try InnerTubeRequest.make(endpoint: "browse", cookies: [cookie], now: Date(timeIntervalSince1970: 1_700_000_000), locale: .current)
        let mobile = try InnerTubeRequest.makeMobileGuest(endpoint: "browse", locale: .current)
        #expect(signed.value(forHTTPHeaderField: "X-Goog-AuthUser") == "0")
        for header in ["Cookie", "Authorization", "X-Goog-AuthUser"] {
            #expect(mobile.value(forHTTPHeaderField: header) == nil)
        }
        #expect(mobile.httpShouldHandleCookies == false)
    }
}
