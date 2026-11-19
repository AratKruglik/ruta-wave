import Foundation
import Testing

@Suite struct FixturePrivacyTests {
    private static let forbidden: [(name: String, pattern: String)] = [
        ("cookie assignment", #"\b(SAPISID|__Secure-[0-9A-Za-z-]+|SID|HSID|SSID|APISID|LOGIN_INFO)="#),
        ("cookie or auth key", #""(SAPISID|Authorization|Cookie)""#),
        ("email address", #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#),
        ("visitor or account key", #""(visitorData|VISITOR_DATA|responseContext|activeAccountHeaderRenderer|accountName)""#),
        ("unscrubbed token", #""(continuation|token|feedbackToken)"\s*:\s*"(?!PLACEHOLDER_)"#),
        ("masked name with a live channel link", #""browseId":\s*"(?!UCplaceholder)[^"]*"\s*\}\s*\},\s*"text":\s*"Placeholder Name""#),
    ]

    @Test func fixtureDirectoryIsNotEmpty() {
        #expect(!Fixture.all.isEmpty)
    }

    @Test(arguments: Fixture.all)
    func fixtureHoldsNoPersonalData(_ file: URL) throws {
        let text = try String(contentsOf: file, encoding: .utf8)
        let found = try Self.violations(in: text)
        #expect(found.isEmpty, "\(file.lastPathComponent) contains \(found)")
    }

    private static func violations(in text: String) throws -> [String] {
        try forbidden.filter { try text.firstMatch(of: Regex($0.pattern)) != nil }.map(\.name)
    }

    @Test func guardRejectsLeakedValuesAndAcceptsPlaceholders() throws {
        let leaked = #"{"visitorData":"abc","continuation":"RealToken","mail":"a@b.com","c":"SAPISID=x","Cookie":"y","r":{"navigationEndpoint":{"browseEndpoint":{"browseId":"UCreal"}},"text":"Placeholder Name"}}"#
        let found = try Self.violations(in: leaked)
        #expect(found.count == Self.forbidden.count)
        #expect(try Self.violations(in: #"{"continuation":"PLACEHOLDER_CONTINUATION_1"}"#).isEmpty)
    }

    @Test(arguments: Fixture.all)
    func fixtureIsDocumented(_ file: URL) throws {
        let readme = try String(contentsOf: Fixture.directory.appendingPathComponent("README.md"), encoding: .utf8)
        #expect(readme.contains("`\(file.lastPathComponent)`"), "\(file.lastPathComponent) has no README row")
    }
}
