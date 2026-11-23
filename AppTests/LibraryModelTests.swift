import AppSettings
import Foundation
import InnerTube
import Testing

private struct Failure: Error {}

private let sectionChips = [
    Chip(title: "Playlists", target: .likedPlaylists, isSelected: true),
    Chip(title: "Songs", target: .likedSongs),
    Chip(title: "Albums", target: .likedAlbums),
    Chip(title: "Artists", target: .libraryArtists),
]

private func playlist(_ id: String) -> MusicItem { .playlist(Playlist(browseId: "VL" + id, title: id)) }
private func album(_ id: String) -> MusicItem { .album(Album(browseId: id, title: id)) }

private func page(
    _ items: [MusicItem], next: String? = nil, sections: [Chip] = sectionChips, sorts: [LibrarySort] = []
) -> LibraryPage {
    LibraryPage(sections: sections, sortOptions: sorts, items: Page(items: items, continuation: next))
}

private func serverSorts(selected: Int = 0) -> [LibrarySort] {
    ["Recent activity", "A to Z", "Z to A"].enumerated().map { LibrarySort(title: $1, continuation: "p\($0)", isSelected: $0 == selected) }
}

private let landing = BrowseTarget.libraryLanding.browseId

private let credentials = Credentials(cookies: [], authUserIndex: 0)

@MainActor
private func makeModel(_ loader: LibraryLoader, preferences: Preferences = makePreferences()) -> LibraryModel {
    LibraryModel(loader: loader, credentials: { credentials }, preferences: preferences)
}

private func makePreferences() -> Preferences {
    let name = "LibraryModelTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return Preferences(defaults: defaults)
}

@MainActor
private func content(_ model: LibraryModel) -> LibraryModel.Content? {
    if case .loaded(let content) = model.state { content } else { nil }
}

@MainActor
private func titles(_ model: LibraryModel) -> [String] {
    (content(model)?.items ?? []).map {
        switch $0 {
        case .playlist(let playlist): playlist.title
        case .album(let album): album.title
        default: "?"
        }
    }
}

@MainActor
struct LibraryModelTests {
    @Test func playlistsAreTheDefaultAndLikedMusicIsSynthesized() async {
        var loader = LibraryLoader.stub
        loader.page = { _, _ in page([playlist("a")]) }
        let model = makeModel(loader)
        await model.load()
        let loaded = content(model)
        #expect(loaded?.kind == .playlists)
        #expect(loaded?.likedMusic?.browseId == Route.likedMusicBrowseId)
        #expect(titles(model) == ["a"])
        #expect(model.sections.map(\.isSelected) == [true, false, false, false])
    }

    @Test func likedMusicFromTheResponseIsNotDuplicatedInTheItems() async {
        var loader = LibraryLoader.stub
        let liked = MusicItem.playlist(Playlist(browseId: "VLLM", title: "Server liked"))
        loader.page = { _, _ in page([playlist("a"), liked, playlist("b")], next: "t1") }
        loader.more = { _, _ in Page(items: [liked, playlist("c")], continuation: nil) }
        let model = makeModel(loader)
        await model.load()
        model.loadMore()
        #expect(await waitUntil { content(model)?.paging == .done })
        #expect(titles(model) == ["a", "b", "c"])
        #expect(content(model)?.likedMusic?.title == "Server liked")
    }

    @Test func rememberedSectionLoadsFirstAndIsMarkedSelected() async {
        let preferences = makePreferences()
        preferences.librarySection = "FEmusic_liked_albums"
        let calls = CallLog()
        var loader = LibraryLoader.stub
        loader.page = { target, _ in
            calls.record(target.browseId)
            return page([album("x")])
        }
        let model = makeModel(loader, preferences: preferences)
        await model.load()
        #expect(calls.all == ["FEmusic_liked_albums", landing])
        #expect(content(model)?.kind == .albums)
        #expect(model.sections.map(\.isSelected) == [false, false, true, false])
    }

    @Test func rememberedSectionThatIsNotOfferedFallsBackToPlaylists() async {
        let preferences = makePreferences()
        preferences.librarySection = "FEmusic_library_corpus_artists"
        let calls = CallLog()
        var loader = LibraryLoader.stub
        loader.page = { target, _ in
            calls.record(target.browseId)
            return page([playlist("a")])
        }
        let model = makeModel(loader, preferences: preferences)
        await model.load()
        #expect(calls.all == ["FEmusic_library_corpus_artists", landing, "FEmusic_liked_playlists"])
        #expect(content(model)?.kind == .playlists)
    }

    @Test func selectingASectionReloadsAndRemembersIt() async {
        let preferences = makePreferences()
        let calls = CallLog()
        var loader = LibraryLoader.stub
        loader.page = { target, _ in
            calls.record(target.browseId)
            return page([album(target.browseId)])
        }
        let model = makeModel(loader, preferences: preferences)
        await model.load()
        model.selectSection(sectionChips[2])
        guard case .loading = model.state else { Issue.record("expected loading"); return }
        await model.load()
        #expect(calls.all == ["FEmusic_liked_playlists", landing, "FEmusic_liked_albums"])
        #expect(preferences.librarySection == "FEmusic_liked_albums")
        #expect(titles(model) == ["FEmusic_liked_albums"])
    }

    @Test func switchingBackToAnEarlierSectionStillReloads() async {
        var loader = LibraryLoader.stub
        loader.page = { target, _ in page([album(target.browseId)]) }
        let model = makeModel(loader)
        await model.load()
        model.selectSection(sectionChips[1])
        model.selectSection(sectionChips[0])
        await model.load()
        #expect(titles(model) == ["FEmusic_liked_playlists"])
    }

    @Test func serverSortReloadsWithTheOptionsTokenAndIsRememberedByLabel() async {
        let preferences = makePreferences()
        let calls = CallLog()
        var loader = LibraryLoader.stub
        loader.page = { target, _ in
            calls.record(target.browseId)
            return page([playlist("a")], sorts: serverSorts())
        }
        loader.reload = { token, _ in
            calls.record(token)
            return page([playlist("b")], sorts: serverSorts(selected: Int(token.dropFirst()) ?? 0))
        }
        let model = makeModel(loader, preferences: preferences)
        await model.load()
        #expect(model.sortOptions.map(\.title) == ["Recent activity", "A to Z", "Z to A"])
        model.selectSort(model.sortOptions[1])
        await model.load()
        #expect(calls.all == ["FEmusic_liked_playlists", landing, "p1"])
        #expect(model.sortOptions.map(\.isSelected) == [false, true, false])
        #expect(titles(model) == ["b"])
        #expect(preferences.librarySort(for: "FEmusic_liked_playlists") == "A to Z")
    }

    @Test func aReloadWithoutAHeaderKeepsTheOrdersAndMarksTheChosenOne() async {
        var loader = LibraryLoader.stub
        loader.page = { _, _ in page([playlist("a")], sorts: serverSorts()) }
        loader.reload = { _, _ in page([playlist("b")], sections: []) }
        let model = makeModel(loader)
        await model.load()
        model.selectSort(model.sortOptions[2])
        await model.load()
        #expect(model.sortOptions.map(\.title) == ["Recent activity", "A to Z", "Z to A"])
        #expect(model.sortOptions.map(\.isSelected) == [false, false, true])
        #expect(model.sections.count == sectionChips.count)
    }

    @Test func rememberedServerSortIsRequestedOnFirstLoad() async {
        let preferences = makePreferences()
        preferences.setLibrarySort("Z to A", for: "FEmusic_liked_playlists")
        let calls = CallLog()
        var loader = LibraryLoader.stub
        loader.page = { target, _ in
            calls.record(target.browseId)
            return page([playlist("a")], sorts: serverSorts())
        }
        loader.reload = { token, _ in
            calls.record(token)
            return page([playlist("a")], sorts: serverSorts(selected: Int(token.dropFirst()) ?? 0))
        }
        let model = makeModel(loader, preferences: preferences)
        await model.load()
        #expect(calls.all == ["FEmusic_liked_playlists", landing, "p2"])
        #expect(model.sortOptions.map(\.isSelected) == [false, false, true])
    }

    @Test func rememberedSortThatIsNotOfferedFallsBackToTheResponsesSelection() async {
        let preferences = makePreferences()
        preferences.setLibrarySort("Gone", for: "FEmusic_liked_playlists")
        let calls = CallLog()
        var loader = LibraryLoader.stub
        loader.page = { target, _ in
            calls.record(target.browseId)
            return page([playlist("a")], sorts: serverSorts())
        }
        let model = makeModel(loader, preferences: preferences)
        await model.load()
        #expect(calls.all == ["FEmusic_liked_playlists", landing])
        #expect(model.sortOptions.map(\.isSelected) == [true, false, false])
    }

    @Test func sectionChipsComeFromTheLandingPageWithSubFiltersAfterTheirSibling() async {
        let subscriptions = Chip(title: "Subscriptions", target: .librarySubscriptions)
        let preferences = makePreferences()
        preferences.librarySection = BrowseTarget.libraryArtists.browseId
        var loader = LibraryLoader.stub
        loader.page = { target, _ in
            target == .libraryLanding
                ? page([], sections: sectionChips)
                : page([], sections: [Chip(title: "Artists", target: .libraryArtists, isSelected: true), subscriptions])
        }
        let model = makeModel(loader, preferences: preferences)
        await model.load()
        #expect(model.sections.map(\.title) == ["Playlists", "Songs", "Albums", "Artists", "Subscriptions"])
        #expect(model.sections.map(\.isSelected) == [false, false, false, true, false])
    }

    @Test func localSortOrdersLoadedItemsAndTogglesOff() async {
        let preferences = makePreferences()
        var loader = LibraryLoader.stub
        loader.page = { _, _ in page([album("b"), album("c"), album("a")]) }
        let model = makeModel(loader, preferences: preferences)
        await model.load()
        #expect(model.sortOptions.map(\.title) == ["A to Z", "Z to A"])
        model.selectSort(model.sortOptions[0])
        #expect(titles(model) == ["a", "b", "c"])
        #expect(preferences.librarySort(for: "FEmusic_liked_playlists") == LibraryModel.localAscending)
        model.selectSort(model.sortOptions[1])
        #expect(titles(model) == ["c", "b", "a"])
        model.selectSort(model.sortOptions[1])
        #expect(titles(model) == ["b", "c", "a"])
        #expect(preferences.librarySort(for: "FEmusic_liked_playlists") == nil)
    }

    @Test func localSortIsRememberedAndAppliesToLaterPages() async {
        let preferences = makePreferences()
        preferences.setLibrarySort(LibraryModel.localDescending, for: "FEmusic_liked_playlists")
        var loader = LibraryLoader.stub
        loader.page = { _, _ in page([album("b"), album("a")], next: "t1") }
        loader.more = { _, _ in Page(items: [album("c")], continuation: nil) }
        let model = makeModel(loader, preferences: preferences)
        await model.load()
        #expect(titles(model) == ["b", "a"])
        model.loadMore()
        #expect(await waitUntil { content(model)?.paging == .done })
        #expect(titles(model) == ["c", "b", "a"])
    }

    @Test func pagingAppendsWithoutDuplicatesAndStopsOnARepeatedToken() async {
        let pages = CallLog()
        var loader = LibraryLoader.stub
        loader.page = { _, _ in page([album("a"), album("b")], next: "t1") }
        loader.more = { token, _ in
            pages.record(token)
            return pages.all.count == 1
                ? Page(items: [album("b"), album("c")], continuation: "t2")
                : Page(items: [album("d")], continuation: "t2")
        }
        let model = makeModel(loader)
        await model.load()
        model.loadMore()
        #expect(await waitUntil { content(model)?.paging == .idle && titles(model).count == 3 })
        model.loadMore()
        #expect(await waitUntil { content(model)?.paging == .done })
        #expect(titles(model) == ["a", "b", "c", "d"])
        model.loadMore()
        #expect(pages.all == ["t1", "t2"])
    }

    @Test func aRepeatedFirstPageEndsPaging() async {
        var loader = LibraryLoader.stub
        loader.page = { _, _ in page([album("a")], next: "t1") }
        loader.more = { _, _ in Page(items: [album("a")], continuation: "t2") }
        let model = makeModel(loader)
        await model.load()
        model.loadMore()
        #expect(await waitUntil { content(model)?.paging == .done })
        #expect(titles(model) == ["a"])
    }

    @Test func aPagingFailureCanBeRetried() async {
        let calls = CallLog()
        var loader = LibraryLoader.stub
        loader.page = { _, _ in page([album("a")], next: "t1") }
        loader.more = { _, _ in
            calls.record("more")
            if calls.all.count == 1 { throw Failure() }
            return Page(items: [album("b")], continuation: nil)
        }
        let model = makeModel(loader)
        await model.load()
        model.loadMore()
        #expect(await waitUntil { content(model)?.paging == .failed })
        model.retryMore()
        #expect(await waitUntil { content(model)?.paging == .done })
        #expect(titles(model) == ["a", "b"])
    }

    @Test func anEmptySectionIsLoadedWithNoItems() async {
        var loader = LibraryLoader.stub
        loader.page = { _, _ in page([]) }
        let model = makeModel(loader, preferences: {
            let preferences = makePreferences()
            preferences.librarySection = "FEmusic_liked_videos"
            return preferences
        }())
        await model.load()
        #expect(content(model)?.kind == .songs)
        #expect(content(model)?.items.isEmpty == true)
    }

    @Test func aFailedLoadCanBeRetried() async {
        let calls = CallLog()
        var loader = LibraryLoader.stub
        loader.page = { _, _ in
            calls.record("page")
            if calls.all.count == 1 { throw Failure() }
            return page([album("a")])
        }
        let model = makeModel(loader)
        await model.load()
        guard case .failed = model.state else { Issue.record("expected failed"); return }
        model.retry()
        await model.load()
        #expect(titles(model) == ["a"])
    }

    @Test func removeDropsAPlaylistFromTheItems() async {
        var loader = LibraryLoader.stub
        loader.page = { _, _ in page([playlist("a"), playlist("b")]) }
        let model = makeModel(loader)
        await model.load()
        model.remove(browseId: "VLa")
        #expect(titles(model) == ["b"])
    }

    @Test func invalidateReloadsWhileTheContentStaysVisible() async {
        let calls = CallLog()
        var loader = LibraryLoader.stub
        loader.page = { target, _ in
            if target == .libraryLanding { return page([]) }
            calls.record("page")
            if calls.all.count > 1 { try await Task.sleep(for: .milliseconds(50)) }
            return page([album("a\(calls.all.count)")])
        }
        let model = makeModel(loader)
        await model.load()
        model.invalidate()
        let reload = Task { await model.load() }
        try? await Task.sleep(for: .milliseconds(15))
        #expect(titles(model) == ["a1"])
        await reload.value
        #expect(titles(model) == ["a2"])
    }

    @Test func aFailedRefreshKeepsTheContent() async {
        let calls = CallLog()
        var loader = LibraryLoader.stub
        loader.page = { target, _ in
            if target == .libraryLanding { return page([]) }
            calls.record("page")
            if calls.all.count > 1 { throw Failure() }
            return page([album("a")])
        }
        let model = makeModel(loader)
        await model.load()
        model.invalidate()
        await model.load()
        #expect(titles(model) == ["a"])
    }

    @Test func cancelInFlightDropsLateResultsAndStopsLoading() async {
        var loader = LibraryLoader.stub
        loader.page = { _, _ in
            try await Task.sleep(for: .milliseconds(40))
            return page([album("a")])
        }
        let model = makeModel(loader)
        let task = Task { await model.load() }
        try? await Task.sleep(for: .milliseconds(10))
        model.cancelInFlight()
        await task.value
        await model.load()
        guard case .loading = model.state else { Issue.record("a retired model must not load"); return }
    }

    @Test func kindIsDerivedFromTheSectionBrowseId() {
        #expect(LibraryModel.kind(of: "FEmusic_liked_playlists") == .playlists)
        #expect(LibraryModel.kind(of: "FEmusic_liked_videos") == .songs)
        #expect(LibraryModel.kind(of: "FEmusic_liked_albums") == .albums)
        #expect(LibraryModel.kind(of: "FEmusic_library_corpus_track_artists") == .artists)
        #expect(LibraryModel.kind(of: "FEmusic_library_corpus_artists") == .artists)
    }
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
