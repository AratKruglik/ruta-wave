import InnerTube
import Testing

@MainActor
struct BrowseRoutingTests {
    @Test(arguments: [
        (BrowseTarget(browseId: "FEmusic_new_releases"), Route.explore(.newReleases)),
        (BrowseTarget(browseId: "FEmusic_charts"), Route.explore(.charts)),
        (BrowseTarget(browseId: "FEmusic_moods_and_genres"), Route.explore(.moods)),
        (BrowseTarget(browseId: "FEmusic_moods_and_genres_category", params: "p"), Route.explore(.mood(params: "p"))),
        (BrowseTarget(browseId: "VLPL1"), Route.playlist(browseId: "VLPL1")),
        (BrowseTarget(browseId: "MPREb_x"), Route.album(browseId: "MPREb_x")),
        (BrowseTarget(browseId: "UCx"), Route.artist(channelId: "UCx")),
        (BrowseTarget(browseId: "FEmusic_new_releases_videos"), Route.more(browseId: "FEmusic_new_releases_videos", params: nil)),
        (BrowseTarget(browseId: "FEmusic_moods_and_genres_category"), Route.more(browseId: "FEmusic_moods_and_genres_category", params: nil)),
        (BrowseTarget(browseId: "FEmusic_x", params: "q"), Route.more(browseId: "FEmusic_x", params: "q")),
    ])
    func targetMapsToRoute(target: BrowseTarget, route: Route) {
        #expect(Route(target: target) == route)
    }

    @Test func itemClicksPlayOrOpen() {
        #expect(MusicItem.song(Song(videoId: "v", title: "T")).route == nil)
        #expect(MusicItem.playlist(Playlist(browseId: "RDCLAK1", title: "Mix")).route == nil)
        #expect(MusicItem.playlist(Playlist(browseId: "VLPL1", title: "List")).route == .playlist(browseId: "VLPL1"))
        #expect(MusicItem.album(Album(browseId: "MPREb1", title: "A")).route == .album(browseId: "MPREb1"))
        #expect(MusicItem.artist(Artist(browseId: "UC1", name: "N")).route == .artist(channelId: "UC1"))
    }

    private func link(_ id: String, _ title: String = "Localized") -> MusicItem {
        .link(NavigationLink(title: title, target: BrowseTarget(browseId: id)))
    }

    @Test func tileShelfIsKeyedOnTargetsNotTitles() {
        let tiles = Shelf(
            title: nil, layout: .grid,
            items: [link("FEmusic_new_releases", "Нові релізи"), link("FEmusic_charts"), link("FEmusic_moods_and_genres")])
        #expect(tiles.isExploreTiles)
        #expect(!tiles.isLinkGrid)
        let moods = Shelf(title: "Moods", layout: .grid, items: [link("FEmusic_moods_and_genres_category", "New releases")])
        #expect(!moods.isExploreTiles)
        #expect(moods.isLinkGrid)
        #expect(ExploreTile.symbol(for: "FEmusic_charts") != nil)
        #expect(ExploreTile.symbol(for: "FEmusic_moods_and_genres_category") == nil)
    }
}
