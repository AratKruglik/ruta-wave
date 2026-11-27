import Testing
@testable import InnerTube

private func results(_ name: String) throws -> SearchResults {
    try SearchResults(search: Fixture.json(name))
}

@Suite struct SearchParserTests {
    @Test func unfilteredHasChipsTopResultAndFlatItems() throws {
        let search = try results("search")
        #expect(search.chips.map(\.title) == ["Artists", "Albums", "Songs", "Videos", "Community playlists", "Featured playlists"])
        let hiddenPrefixes = ["EgWKAQJI", "EgWKAQJQ", "EgWKAQJY"]
        #expect(!search.chips.contains { chip in hiddenPrefixes.contains { chip.searchParams?.hasPrefix($0) == true } })
        #expect(search.chips.allSatisfy { $0.searchParams != nil && $0.target == nil })
        guard case .artist(let top) = try #require(search.topResult) else {
            Issue.record("expected artist card")
            return
        }
        #expect(top.name == "Radiohead")
        #expect(top.browseId.hasPrefix("UC"))
        #expect(top.isSubscribed == nil && top.channelId == nil)
        #expect(search.items.continuation == nil)
        #expect(search.correction == nil)
    }

    @Test func artistTopResultCarriesSubscriptionAndChannel() throws {
        guard case .artist(let top) = try #require(try results("search-artist-subscribe").topResult) else {
            Issue.record("expected artist card")
            return
        }
        #expect(top.isSubscribed == true)
        #expect(top.channelId == "UCq19-LqvG35A-30oyAiPiqA")
        #expect(top.channelId != top.browseId)
    }

    @Test func unfilteredItemsKeepServerOrderAndKinds() throws {
        let kinds = try results("search").items.items.map { item -> String in
            switch item {
            case .album: "album"
            case .song(let song): song.isVideo ? "video" : "song"
            case .artist: "artist"
            case .playlist: "playlist"
            case .link: "link"
            }
        }
        #expect(kinds == ["album", "song", "artist", "video", "playlist"])
    }

    @Test func episodesProfilesAndPodcastsAreSkipped() throws {
        let titles = try results("search").items.items.map { item -> String in
            switch item {
            case .album(let album): album.title
            case .song(let song): song.title
            case .artist(let artist): artist.name
            case .playlist(let playlist): playlist.title
            case .link(let link): link.title
            }
        }
        #expect(titles.allSatisfy { !$0.contains("Placeholder Profile") && $0 != "Placeholder Podcast" })
        #expect(titles.count == 5)
    }

    @Test func filteredResultsHaveContinuationAndExplicitFlag() throws {
        let songs = try results("search-songs")
        #expect(songs.topResult == nil)
        #expect(songs.items.continuation == "PLACEHOLDER_CONTINUATION_1")
        guard case .song(let creep) = songs.items.items[0] else {
            Issue.record("expected song")
            return
        }
        #expect(creep.title == "Creep")
        #expect(creep.isExplicit)
        #expect(creep.duration == "3:59")
        #expect(creep.artists.map(\.name) == ["Radiohead"])
        #expect(creep.album?.name == "Creep")
    }

    @Test func filteredSecondPageParsesItemsAndNextToken() throws {
        let next = try results("search-songs-continuation")
        #expect(next.chips.isEmpty)
        #expect(next.items.items.count == 3)
        #expect(next.items.continuation == "PLACEHOLDER_CONTINUATION_1")
    }

    @Test func correctionKeepsBothQueriesAndOriginalParams() throws {
        let search = try results("search-correction")
        #expect(search.correction == SearchCorrection(correctedQuery: "radiohead", originalQuery: "radiohed", originalParams: "QgIIAQ%3D%3D"))
        #expect(search.topResult != nil)
        #expect(!search.items.items.isEmpty)
    }

    @Test func noResultsKeepsChipsAndHasNoItems() throws {
        let empty = try results("search-empty")
        #expect(empty.chips.map(\.title) == ["Songs"])
        #expect(empty.topResult == nil)
        #expect(empty.items == Page(items: [], continuation: nil))
    }

    @Test func responseWithoutResultsRootThrows() throws {
        #expect(throws: InnerTubeError.unexpectedResponse) { try SearchResults(search: Fixture.json("home")) }
    }
}
