import Foundation
import Testing
@testable import InnerTube

private func parse(_ json: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}

private let menuFull = #"""
{"actions":[{"openPopupAction":{"popup":{"multiPageMenuRenderer":{"header":{"activeAccountHeaderRenderer":{
  "accountName":{"runs":[{"text":"Test User"}]},
  "channelHandle":{"runs":[{"text":"@testhandle"}]},
  "accountPhoto":{"thumbnails":[{"url":"https://yt3.ggpht.com/test-small"},{"url":"https://yt3.ggpht.com/test-avatar"}]}
}}}}}}]}
"""#

private let menuNameOnly = #"""
{"actions":[{"openPopupAction":{"popup":{"multiPageMenuRenderer":{"header":{"activeAccountHeaderRenderer":{
  "accountName":{"simpleText":"Test User"}
}}}}}}]}
"""#

@Suite struct AccountParsingTests {
    @Test func parsesFullAccountMenu() throws {
        let info = try AccountInfo(accountMenu: parse(menuFull))
        #expect(info.name == "Test User")
        #expect(info.handle == "@testhandle")
        #expect(info.avatarURL == URL(string: "https://yt3.ggpht.com/test-avatar"))
    }

    @Test func rejectsDisallowedAvatarURLs() throws {
        for url in ["https://example.com/a.png", "file:///tmp/a.png", "http://yt3.ggpht.com/a.png", "https://evilggpht.com/a.png"] {
            let photo = try parse(#"{"thumbnails":[{"url":"\#(url)"}]}"#)
            #expect(lastThumbnailURL(photo) == nil)
        }
    }

    @Test func parsesNameOnlyAccountMenu() throws {
        let info = try AccountInfo(accountMenu: parse(menuNameOnly))
        #expect(info == AccountInfo(name: "Test User", handle: nil, avatarURL: nil))
    }

    @Test func accountMenuWithoutNameThrows() throws {
        #expect(throws: InnerTubeError.unexpectedResponse) { try AccountInfo(accountMenu: parse("{}")) }
    }
}
