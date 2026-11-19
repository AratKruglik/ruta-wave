import Foundation
import Testing
@testable import InnerTube

@Suite struct ClientVersionTests {
    private func store(cached: String? = nil) -> (ClientVersion, UserDefaults) {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        if let cached { defaults.set(cached, forKey: "innerTubeClientVersion") }
        return (ClientVersion(defaults: defaults), defaults)
    }

    @Test func extractFindsVersionInPage() {
        let html = #"<script>ytcfg.set({"INNERTUBE_CLIENT_NAME":"WEB_REMIX","INNERTUBE_CLIENT_VERSION":"1.20270102.01.00"});</script>"#
        #expect(ClientVersion.extract(fromPage: html) == "1.20270102.01.00")
    }

    @Test func extractIgnoresPagesWithoutVersion() {
        #expect(ClientVersion.extract(fromPage: "<html>consent</html>") == nil)
    }

    @Test(arguments: ["", "1.2.3", "1.20261115.14.00\"", "1.20261115.14 .00", "1.20261115.14.00\n", "1.20261115.14.00" + String(repeating: "0", count: 40), "Ж"])
    func validatedRejects(_ raw: String) {
        #expect(ClientVersion.validated(raw) == nil)
    }

    @Test func initFallsBackToBuiltIn() {
        #expect(store().0.current == ClientVersion.builtIn)
        #expect(store(cached: "garbage").0.current == ClientVersion.builtIn)
    }

    @Test func initUsesValidCache() {
        #expect(store(cached: "1.20270102.01.00").0.current == "1.20270102.01.00")
    }

    @Test func acceptValidUpdatesMemoryAndCache() {
        let (version, defaults) = store()
        version.accept("1.20270102.01.00")
        #expect(version.current == "1.20270102.01.00")
        #expect(defaults.string(forKey: "innerTubeClientVersion") == "1.20270102.01.00")
    }

    @Test func acceptInvalidKeepsPrevious() {
        let (version, defaults) = store(cached: "1.20270102.01.00")
        version.accept("bad")
        version.accept(nil)
        #expect(version.current == "1.20270102.01.00")
        #expect(defaults.string(forKey: "innerTubeClientVersion") == "1.20270102.01.00")
    }

    @Test func pageRequestIsAnonymousGet() {
        let request = InnerTubeRequest.makePage()
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://music.youtube.com/")
        for header in ["Cookie", "Authorization", "X-Goog-AuthUser", "X-Goog-Visitor-Id"] {
            #expect(request.value(forHTTPHeaderField: header) == nil)
        }
        #expect(request.httpShouldHandleCookies == false)
    }

    @Test func requestBodyUsesCurrentVersion() throws {
        let request = try InnerTubeRequest.makeGuest(endpoint: "browse", visitorData: nil, locale: .current)
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(body["context"]?["client"]?["clientVersion"]?.string == ClientVersion.shared.current)
    }
}
