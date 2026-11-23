import Foundation
import InnerTube
import Testing

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedSearches: [String] = []
    private var recordedTokens: [String] = []

    var searches: [String] { lock.withLock { recordedSearches } }
    var tokens: [String] { lock.withLock { recordedTokens } }
    func record(search: String) { lock.withLock { recordedSearches.append(search) } }
    func record(token: String) { lock.withLock { recordedTokens.append(token) } }
}

private struct Failure: Error {}

extension SearchLoader {
    static let stub = SearchLoader(
        suggestions: { _, _ in SearchSuggestions() },
        search: { _, _, _ in SearchResults(chips: [], topResult: nil, items: Page(items: [], continuation: nil), correction: nil) },
        more: { _, _ in Page(items: [], continuation: nil) },
        feedback: { _, _ in })
}

private func song(_ id: String, video: Bool = false) -> MusicItem { .song(Song(videoId: id, title: id, isVideo: video)) }
private func album(_ id: String) -> MusicItem { .album(Album(browseId: id, title: id)) }
private func artist(_ id: String) -> MusicItem { .artist(Artist(browseId: id, name: id)) }
private func playlist(_ id: String) -> MusicItem { .playlist(Playlist(browseId: id, title: id)) }
private func link(_ id: String) -> MusicItem { .link(NavigationLink(title: id, target: BrowseTarget(browseId: id))) }

private func results(
    _ items: [MusicItem], top: MusicItem? = nil, chips: [Chip] = [], next: String? = nil
) -> SearchResults {
    SearchResults(chips: chips, topResult: top, items: Page(items: items, continuation: next), correction: nil)
}

private let allChips = [
    Chip(title: "Songs", searchParams: "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"),
    Chip(title: "Videos", searchParams: "EgWKAQIQAWoKEAkQBRAKEAMQBA%3D%3D"),
    Chip(title: "Albums", searchParams: "EgWKAQIYAWoKEAkQBRAKEAMQBA%3D%3D"),
    Chip(title: "Community playlists", searchParams: "EgeKAQQoAEABagoQCRAFEAoQAxAE"),
    Chip(title: "Artists", searchParams: "EgWKAQIgAWoKEAkQBRAKEAMQBA%3D%3D"),
    Chip(title: "Featured playlists", searchParams: "EgeKAQQoADgBagoQCRAFEAoQAxAE"),
]

private func loader(
    _ calls: Calls, search: @escaping @Sendable (String, String?) async throws -> SearchResults,
    more: @escaping @Sendable (String) async throws -> Page<MusicItem> = { _ in Page(items: [], continuation: nil) }
) -> SearchLoader {
    SearchLoader(
        suggestions: { _, _ in SearchSuggestions() },
        search: { query, params, _ in
            calls.record(search: query)
            return try await search(query, params)
        },
        more: { token, _ in
            calls.record(token: token)
            return try await more(token)
        },
        feedback: { _, _ in })
}

@MainActor
private func makeModel(
    _ loader: SearchLoader, query: String = "q", filter: String? = nil, chips: [Chip] = []
) -> SearchModel {
    SearchModel(query: query, filter: filter, chips: chips, loader: loader, credentials: { nil })
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(3)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@MainActor
private func content(_ model: SearchModel) -> SearchModel.Content? {
    if case .loaded(let content) = model.state { content } else { nil }
}

@MainActor
struct SearchModelTests {
    @Test func unfilteredResultsAreGroupedInFixedOrderAndCapped() async {
        let items = (1...6).map { song("s\($0)") } + [video("v1"), album("a1"), artist("r1"), playlist("p1"), link("l1")]
        let model = makeModel(loader(Calls(), search: { _, _ in results(items.reversed(), chips: allChips) }))
        await model.load()
        let page = content(model)
        #expect(page?.isFiltered == false)
        #expect(page?.sections.map(\.kind) == [.songs, .videos, .albums, .artists, .playlists])
        #expect(page?.sections.first?.items.count == SearchSection.rowLimit)
        #expect(page?.sections.flatMap(\.items).contains(link("l1")) == false)
    }

    @Test func showAllParamsResolveByPrefix() {
        let sections = SearchSection.sections(
            [song("s"), video("v"), album("a"), artist("r"), playlist("p")], chips: allChips)
        #expect(sections.map(\.showAllParams) == [
            allChips[0].searchParams, allChips[1].searchParams, allChips[2].searchParams, allChips[4].searchParams,
            allChips[3].searchParams,
        ])
    }

    @Test func playlistsFallBackToFeaturedAndMissingChipsGiveNil() {
        let featuredOnly = allChips.filter { $0.title != "Community playlists" }
        #expect(SearchSection.sections([playlist("p")], chips: featuredOnly).first?.showAllParams == allChips[5].searchParams)
        #expect(SearchSection.sections([song("s")], chips: []).first?.showAllParams == nil)
    }

    @Test func selectedChipMakesTheResultFilteredAndPaged() async {
        let chips = [Chip(title: "Songs", searchParams: "EgWKAQII", isSelected: true)]
        let model = makeModel(loader(Calls(), search: { _, _ in results([song("a")], chips: chips, next: "t1") }), filter: "EgWKAQII")
        await model.load()
        #expect(content(model)?.isFiltered == true)
        #expect(content(model)?.paging == .idle)
        #expect(content(model)?.sections.isEmpty == true)
    }

    @Test func loadMoreAppendsOnceAndStopsOnARepeatedToken() async {
        let calls = Calls()
        let chips = [Chip(title: "Songs", searchParams: "EgWKAQII", isSelected: true)]
        let model = makeModel(
            loader(
                calls, search: { _, _ in results([song("a")], chips: chips, next: "t1") },
                more: { _ in Page(items: [song("b")], continuation: "t1") }),
            filter: "EgWKAQII")
        await model.load()
        model.loadMore()
        model.loadMore()
        #expect(await waitUntil { content(model)?.paging == .done })
        #expect(content(model)?.items == [song("a"), song("b")])
        #expect(calls.tokens == ["t1"])
        model.loadMore()
        #expect(calls.tokens == ["t1"])
    }

    @Test func loadMoreFailureCanBeRetried() async {
        let chips = [Chip(title: "Songs", searchParams: "EgWKAQII", isSelected: true)]
        let attempts = Counter()
        let model = makeModel(
            loader(
                Calls(), search: { _, _ in results([song("a")], chips: chips, next: "t1") },
                more: { _ in
                    if attempts.next() == 1 { throw Failure() }
                    return Page(items: [song("b")], continuation: nil)
                }),
            filter: "EgWKAQII")
        await model.load()
        model.loadMore()
        #expect(await waitUntil { content(model)?.paging == .failed })
        model.retryMore()
        #expect(await waitUntil { content(model)?.paging == .done })
        #expect(content(model)?.items.count == 2)
    }

    @Test func emptyResultsGiveEmptyAndATopResultAloneDoesNot() async {
        let empty = makeModel(loader(Calls(), search: { _, _ in results([]) }))
        await empty.load()
        guard case .empty = empty.state else { Issue.record("expected empty"); return }
        let topOnly = makeModel(loader(Calls(), search: { _, _ in results([], top: artist("r")) }))
        await topOnly.load()
        #expect(content(topOnly)?.topResult == artist("r"))
    }

    @Test func errorGivesFailedAndRetryRefetches() async {
        let calls = Calls()
        let attempts = Counter()
        let model = makeModel(loader(calls, search: { _, _ in
            if attempts.next() == 1 { throw Failure() }
            return results([song("a")])
        }))
        await model.load()
        guard case .failed = model.state else { Issue.record("expected failed"); return }
        let before = model.loadKey
        model.retry()
        #expect(model.loadKey != before)
        await model.load()
        #expect(content(model) != nil)
        #expect(calls.searches.count == 2)
    }

    @Test func notReadyDoesNotFetchUntilReady() async {
        let calls = Calls()
        let model = makeModel(loader(calls, search: { _, _ in results([song("a")]) }))
        model.isReady = false
        await model.load()
        #expect(calls.searches.isEmpty)
        model.isReady = true
        await model.load()
        #expect(content(model) != nil)
    }

    @Test func staleResponseAfterCancelInFlightIsDropped() async {
        let model = makeModel(loader(Calls(), search: { _, _ in
            try await Task.sleep(for: .milliseconds(50))
            return results([song("a")])
        }))
        let task = Task { await model.load() }
        try? await Task.sleep(for: .milliseconds(10))
        model.cancelInFlight()
        await task.value
        guard case .loading = model.state else { Issue.record("expected loading"); return }
    }

    @Test func seededChipsSurviveLoadingAndSelectionFollowsTheRoute() async {
        let model = makeModel(
            loader(Calls(), search: { _, _ in try await Task.sleep(for: .milliseconds(50)); return results([song("a")]) }),
            filter: "EgWKAQII", chips: allChips)
        let task = Task { await model.load() }
        try? await Task.sleep(for: .milliseconds(10))
        #expect(model.chips == allChips)
        #expect(model.isChipSelected(Chip(title: "Songs", searchParams: "EgWKAQII")))
        #expect(!model.isAllSelected)
        await task.value
        #expect(model.isAllSelected)
    }

    @Test func storeSeedsANewModelWithTheChipsOfTheSameQuery() async {
        let store = BrowseStore(
            loader: BrowseLoader(page: { _, _ in throw Failure() }, more: { _, _ in throw Failure() }),
            searchLoader: loader(Calls(), search: { _, _ in results([song("a")], chips: allChips) }), entityLoader: .stub,
            libraryLoader: .stub, toasts: ToastCenter(), credentials: { nil })
        let first = store.searchModel(for: .search(query: "q", filter: nil))
        await first?.load()
        let second = store.searchModel(for: .search(query: "q", filter: allChips[0].searchParams))
        #expect(second?.chips == allChips)
        #expect(store.searchModel(for: .search(query: "other", filter: nil))?.chips.isEmpty == true)
        #expect(store.searchModel(for: .album(browseId: "x")) == nil)
    }
}

private func video(_ id: String) -> MusicItem { song(id, video: true) }

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { value += 1; return value } }
}
