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
}
