import InnerTube
import Observation

struct SearchSection: Equatable {
    enum Kind: CaseIterable { case songs, videos, albums, artists, playlists }

    let kind: Kind
    let items: [MusicItem]
    let showAllParams: String?
}

extension SearchSection {
    static let rowLimit = Metrics.searchSectionRows

    private static let paramsPrefixes: [Kind: [String]] = [
        .songs: ["EgWKAQII"], .videos: ["EgWKAQIQ"], .albums: ["EgWKAQIY"], .artists: ["EgWKAQIg"],
        .playlists: ["EgeKAQQoAEAB", "EgeKAQQoADgB"],
    ]

    /// Fixed-order sections of an unfiltered response; empty kinds and links are dropped.
    static func sections(_ items: [MusicItem], chips: [Chip]) -> [SearchSection] {
        var buckets: [Kind: [MusicItem]] = [:]
        for item in items {
            switch item {
            case .song(let song): buckets[song.isVideo ? .videos : .songs, default: []].append(item)
            case .album: buckets[.albums, default: []].append(item)
            case .artist: buckets[.artists, default: []].append(item)
            case .playlist: buckets[.playlists, default: []].append(item)
            case .link: break
            }
        }
        return Kind.allCases.compactMap { kind in
            guard let found = buckets[kind] else { return nil }
            return SearchSection(kind: kind, items: Array(found.prefix(rowLimit)), showAllParams: showAllParams(kind, chips: chips))
        }
    }

    // A prefix list is ordered by preference: Community playlists first, Featured as the fallback.
    private static func showAllParams(_ kind: Kind, chips: [Chip]) -> String? {
        let params = chips.compactMap(\.searchParams)
        for prefix in paramsPrefixes[kind] ?? [] {
            if let match = params.first(where: { $0.hasPrefix(prefix) }) { return match }
        }
        return nil
    }
}

@MainActor @Observable
final class SearchModel {
    enum Paging: Equatable { case idle, loading, failed, done }

    struct Content {
        var topResult: MusicItem?
        var items: [MusicItem]
        var sections: [SearchSection]
        var correction: SearchCorrection?
        var isFiltered: Bool
        var paging: Paging
    }

    enum State {
        case loading
        case loaded(Content)
        case empty
        case failed
    }

    struct LoadKey: Hashable {
        let query: String
        let filter: String?
        let attempt: Int
        let isReady: Bool
    }

    private(set) var state: State = .loading
    /// The server's chips, kept across loading so the chip row does not jump.
    private(set) var chips: [Chip]
    let query: String
    let filter: String?
    /// A guest searches only after the guest visitor is connected, so a page and its continuation share one visitor.
    var isReady = true

    @ObservationIgnored private let loader: SearchLoader
    @ObservationIgnored private let credentials: @MainActor () -> Credentials?
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var lastLoadFailed = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var loadedKey: LoadKey?
    @ObservationIgnored private var continuation: String?
    @ObservationIgnored private var moreTask: Task<Void, Never>?

    init(
        query: String, filter: String?, chips: [Chip] = [], loader: SearchLoader,
        credentials: @escaping @MainActor () -> Credentials?
    ) {
        self.query = query
        self.filter = filter
        self.chips = chips
        self.loader = loader
        self.credentials = credentials
    }

    var loadKey: LoadKey { LoadKey(query: query, filter: filter, attempt: attempt, isReady: isReady) }

    /// All mode while loading is decided by the route; once loaded, by the response.
    var isAllSelected: Bool {
        if case .loaded(let content) = state { !content.isFiltered } else { filter == nil }
    }

    func isChipSelected(_ chip: Chip) -> Bool {
        if case .loaded = state { chip.isSelected } else { chip.searchParams == filter }
    }

    func load() async {
        let key = loadKey
        guard key.isReady, loadedKey != key else { return }
        let captured = generation
        if case .loaded = state {} else { state = .loading }
        do {
            let results = try await loader.search(query, filter, credentials())
            guard !Task.isCancelled, generation == captured else { return }
            apply(results)
            loadedKey = key
            lastLoadFailed = false
        } catch {
            guard !Task.isCancelled, generation == captured else { return }
            if case .loaded = state { lastLoadFailed = true } else { state = .failed }
        }
    }

    func retry() {
        attempt += 1
    }

    /// Called when the network comes back: reloads a failed page, or lets the footer retry a failed continuation.
    func reloadIfFailed() {
        if case .failed = state { attempt += 1 } else if lastLoadFailed { attempt += 1 } else { if case .loaded(let content) = state, content.paging == .failed { setPaging(.idle) } }
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

    func cancelInFlight() {
        generation += 1
        moreTask?.cancel()
        continuation = nil
    }

    private func apply(_ results: SearchResults) {
        moreTask?.cancel()
        chips = results.chips
        let isFiltered = results.chips.contains(where: \.isSelected)
        guard results.topResult != nil || !results.items.items.isEmpty else {
            state = .empty
            return
        }
        continuation = isFiltered ? results.items.continuation : nil
        state = .loaded(Content(
            topResult: results.topResult, items: results.items.items,
            sections: isFiltered ? [] : SearchSection.sections(results.items.items, chips: results.chips),
            correction: results.correction, isFiltered: isFiltered, paging: continuation == nil ? .done : .idle))
    }

    private func append(_ page: Page<MusicItem>, requestedWith token: String) {
        guard case .loaded(var content) = state else { return }
        let fresh = page.items.filter { !content.items.contains($0) }
        content.items += fresh
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
}
