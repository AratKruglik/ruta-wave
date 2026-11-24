import Foundation
import Testing
@testable import InnerTube

private func page(_ name: String) throws -> BrowsePage {
    try BrowsePage(browse: Fixture.json(name))
}

private func shelf(_ page: BrowsePage, _ title: String) throws -> Shelf {
    try #require(page.shelves.items.first { $0.title == title })
}

@Suite struct BrowseParserTests {
    @Test func homeHasChipsShelvesAndContinuation() throws {
        let home = try page("home")
        #expect(home.about == nil)
        #expect(home.chips.count == 10)
        #expect(home.chips.allSatisfy { $0.target?.browseId == "FEmusic_home" && $0.target?.params != nil && !$0.title.isEmpty })
        #expect(home.shelves.items.map(\.title) == ["Morning boost", "It's autumn"])
        #expect(home.shelves.items.allSatisfy { $0.layout == .cards && !$0.items.isEmpty })
        #expect(home.shelves.continuation == "PLACEHOLDER_CONTINUATION_1")
    }

    @Test func homeMixCardPlaysThroughItsOverlay() throws {
        let mix = try shelf(page("home"), "It's autumn")
        guard case .playlist(let playlist) = mix.items[0] else {
            Issue.record("expected playlist")
            return
        }
        #expect(playlist.playTarget?.playlistId?.hasPrefix("RDCLAK") == true)
        #expect(playlist.playTarget?.videoId == nil)
    }

    @Test func newReleaseAlbumsCarryAPlaylistPlayTarget() throws {
        let releases = try page("new-releases").shelves.items.flatMap(\.items)
        let albums = releases.compactMap { item -> Album? in if case .album(let album) = item { album } else { nil } }
        #expect(!albums.isEmpty)
        #expect(albums.allSatisfy { $0.playTarget?.playlistId?.hasPrefix("OLAK5uy") == true })
    }

    @Test func moodLinksCarryStripeColors() throws {
        let moods = try shelf(page("explore"), "Moods & genres")
        let colors = moods.items.compactMap { item -> UInt32? in if case .link(let link) = item { link.stripeColor } else { nil } }
        #expect(colors.count == moods.items.count)
        #expect(colors.first == 4288988671)
    }

    @Test func homeShelfSubtitleAndStrapline() throws {
        let autumn = try shelf(page("home"), "It's autumn")
        #expect(autumn.strapline == "SWEATER WEATHER")
        guard case .playlist(let playlist) = autumn.items[0] else {
            Issue.record("expected playlist")
            return
        }
        #expect(playlist.browseId.hasPrefix("VL"))
        #expect(playlist.thumbnailURL?.host == "yt3.googleusercontent.com")
    }

    @Test func tastebuilderShelfIsSkipped() throws {
        let raw = try Fixture.json("home")
        let kinds = raw.sectionList?["contents"]?.array?.compactMap { $0.object?.keys.first } ?? []
        #expect(kinds.contains("musicTastebuilderShelfRenderer"))
        #expect(try page("home").shelves.items.count == kinds.count - 1)
    }

    @Test func signedInHomeShelvesWithStraplineAndSelectedChip() throws {
        let home = try page("home-signed-in")
        #expect(home.chips.map(\.title) == ["Relax", "Workout"])
        #expect(home.chips.map(\.isSelected) == [false, true])
        let listenAgain = try shelf(home, "Listen again")
        #expect(listenAgain.strapline == "Placeholder Name")
        #expect(listenAgain.items.count == 2)
        let mixed = try shelf(home, "Mixed for you")
        #expect(mixed.more == BrowseTarget(browseId: "FEmusic_mixed_for_you"))
        #expect(mixed.items == [.playlist(Playlist(browseId: "RDPLACEHOLDERMIX0001", title: "Placeholder Mix", subtitle: "Placeholder Artist", thumbnailURL: URL(string: "https://lh3.googleusercontent.com/placeholder-mix=w226-h226"), playTarget: WatchTarget(playlistId: "RDPLACEHOLDERMIX0001", params: "wAEB")))])
    }

    @Test func homeContinuationPageParsesWithoutChips() throws {
        let next = try page("home-continuation")
        #expect(next.chips.isEmpty)
        #expect(next.shelves.items.count == 3)
        #expect(next.shelves.continuation == "PLACEHOLDER_CONTINUATION_1")
        let releases = try shelf(next, "New releases")
        #expect(releases.more?.browseId == "FEmusic_new_releases_albums")
        #expect(releases.more?.params != nil)
    }

    @Test func exploreHasTilesAndMixedShelves() throws {
        let explore = try page("explore")
        let tiles = explore.shelves.items[0]
        #expect(tiles.layout == .grid)
        #expect(tiles.items.compactMap { item -> String? in
            guard case .link(let link) = item else { return nil }
            return link.target.browseId
        } == ["FEmusic_new_releases", "FEmusic_charts", "FEmusic_moods_and_genres"])
        let moods = try shelf(explore, "Moods & genres")
        #expect(moods.items.allSatisfy { item in
            guard case .link(let link) = item else { return false }
            return link.target.browseId == "FEmusic_moods_and_genres_category" && link.target.params != nil
        })
        let trending = try shelf(explore, "Trending")
        #expect(trending.layout == .rows)
        #expect(trending.more?.browseId.hasPrefix("VL") == true)
        guard case .song(let first) = trending.items[0] else {
            Issue.record("expected song")
            return
        }
        #expect(first.rank == ChartRank(position: 1, trend: nil))
        #expect(first.artists.map(\.name) == ["DNK"])
        #expect(first.album?.browseId == "MPREb_I7uEyV5AvQL")
        let videos = try shelf(explore, "New music videos")
        #expect(videos.more == BrowseTarget(browseId: "FEmusic_new_releases_videos"))
        #expect(videos.items.allSatisfy { if case .song(let song) = $0 { song.isVideo } else { false } })
    }

    @Test func newReleasesHasTitleGridAndCarousels() throws {
        let releases = try page("new-releases")
        #expect(releases.title == "New releases")
        #expect(releases.shelves.items.map(\.layout) == [.grid, .cards, .cards])
    }

    @Test func moodsAndGenresGridsHaveTitles() throws {
        let moods = try page("moods-and-genres")
        #expect(moods.title == "Moods & genres")
        #expect(moods.shelves.items.map(\.title) == ["Moods & moments", "Genres"])
        #expect(moods.shelves.items.allSatisfy { $0.layout == .grid })
    }

    @Test func moodCategoryHasTitleAndMoreTargetsWithParams() throws {
        let category = try page("mood-category")
        #expect(category.title == "Chill")
        #expect(category.shelves.items.allSatisfy { $0.more?.browseId == "FEmusic_moods_and_genres_category" && $0.more?.params != nil })
    }

    @Test func morePageIsASingleGrid() throws {
        let more = try page("more-albums")
        #expect(more.title == "Albums & singles")
        #expect(more.shelves.items.count == 1)
        #expect(more.shelves.items[0].layout == .grid)
        #expect(more.shelves.items[0].items.allSatisfy { if case .album = $0 { true } else { false } })
    }

    @Test func unknownShelfInjectedIntoARealPageKeepsTheRest() throws {
        var root = try #require(JSONSerialization.jsonObject(with: Fixture.data("explore")) as? [String: Any])
        let unknown: [String: Any] = ["futureShelfRenderer": ["contents": ["x"]]]
        func inject(_ node: Any) -> Any {
            if var object = node as? [String: Any] {
                if var list = object["sectionListRenderer"] as? [String: Any], let contents = list["contents"] as? [Any] {
                    list["contents"] = [unknown] + contents + [unknown]
                    object["sectionListRenderer"] = list
                    return object
                }
                return object.mapValues(inject)
            }
            if let array = node as? [Any] { return array.map(inject) }
            return node
        }
        root = try #require(inject(root) as? [String: Any])
        let injected = try JSONValue(response: JSONSerialization.data(withJSONObject: root))
        #expect(try BrowsePage(browse: injected).shelves.items == page("explore").shelves.items)
    }

    @Test func responseWithoutSectionListThrows() throws {
        #expect(throws: InnerTubeError.unexpectedResponse) { try BrowsePage(browse: Fixture.json("suggestions")) }
    }
}
