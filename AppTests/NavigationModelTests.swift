import Foundation
import Testing

@MainActor
struct NavigationModelTests {
    @Test func pushThenBackThenForward() {
        let model = NavigationModel()
        model.push(.album(browseId: "a"))
        model.push(.artist(channelId: "b"))
        model.back()
        #expect(model.path(for: .home) == [.album(browseId: "a")])
        #expect(model.canGoForward)
        model.forward()
        #expect(model.path(for: .home) == [.album(browseId: "a"), .artist(channelId: "b")])
        #expect(!model.canGoForward)
    }

    @Test func pushClearsForward() {
        let model = NavigationModel()
        model.push(.album(browseId: "a"))
        model.back()
        model.push(.artist(channelId: "b"))
        #expect(!model.canGoForward)
    }

    @Test func systemPopFeedsForward() {
        let model = NavigationModel()
        model.push(.album(browseId: "a"))
        model.push(.artist(channelId: "b"))
        model.setPath([], for: .home)
        #expect(model.canGoForward)
        model.forward()
        model.forward()
        #expect(model.path(for: .home) == [.album(browseId: "a"), .artist(channelId: "b")])
    }

    @Test func unrelatedPathReplacementClearsForward() {
        let model = NavigationModel()
        model.push(.album(browseId: "a"))
        model.back()
        model.setPath([.history], for: .home)
        #expect(!model.canGoForward)
    }

    @Test func reselectingPopsToRootAndRequestsScroll() {
        let model = NavigationModel()
        model.push(.album(browseId: "a"))
        model.back()
        model.push(.artist(channelId: "b"))
        model.select(.home)
        #expect(model.path(for: .home).isEmpty)
        #expect(!model.canGoForward)
        #expect(model.scrollToTopRequests[.home] == 1)
    }

    @Test func switchingSectionKeepsStacks() {
        let model = NavigationModel()
        model.push(.album(browseId: "a"))
        model.select(.explore)
        model.push(.explore(.charts))
        model.select(.home)
        #expect(model.path(for: .home) == [.album(browseId: "a")])
        #expect(model.path(for: .explore) == [.explore(.charts)])
    }

    @Test func goHomeSelectsHomeAtItsRoot() {
        let model = NavigationModel()
        model.push(.album(browseId: "a"))
        model.select(.explore)
        model.goHome()
        #expect(model.selection == .home)
        #expect(model.path(for: .home).isEmpty)
    }

    @Test func dropAccountRoutesTruncatesAndFallsBackFromLibrary() {
        let model = NavigationModel()
        model.push(.album(browseId: "a"))
        model.push(.playlist(browseId: Route.likedMusicBrowseId))
        model.push(.artist(channelId: "b"))
        model.select(.library)
        model.push(.library(section: nil))
        model.dropAccountRoutes()
        #expect(model.path(for: .home) == [.album(browseId: "a")])
        #expect(model.path(for: .library).isEmpty)
        #expect(model.selection == .home)
    }

    @Test func dropAccountRoutesFiltersForward() {
        let model = NavigationModel()
        model.push(.history)
        model.back()
        model.dropAccountRoutes()
        #expect(!model.canGoForward)
    }

    @Test func everyPlaylistIsAccountOnly() {
        #expect(Route.playlist(browseId: "VLPL123").requiresAccount)
        #expect(Route.history.requiresAccount)
        #expect(Route.more(browseId: "FEmusic_x", params: nil).requiresAccount)
    }

    @Test func dropAccountRoutesClearsLibraryPlaylists() {
        let model = NavigationModel()
        model.select(.library)
        model.push(.playlist(browseId: "VLPLx"))
        model.push(.album(browseId: "a"))
        model.back()
        model.dropAccountRoutes()
        model.select(.library)
        #expect(model.path(for: .library).isEmpty)
        #expect(!model.canGoForward)
    }

    @Test func replaceLastSwapsTheTopAndClearsForward() {
        let model = NavigationModel()
        model.push(.album(browseId: "a"))
        model.push(.search(query: "q", filter: nil))
        model.replaceLast(.search(query: "q", filter: "p"))
        #expect(model.path(for: .home) == [.album(browseId: "a"), .search(query: "q", filter: "p")])
        model.back()
        model.replaceLast(.artist(channelId: "b"))
        #expect(!model.canGoForward)
        #expect(model.path(for: .home) == [.artist(channelId: "b")])
    }

    @Test func replaceLastPushesOnAnEmptyStack() {
        let model = NavigationModel()
        model.replaceLast(.history)
        #expect(model.path(for: .home) == [.history])
    }

    @Test func dropIdentityRoutesTruncatesAtTheFirstAccountRouteAndClearsForward() {
        let model = NavigationModel()
        model.push(.explore(.charts))
        model.push(.search(query: "q", filter: nil))
        model.push(.album(browseId: "a"))
        model.push(.search(query: "r", filter: nil))
        model.back()
        model.dropIdentityRoutes()
        #expect(model.path(for: .home) == [.explore(.charts)])
        #expect(!model.canGoForward)
    }

    @Test func dropIdentityRoutesCutsForwardAtTheFirstAccountRoute() {
        let model = NavigationModel()
        model.push(.explore(.charts))
        model.push(.search(query: "q", filter: nil))
        model.push(.album(browseId: "a"))
        model.back()
        model.back()
        model.dropIdentityRoutes()
        #expect(model.path(for: .home) == [.explore(.charts)])
        #expect(!model.canGoForward)
    }

    @Test func signOutDropsSearchRoutes() {
        let model = NavigationModel()
        model.push(.search(query: "q", filter: nil))
        model.dropAccountRoutes()
        #expect(model.path(for: .home).isEmpty)
    }

    @Test func requestingANewPlaylistCountsEveryRequest() {
        let model = NavigationModel()
        #expect(model.newPlaylistRequests == 0)
        model.requestNewPlaylist()
        model.requestNewPlaylist()
        #expect(model.newPlaylistRequests == 2)
    }

    @Test func newPlaylistRequestCarriesTheSongsAndResets() {
        let model = NavigationModel()
        model.requestNewPlaylist(videoIds: ["a", "b"])
        #expect(model.pendingPlaylistVideoIds == ["a", "b"] && model.newPlaylistRequests == 1)
        model.requestNewPlaylist()
        #expect(model.pendingPlaylistVideoIds.isEmpty)
    }

    @Test func pushAndReplaceLastClosePlayerPage() {
        let model = NavigationModel()
        model.isPlayerPagePresented = true
        model.push(.history)
        #expect(!model.isPlayerPagePresented)
        model.isPlayerPagePresented = true
        model.replaceLast(.history)
        #expect(!model.isPlayerPagePresented)
    }

    private func saved(signedIn: Bool = true, user: Int = 0, build: (NavigationModel) -> Void) throws -> Data {
        let model = NavigationModel()
        build(model)
        return try JSONEncoder().encode(model.snapshot(isSignedIn: signedIn, authUserIndex: user))
    }

    @Test func restoreRoundTripsSectionAndStacks() throws {
        let data = try saved { model in
            model.push(.explore(.charts))
            model.push(.album(browseId: "a"))
            model.select(.library)
            model.push(.playlist(browseId: "p"))
        }
        let model = NavigationModel.restored(from: data, isSignedIn: true, authUserIndex: 0)
        #expect(model.selection == .library)
        #expect(model.path(for: .library) == [.playlist(browseId: "p")])
        #expect(model.path(for: .home) == [.explore(.charts), .album(browseId: "a")])
        #expect(!model.canGoForward)
        model.back()
        #expect(model.path(for: .library).isEmpty)
    }

    @Test func backAfterRestoreWalksTheStack() throws {
        let data = try saved { model in
            model.push(.explore(.charts))
            model.push(.album(browseId: "a"))
        }
        let model = NavigationModel.restored(from: data, isSignedIn: true, authUserIndex: 0)
        model.back()
        #expect(model.path(for: .home) == [.explore(.charts)])
        model.back()
        #expect(model.path(for: .home).isEmpty)
    }

    @Test func signedInSnapshotRestoredAsGuestDropsAccountRoutes() throws {
        let data = try saved { model in
            model.push(.album(browseId: "a"))
            model.push(.playlist(browseId: "p"))
            model.select(.library)
            model.push(.history)
        }
        let model = NavigationModel.restored(from: data, isSignedIn: false, authUserIndex: 0)
        #expect(model.selection == .home)
        #expect(model.path(for: .library).isEmpty)
        #expect(model.path(for: .home) == [.album(browseId: "a")])
    }

    @Test func guestSnapshotRestoredSignedInDropsIdentityRoutes() throws {
        let data = try saved(signedIn: false) { model in
            model.push(.album(browseId: "a"))
            model.push(.search(query: "q", filter: nil))
        }
        let model = NavigationModel.restored(from: data, isSignedIn: true, authUserIndex: 0)
        #expect(model.path(for: .home) == [.album(browseId: "a")])
    }

    @Test func differentAccountDropsIdentityRoutesOnly() throws {
        let data = try saved(user: 0) { model in
            model.push(.album(browseId: "a"))
            model.push(.search(query: "q", filter: nil))
            model.select(.library)
        }
        let model = NavigationModel.restored(from: data, isSignedIn: true, authUserIndex: 1)
        #expect(model.selection == .library)
        #expect(model.path(for: .home) == [.album(browseId: "a")])
    }

    @Test func unreadableVersionedOrDeepSnapshotsStartAtHome() throws {
        let deep = NavigationModel.Snapshot(section: .explore, paths: [.explore: Array(repeating: .history, count: NavigationModel.maxRestoredDepth + 1)], isSignedIn: true, authUserIndex: 0)
        var future = deep
        future.paths = [:]
        future.version = 2
        for data in [Data("junk".utf8), try JSONEncoder().encode(deep), try JSONEncoder().encode(future), nil] {
            let model = NavigationModel.restored(from: data, isSignedIn: true, authUserIndex: 0)
            #expect(model.selection == .home)
            #expect(model.path(for: .explore).isEmpty)
        }
    }
}
