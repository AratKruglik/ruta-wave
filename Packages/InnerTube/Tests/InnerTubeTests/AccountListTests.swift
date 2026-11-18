import Foundation
import Testing
@testable import InnerTube

private func parse(_ json: String) throws -> JSONValue {
    try JSONValue(response: Data(json.utf8))
}

private func item(_ index: Int, selected: Bool = false) -> AccountListItem {
    AccountListItem(name: "Test User \(index)", handle: nil, avatarURL: nil, authUserIndex: index, isSelected: selected)
}

private let switcher = #"""
)]}'
{"actions":[{"getMultiPageMenuAction":{"menu":{"multiPageMenuRenderer":{"sections":[{"accountSectionListRenderer":{"contents":[{"accountItemSectionRenderer":{"contents":[
 {"accountItem":{"accountName":{"runs":[{"text":"Test User 1"}]},"accountByline":{"runs":[{"text":"3 960 subscribers"}]},"channelHandle":{"runs":[{"text":"@testhandle1"}]},
  "accountPhoto":{"thumbnails":[{"url":"https://yt3.ggpht.com/test-1"}]},"isSelected":false,
  "serviceEndpoint":{"selectActiveIdentityEndpoint":{"supportedTokens":[{"accountSigninToken":{"signinUrl":"/signin?action_handle_signin=true&authuser=1"}}]}}}},
 {"accountItem":{"accountName":{"runs":[{"text":"Test User 0"}]},"accountByline":{"runs":[{"text":"No channel"}]},
  "accountPhoto":{"thumbnails":[{"url":"https://example.com/test-0"}]},"isSelected":true,
  "serviceEndpoint":{"selectActiveIdentityEndpoint":{"supportedTokens":[{"accountSigninToken":{"signinUrl":"/signin?authuser=0"}}]}}}},
 {"accountItem":{"accountName":{"simpleText":"Brand Token"},"isSelected":false,
  "serviceEndpoint":{"selectActiveIdentityEndpoint":{"supportedTokens":[{"offlineCacheKeyToken":{"clientCacheKey":"k"}},{"pageIdToken":{"pageId":"1"}},{"accountSigninToken":{"signinUrl":"/signin?authuser=0"}}]}}}},
 {"accountItem":{"accountName":{"simpleText":"Brand Page"},
  "serviceEndpoint":{"selectActiveIdentityEndpoint":{"supportedTokens":[{"accountSigninToken":{"signinUrl":"/signin?authuser=0&pageid=2"}}]}}}},
 {"accountItem":{"accountName":{"simpleText":"Duplicate"},
  "serviceEndpoint":{"x":{"signinUrl":"/signin?authuser=1"}}}},
 {"accountItem":{"accountName":{"simpleText":"Negative"},"x":{"signinUrl":"/signin?authuser=-1"}}},
 {"accountItem":{"accountName":{"simpleText":"No Token"},"isSelected":true}},
 {"accountItem":{"accountByline":{"simpleText":"nameless"},"x":{"signinUrl":"/signin?authuser=5"}}}
]}}]}}]}}}}]}
"""#

@Suite struct AccountListTests {
    @Test func parsesPersonalAccountsOnly() throws {
        let list = AccountListItem.list(accountSwitcher: try parse(switcher))
        #expect(list.map(\.authUserIndex) == [0, 1])
        #expect(list.map(\.isSelected) == [true, false])
        #expect(list[0].name == "Test User 0")
        #expect(list[0].handle == nil)
        #expect(list[0].avatarURL == nil)
        #expect(list[1].handle == "@testhandle1")
        #expect(list[1].avatarURL == URL(string: "https://yt3.ggpht.com/test-1"))
    }

    @Test func handleComesFromChannelHandleOnly() throws {
        let json = #"{"accountItem":{"accountName":{"simpleText":"T"},"channelHandle":{"simpleText":"@h"},"x":{"signinUrl":"/s?authuser=0"}}}"#
        #expect(AccountListItem.list(accountSwitcher: try parse(json)).first?.handle == "@h")
    }

    @Test func emptyWhenNoAccountItems() throws {
        #expect(AccountListItem.list(accountSwitcher: try parse(#"{"actions":[]}"#)).isEmpty)
    }

    @Test(arguments: [
        (0, [0, 1], 0), (1, [0, 1], 1), (7, [0, 1], 0), (7, [1], 0), (0, [1], 0), (-1, [0, 1], 0),
        (7, [], 7), (3, [], 3),
    ])
    func fallbackIndex(current: Int, indices: [Int], expected: Int) {
        #expect(AccountListItem.fallbackIndex(current: current, accounts: indices.map { item($0) }) == expected)
    }

    @Test func fallbackIndexKeepsCurrentWhenListFailed() {
        #expect(AccountListItem.fallbackIndex(current: 7, accounts: nil) == 7)
    }

    @Test func parsesSwitcherWithoutXSSIPrefix() throws {
        let bare = switcher.replacingOccurrences(of: ")]}'\n", with: "")
        #expect(AccountListItem.list(accountSwitcher: try parse(bare)).map(\.authUserIndex) == [0, 1])
    }

    @Test(arguments: ["/s", "/s?authuser=abc", "/s?authuser=", "/s?authuser=-2", "/s?authuser=1.5"])
    func skipsItemsWithoutValidAuthUser(url: String) throws {
        let json = #"{"accountItem":{"accountName":{"simpleText":"T"},"x":{"signinUrl":"\#(url)"}}}"#
        #expect(AccountListItem.list(accountSwitcher: try parse(json)).isEmpty)
    }

    @Test func dropsItemWithConflictingAuthUserIndexes() throws {
        let json = #"{"accountItem":{"accountName":{"simpleText":"T"},"a":{"signinUrl":"/s?authuser=0"},"b":{"signinUrl":"/s?authuser=1"}}}"#
        #expect(AccountListItem.list(accountSwitcher: try parse(json)).isEmpty)
    }

    @Test func keepsItemWithRepeatedSameAuthUserIndex() throws {
        let json = #"{"accountItem":{"accountName":{"simpleText":"T"},"a":{"signinUrl":"/s?authuser=1"},"b":{"signinUrl":"/t?authuser=1"}}}"#
        #expect(AccountListItem.list(accountSwitcher: try parse(json)).map(\.authUserIndex) == [1])
    }

    @Test func skipsItemWithoutName() throws {
        let json = #"{"accountItem":{"x":{"signinUrl":"/s?authuser=0"}}}"#
        #expect(AccountListItem.list(accountSwitcher: try parse(json)).isEmpty)
    }

    @Test func skipsBrandItemMarkedByPageIdToken() throws {
        let json = #"{"accountItem":{"accountName":{"simpleText":"B"},"t":[{"pageIdToken":{"pageId":"1"}}],"x":{"signinUrl":"/s?authuser=0"}}}"#
        #expect(AccountListItem.list(accountSwitcher: try parse(json)).isEmpty)
    }

    @Test func skipsBrandItemMarkedByPageIdParam() throws {
        let json = #"{"accountItem":{"accountName":{"simpleText":"B"},"x":{"signinUrl":"/s?authuser=0&pageid=7"}}}"#
        #expect(AccountListItem.list(accountSwitcher: try parse(json)).isEmpty)
    }

    @Test(arguments: [
        ("https://yt3.ggpht.com/a", true), ("https://lh3.googleusercontent.com/a", true),
        ("https://i.ytimg.com/a", true), ("http://yt3.ggpht.com/a", false),
        ("https://evil.example/a", false), ("https://ggpht.com.evil.example/a", false),
        ("https://notggpht.com/a", false),
    ])
    func avatarAllowlist(url: String, kept: Bool) throws {
        let json = #"{"accountItem":{"accountName":{"simpleText":"T"},"accountPhoto":{"thumbnails":[{"url":"\#(url)"}]},"x":{"signinUrl":"/s?authuser=0"}}}"#
        let avatar = AccountListItem.list(accountSwitcher: try parse(json)).first?.avatarURL
        #expect((avatar != nil) == kept)
    }
}
