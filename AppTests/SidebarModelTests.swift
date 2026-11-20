import InnerTube
import Testing

@MainActor
struct SidebarModelTests {
    @Test func guestLoadsEmptyList() async {
        let model = SidebarModel(client: nil)
        await model.load(credentials: nil)
        guard case .loaded(let playlists) = model.state else { Issue.record("expected loaded"); return }
        #expect(playlists.isEmpty)
    }

    @Test func signedInWithoutClientStaysLoading() async {
        let model = SidebarModel(client: nil)
        await model.load(credentials: Credentials(cookies: [], authUserIndex: 0))
        guard case .loading = model.state else { Issue.record("expected loading"); return }
    }

    @Test func pinsLikedMusicFirstWithoutDuplicating() {
        let other = Playlist(browseId: "VLother", title: "Other")
        let liked = Playlist(browseId: Route.likedMusicBrowseId, title: "Liked")
        #expect(SidebarModel.pinningLikedMusic([other, liked]) == [liked, other])
    }

    @Test func addsLikedMusicWhenMissing() {
        let other = Playlist(browseId: "VLother", title: "Other")
        let result = SidebarModel.pinningLikedMusic([other])
        #expect(result.count == 2)
        #expect(result[0].browseId == Route.likedMusicBrowseId)
        #expect(result[1] == other)
    }
}
