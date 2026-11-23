import Testing
@testable import InnerTube

private func library(_ name: String) throws -> LibraryPage {
    try LibraryPage(library: Fixture.json(name))
}

@Suite struct LibraryParserTests {
    @Test(arguments: [
        ("library-playlists", "playlist", true),
        ("library-songs", "song", true),
        ("library-albums", "album", false),
        ("library-artists", "artist", false),
        ("library-subscriptions", "artist", false),
    ])
    func everySectionParsesItsKind(name: String, kind: String, hasContinuation: Bool) throws {
        let page = try library(name)
        #expect(!page.items.items.isEmpty)
        #expect(page.items.items.contains { Self.kind($0) == kind })
        #expect((page.items.continuation != nil) == hasContinuation)
    }

    private static func kind(_ item: MusicItem) -> String {
        switch item {
        case .song: "song"
        case .album: "album"
        case .artist: "artist"
        case .playlist: "playlist"
        case .link: "link"
        }
    }

    @Test func playlistsDropTheNewPlaylistCardAndKeepLikedMusic() throws {
        let items = try library("library-playlists").items.items
        let ids = items.compactMap { item -> String? in
            if case .playlist(let playlist) = item { playlist.browseId } else { nil }
        }
        #expect(ids.count == 2)
        #expect(ids[0] == BrowseTarget.likedMusic.browseId)
    }

    @Test func aSectionPageOffersOnlyItsOwnChipAndItsServerOrders() throws {
        let page = try library("library-playlists")
        #expect(page.sections.map(\.title) == ["Playlists"])
        #expect(page.sections.map(\.target) == [.likedPlaylists])
        #expect(page.sortOptions.map(\.title) == ["Recently saved", "A to Z", "Z to A"])
        #expect(page.sortOptions.map(\.isSelected) == [true, false, false])
        #expect(page.sortOptions.map(\.continuation) == ["PLACEHOLDER_SORT_0", "PLACEHOLDER_SORT_1", "PLACEHOLDER_SORT_2"])
    }

    @Test func theLandingPageListsEverySectionButPodcastsAndProfiles() throws {
        let page = try library("library-landing")
        #expect(page.sections.map(\.title) == ["Playlists", "Songs", "Albums", "Artists"])
        #expect(page.sections.map(\.target) == [.likedPlaylists, .likedSongs, .likedAlbums, .libraryArtists])
    }

    @Test func artistsOfferSubscriptionsAndOpenThePublicArtistPage() throws {
        let page = try library("library-artists")
        #expect(page.sections.map(\.target) == [.libraryArtists, .librarySubscriptions])
        let ids = page.items.items.compactMap { item -> String? in
            if case .artist(let artist) = item { artist.browseId } else { nil }
        }
        #expect(!ids.isEmpty)
        #expect(ids.allSatisfy { $0.hasPrefix("UC") })
    }

    @Test func aSortReloadIsASectionListContinuationWithItsHeader() throws {
        let page = try library("library-reload")
        #expect(page.sortOptions.first(where: \.isSelected)?.title == "A to Z")
        #expect(page.items.items.count == 1)
    }

    @Test func albumsSkipThePodcastShow() throws {
        #expect(try library("library-albums").items.items.count == 2)
    }

    @Test func continuationReadsGridAndShelfRoots() throws {
        let grid = try Page<MusicItem>(libraryContinuation: Fixture.json("library-continuation"))
        #expect(grid.items.count == 1)
        #expect(grid.continuation == nil)
        #expect(throws: InnerTubeError.unexpectedResponse) { try Page<MusicItem>(libraryContinuation: JSONValue.object([:])) }
    }

    @Test func guestLibraryIsAnEmptyPage() throws {
        let page = try library("library-guest")
        #expect(page.items.items.isEmpty)
        #expect(page.items.continuation == nil)
        #expect(page.sections.isEmpty)
    }

    @Test func guideListsPlaylistsInOrderWithLikedMusicFirst() throws {
        let playlists = try [Playlist](guide: Fixture.json("guide"))
        #expect(playlists.map(\.title) == ["Liked music", "Placeholder playlist 1", "Placeholder playlist 2"])
        #expect(playlists[0].browseId == BrowseTarget.likedMusic.browseId)
        #expect(playlists.allSatisfy { $0.subtitle == nil && $0.thumbnailURL != nil })
    }

    @Test func guestGuideHasNoPlaylists() throws {
        #expect(try [Playlist](guide: Fixture.json("guide-guest")).isEmpty)
    }

    @Test func guideRecursesIntoCollapsibleSectionsInOrder() throws {
        let entry: (String, String) -> JSONValue = { title, id in
            .object(["guideEntryRenderer": .object([
                "formattedTitle": .object(["simpleText": .string(title)]),
                "navigationEndpoint": .object(["browseEndpoint": .object(["browseId": .string(id)])]),
            ])])
        }
        let collapsible = JSONValue.object(["guideCollapsibleSectionEntryRenderer": .object([
            "headerEntry": entry("Playlists", "FEmusic_liked_playlists"),
            "sectionItems": .array([entry("A", "VLPLa"), entry("B", "VLPLb")]),
        ])])
        let json = JSONValue.object(["items": .array([.object(["guideSectionRenderer": .object(["items": .array([collapsible])])])])])
        #expect([Playlist](guide: json).map(\.title) == ["A", "B"])
    }
}
