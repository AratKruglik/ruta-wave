import AppSettings
import Foundation
import InnerTube
import Observation

struct BrowseLoader: Sendable {
    var page: @Sendable (BrowseModel.Source, Credentials?) async throws -> ChartsPage
    var more: @Sendable (String, Credentials?) async throws -> Page<Shelf>

    static func live(_ client: InnerTubeClient) -> BrowseLoader {
        BrowseLoader(
            page: { source, credentials in
                switch source {
                case .home(let params):
                    ChartsPage(page: try await client.home(params: params, credentials: credentials), countries: [], selectedCountry: nil)
                case .browse(let target):
                    ChartsPage(page: try await client.browse(target, credentials: credentials), countries: [], selectedCountry: nil)
                case .charts(let country):
                    try await client.charts(country: country, credentials: credentials)
                }
            },
            more: { token, credentials in try await client.browseContinuation(token, credentials: credentials) })
    }
}

@MainActor @Observable
final class BrowseModel {
    enum Source: Hashable, Sendable {
        case home(chipParams: String?)
        case browse(BrowseTarget)
        case charts(country: String?)
    }

    enum Paging: Equatable { case idle, loading, failed, done }

    struct Content {
        var title: String?
        var chips: [Chip]
        var shelves: [Shelf]
        var countries: [ChartCountry]
        var selectedCountry: String?
        var paging: Paging
    }

    enum State {
        case loading
        case loaded(Content)
        case empty
        case failed
    }

    struct LoadKey: Hashable {
        let source: Source
        let attempt: Int
        let isReady: Bool
    }

    private(set) var state: State = .loading
    private(set) var source: Source
    /// A guest browses only after the guest visitor is connected, so a page and its continuation share one visitor.
    var isReady = true
    var scrollAnchor: Int?

    @ObservationIgnored private let loader: BrowseLoader
    @ObservationIgnored private let credentials: @MainActor () -> Credentials?
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var loadedKey: LoadKey?
    @ObservationIgnored private var continuation: String?
    @ObservationIgnored private var moreTask: Task<Void, Never>?

    init(
        source: Source, loader: BrowseLoader, credentials: @escaping @MainActor () -> Credentials?,
        preferences: Preferences = Preferences()
    ) {
        self.source = source
        self.loader = loader
        self.credentials = credentials
        self.preferences = preferences
    }

    /// An explicit pick wins; otherwise the system region, computed on every call and never stored.
    static func chartsSource(preferences: Preferences = Preferences(), region: String? = Locale.current.region?.identifier) -> Source {
        .charts(country: preferences.chartCountry ?? region)
    }

    var loadKey: LoadKey { LoadKey(source: source, attempt: attempt, isReady: isReady) }

    func load() async {
        let key = loadKey
        guard key.isReady, loadedKey != key else { return }
        let captured = generation
        if case .loaded = state {} else { state = .loading }
        do {
            let page = try await fetch()
            guard !Task.isCancelled, generation == captured else { return }
            apply(page)
            loadedKey = key
        } catch {
            guard !Task.isCancelled, generation == captured else { return }
            state = .failed
        }
    }

    func retry() {
        attempt += 1
    }

    func loadMore() {
        guard case .loaded(var content) = state, content.paging == .idle, let token = continuation else { return }
        content.paging = .loading
        state = .loaded(content)
        let captured = generation
        let credentials = credentials()
        moreTask = Task { [loader] in
            do {
                let page = try await loader.more(token, credentials)
                guard !Task.isCancelled, generation == captured else { return }
                append(page, requestedWith: token)
            } catch {
                guard !Task.isCancelled, generation == captured else { return }
                setPaging(.failed)
            }
        }
    }

    func retryMore() {
        setPaging(.idle)
        loadMore()
    }

    func selectChip(_ chip: Chip) {
        guard case .home = source, let target = chip.target else { return }
        invalidate()
        source = .home(chipParams: chip.isSelected ? nil : target.params)
        state = .loading
    }

    func selectCountry(_ code: String) {
        guard case .charts = source else { return }
        preferences.chartCountry = code
        invalidate()
        source = .charts(country: code)
    }

    // A rejected country is retried once without it (AC-5.3); the stored pick is left alone.
    private func fetch() async throws -> ChartsPage {
        let credentials = credentials()
        do {
            return try await loader.page(source, credentials)
        } catch where !Task.isCancelled {
            guard case .charts(let country) = source, country != nil else { throw error }
            return try await loader.page(.charts(country: nil), credentials)
        }
    }

    private func apply(_ page: ChartsPage) {
        moreTask?.cancel()
        continuation = page.page.shelves.continuation
        let shelves = page.page.shelves.items
        guard !shelves.isEmpty else {
            state = .empty
            return
        }
        state = .loaded(Content(
            title: page.page.title, chips: page.page.chips, shelves: shelves, countries: page.countries,
            selectedCountry: page.selectedCountry, paging: continuation == nil ? .done : .idle))
    }

    private func append(_ page: Page<Shelf>, requestedWith token: String) {
        guard case .loaded(var content) = state else { return }
        let fresh = page.items.filter { !content.shelves.contains($0) }
        content.shelves += fresh
        let finished = fresh.isEmpty || page.continuation == nil || page.continuation == token
        continuation = finished ? nil : page.continuation
        content.paging = finished ? .done : .idle
        state = .loaded(content)
    }

    private func setPaging(_ paging: Paging) {
        guard case .loaded(var content) = state else { return }
        content.paging = paging
        state = .loaded(content)
    }

    func cancelInFlight() { invalidate() }

    // Responses already in flight carry the old generation and are dropped.
    private func invalidate() {
        generation += 1
        moreTask?.cancel()
        continuation = nil
    }
}
