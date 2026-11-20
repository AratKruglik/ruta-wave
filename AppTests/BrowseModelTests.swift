import AppSettings
import Foundation
import InnerTube
import Testing

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedSources: [BrowseModel.Source] = []
    private var recordedTokens: [String] = []

    var sources: [BrowseModel.Source] { lock.withLock { recordedSources } }
    var tokens: [String] { lock.withLock { recordedTokens } }
    func record(_ source: BrowseModel.Source) { lock.withLock { recordedSources.append(source) } }
    func record(token: String) { lock.withLock { recordedTokens.append(token) } }
}

private struct Failure: Error {}

private func shelf(_ title: String) -> Shelf {
    Shelf(title: title, layout: .cards, items: [.song(Song(videoId: title, title: title))])
}

private func chartsPage(
    _ titles: [String], next: String? = nil, chips: [Chip] = [], countries: [ChartCountry] = [], selected: String? = nil
) -> ChartsPage {
    ChartsPage(
        page: BrowsePage(title: nil, chips: chips, shelves: Page(items: titles.map(shelf), continuation: next)),
        countries: countries, selectedCountry: selected)
}

private func page(_ titles: [String], next: String? = nil, chips: [Chip] = []) -> ChartsPage {
    chartsPage(titles, next: next, chips: chips)
}

private func loader(
    _ calls: Calls, page: @escaping @Sendable (BrowseModel.Source) async throws -> ChartsPage,
    more: @escaping @Sendable (String) async throws -> Page<Shelf> = { _ in Page(items: [], continuation: nil) }
) -> BrowseLoader {
    BrowseLoader(
        page: { source, _ in
            calls.record(source)
            return try await page(source)
        },
        more: { token, _ in
            calls.record(token: token)
            return try await more(token)
        })
}

@MainActor
private func makeModel(
    _ source: BrowseModel.Source = .home(chipParams: nil), loader: BrowseLoader, preferences: Preferences? = nil
) -> BrowseModel {
    BrowseModel(
        source: source, loader: loader, credentials: { nil },
        preferences: preferences ?? Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!))
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
private func shelfTitles(_ model: BrowseModel) -> [String?] {
    if case .loaded(let content) = model.state { content.shelves.map(\.title) } else { [] }
}

@MainActor
private func paging(_ model: BrowseModel) -> BrowseModel.Paging? {
    if case .loaded(let content) = model.state { content.paging } else { nil }
}

@MainActor
struct BrowseModelTests {
    @Test func secondLoadWithTheSameKeyMakesNoRequest() async {
        let calls = Calls()
        let model = makeModel(loader: loader(calls, page: { _ in page(["a"]) }))
        await model.load()
        await model.load()
        #expect(calls.sources.count == 1)
        #expect(shelfTitles(model) == ["a"])
    }

    @Test func pagesThroughContinuationsAndFinishes() async {
        let calls = Calls()
        let model = makeModel(loader: loader(
            calls, page: { _ in page(["a"], next: "t1") },
            more: { token in token == "t1" ? Page(items: [shelf("b")], continuation: "t2") : Page(items: [shelf("c")], continuation: nil) }))
        await model.load()
        #expect(paging(model) == .idle)
        model.loadMore()
        #expect(await waitUntil { paging(model) == .idle && shelfTitles(model) == ["a", "b"] })
        model.loadMore()
        #expect(await waitUntil { paging(model) == .done })
        #expect(shelfTitles(model) == ["a", "b", "c"])
        #expect(calls.tokens == ["t1", "t2"])
    }

    @Test func onlyOneContinuationRequestIsInFlight() async {
        let calls = Calls()
        let model = makeModel(loader: loader(
            calls, page: { _ in page(["a"], next: "t1") },
            more: { _ in
                try await Task.sleep(for: .milliseconds(50))
                return Page(items: [shelf("b")], continuation: nil)
            }))
        await model.load()
        model.loadMore()
        model.loadMore()
        #expect(await waitUntil { paging(model) == .done })
        #expect(calls.tokens == ["t1"])
    }

    @Test func partErrorKeepsShelvesAndRetryAppends() async {
        let failing = Calls()
        let model = makeModel(loader: loader(
            failing, page: { _ in page(["a"], next: "t1") },
            more: { _ in
                if failing.tokens.count == 1 { throw Failure() }
                return Page(items: [shelf("b")], continuation: nil)
            }))
        await model.load()
        model.loadMore()
        #expect(await waitUntil { paging(model) == .failed })
        #expect(shelfTitles(model) == ["a"])
        model.retryMore()
        #expect(await waitUntil { paging(model) == .done })
        #expect(shelfTitles(model) == ["a", "b"])
    }

    @Test func pageErrorThenRetryLoads() async {
        let calls = Calls()
        let model = makeModel(loader: loader(calls, page: { _ in
            if calls.sources.count == 1 { throw Failure() }
            return page(["a"])
        }))
        await model.load()
        guard case .failed = model.state else { Issue.record("expected failed"); return }
        model.retry()
        await model.load()
        #expect(shelfTitles(model) == ["a"])
    }

    @Test func noShelvesIsEmpty() async {
        let model = makeModel(loader: loader(Calls(), page: { _ in page([]) }))
        await model.load()
        guard case .empty = model.state else { Issue.record("expected empty"); return }
    }

    @Test func chipSelectsAndDeselects() async {
        let relax = Chip(title: "Relax", target: BrowseTarget(browseId: "FEmusic_home", params: "p1"))
        let calls = Calls()
        let model = makeModel(loader: loader(calls, page: { source in
            if case .home(.some) = source {
                return page(["x"], chips: [Chip(title: "Relax", target: relax.target, isSelected: true)])
            }
            return page(["a"], chips: [relax])
        }))
        await model.load()
        model.selectChip(relax)
        await model.load()
        #expect(model.source == .home(chipParams: "p1"))
        guard case .loaded(let content) = model.state, let selected = content.chips.first else { Issue.record("expected chips"); return }
        model.selectChip(selected)
        #expect(model.source == .home(chipParams: nil))
        await model.load()
        #expect(calls.sources == [.home(chipParams: nil), .home(chipParams: "p1"), .home(chipParams: nil)])
    }

    @Test func staleContinuationAfterAChipSwitchIsDropped() async {
        let relax = Chip(title: "Relax", target: BrowseTarget(browseId: "FEmusic_home", params: "p1"))
        let model = makeModel(loader: loader(
            Calls(), page: { source in
                if case .home(.some) = source { return page(["x"]) }
                return page(["a"], next: "t1", chips: [relax])
            },
            more: { _ in
                try await Task.sleep(for: .milliseconds(100))
                return Page(items: [shelf("late")], continuation: nil)
            }))
        await model.load()
        model.loadMore()
        model.selectChip(relax)
        await model.load()
        try? await Task.sleep(for: .milliseconds(250))
        #expect(shelfTitles(model) == ["x"])
    }

    @Test func repeatedTokenOrDuplicateShelvesStopPaging() async {
        let sameToken = makeModel(loader: loader(
            Calls(), page: { _ in page(["a"], next: "t1") }, more: { _ in Page(items: [shelf("b")], continuation: "t1") }))
        await sameToken.load()
        sameToken.loadMore()
        #expect(await waitUntil { paging(sameToken) == .done })
        #expect(shelfTitles(sameToken) == ["a", "b"])

        let duplicates = makeModel(loader: loader(
            Calls(), page: { _ in page(["a"], next: "t1") }, more: { _ in Page(items: [shelf("a")], continuation: "t2") }))
        await duplicates.load()
        duplicates.loadMore()
        #expect(await waitUntil { paging(duplicates) == .done })
        #expect(shelfTitles(duplicates) == ["a"])

        let empty = makeModel(loader: loader(
            Calls(), page: { _ in page(["a"], next: "t1") }, more: { _ in Page(items: [], continuation: "t2") }))
        await empty.load()
        empty.loadMore()
        #expect(await waitUntil { paging(empty) == .done })
    }

    @Test func guestDoesNotLoadBeforeTheGateOpens() async {
        let calls = Calls()
        let model = makeModel(loader: loader(calls, page: { _ in page(["a"]) }))
        model.isReady = false
        await model.load()
        #expect(calls.sources.isEmpty)
        model.isReady = true
        await model.load()
        #expect(shelfTitles(model) == ["a"])
    }

    @Test func storeResetReplacesEveryModelAndKeepsTheGate() async {
        let store = BrowseStore(loader: loader(Calls(), page: { _ in page(["a"]) }), searchLoader: .stub, credentials: { nil })
        store.setReady(false)
        let oldHome = store.home
        let route = Route.explore(.newReleases)
        let cached = store.model(for: route)
        #expect(store.model(for: route) === cached)
        store.reset()
        #expect(store.home !== oldHome)
        #expect(store.model(for: route) !== cached)
        #expect(!store.home.isReady)
        #expect(store.model(for: .album(browseId: "MPREb1")) == nil)
    }
}
