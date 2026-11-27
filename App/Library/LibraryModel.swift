import AppSettings
import Foundation
import InnerTube
import Observation

@MainActor @Observable
final class LibraryModel {
    enum SectionKind: Equatable { case playlists, songs, albums, artists }

    enum Paging: Equatable { case idle, loading, failed, done }

    struct SortOption: Equatable, Identifiable {
        let id: String
        let title: String
        let isSelected: Bool
    }

    struct Content {
        var kind: SectionKind
        /// Already sorted. For playlists this excludes Liked music.
        var items: [MusicItem]
        /// Playlists only; synthesized when the response has none.
        var likedMusic: Playlist?
        var paging: Paging
    }

    enum State {
        case loading
        case loaded(Content)
        case failed
    }

    struct LoadKey: Hashable {
        let section: String?
        let sort: String?
        let attempt: Int
    }

    static let defaultSection = BrowseTarget.likedPlaylists.browseId
    static let localAscending = "local.az"
    static let localDescending = "local.za"

    private(set) var state: State = .loading
    private(set) var sortOptions: [SortOption] = []
    @ObservationIgnored private var sectionChips: [Chip] = []
    private(set) var section = LibraryModel.defaultSection

    @ObservationIgnored private let loader: LibraryLoader
    @ObservationIgnored private let credentials: @MainActor () -> Credentials?
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private var requestedSection: String?
    @ObservationIgnored private var requestedSort: String?
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var lastLoadFailed = false
    @ObservationIgnored private var loadedKey: LoadKey?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isRetired = false
    @ObservationIgnored private var continuation: String?
    @ObservationIgnored private var seen: Set<String> = []
    @ObservationIgnored private var rawItems: [MusicItem] = []
    @ObservationIgnored private var appliedSort: String?
    @ObservationIgnored private var serverSorts: [LibrarySort] = []
    @ObservationIgnored private var moreTask: Task<Void, Never>?

    init(loader: LibraryLoader, credentials: @escaping @MainActor () -> Credentials?, preferences: Preferences = Preferences()) {
        self.loader = loader
        self.credentials = credentials
        self.preferences = preferences
    }

    var loadKey: LoadKey { LoadKey(section: requestedSection, sort: requestedSort, attempt: attempt) }

    /// Kept across loads so the chip row never jumps.
    var sections: [Chip] {
        sectionChips.map { Chip(title: $0.title, target: $0.target, isSelected: $0.target?.browseId == section) }
    }

    static func kind(of browseId: String) -> SectionKind {
        switch browseId {
        case BrowseTarget.likedSongs.browseId: .songs
        case BrowseTarget.likedAlbums.browseId: .albums
        case BrowseTarget.libraryArtists.browseId, BrowseTarget.librarySubscriptions.browseId: .artists
        default: .playlists
        }
    }

    // MARK: Loading

    func load() async {
        let key = loadKey
        guard !isRetired, loadedKey != key else { return }
        let captured = generation
        if case .loaded = state {} else { state = .loading }
        do {
            let fetched = try await fetchFirstPage()
            guard !Task.isCancelled, !isRetired, generation == captured else { return }
            moreTask?.cancel()
            apply(fetched)
            loadedKey = key
            lastLoadFailed = false
        } catch {
            guard !Task.isCancelled, !isRetired, generation == captured else { return }
            if case .loaded = state { lastLoadFailed = true } else { state = .failed }
        }
    }

    func retry() {
        attempt += 1
    }

    /// Called when the network comes back: reloads a failed page, or lets the footer retry a failed continuation.
    func reloadIfFailed() {
        if case .failed = state { attempt += 1 } else if lastLoadFailed { attempt += 1 } else { if case .loaded(let content) = state, content.paging == .failed { update { $0.paging = .idle } } }
    }

    func selectSection(_ chip: Chip) {
        guard let browseId = chip.target?.browseId, browseId != section else { return }
        restart()
        requestedSection = browseId
        requestedSort = nil
        section = browseId
        preferences.librarySection = browseId
    }

    func selectSort(_ option: SortOption) {
        if option.id == Self.localAscending || option.id == Self.localDescending {
            appliedSort = option.isSelected ? nil : option.id
            preferences.setLibrarySort(appliedSort, for: section)
            sortOptions = Self.localOptions(selected: appliedSort)
            rebuildItems()
            return
        }
        guard !option.isSelected else { return }
        restart()
        requestedSort = option.id
        preferences.setLibrarySort(option.id, for: section)
    }

    func loadMore() {
        guard !isRetired, case .loaded(var content) = state, content.paging == .idle, let token = continuation else { return }
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
                update { $0.paging = .failed }
            }
        }
    }

    func retryMore() {
        update { $0.paging = .idle }
        loadMore()
    }

    /// A playlist deleted or removed elsewhere.
    func remove(browseId: String) {
        rawItems.removeAll { $0.dedupeKey == browseId }
        rebuildItems()
    }

    /// Reloads whatever is loaded while the content stays on screen.
    func invalidate() {
        attempt += 1
    }

    func cancelInFlight() {
        isRetired = true
        generation += 1
        moreTask?.cancel()
        continuation = nil
    }

    // MARK: Internals

    private struct Fetched {
        let section: String
        let page: LibraryPage
        let appliedSort: String?
        let sorts: [LibrarySort]
        let sections: [Chip]
    }

    private func restart() {
        generation += 1
        moreTask?.cancel()
        continuation = nil
        loadedKey = nil
        state = .loading
    }

    private func fetchFirstPage() async throws -> Fetched {
        let credentials = credentials()
        let isExplicit = requestedSection != nil
        var section = requestedSection ?? preferences.librarySection ?? Self.defaultSection
        var page: LibraryPage
        if let id = requestedSort, let sort = serverSorts.first(where: { $0.title == id }) {
            page = Self.keepingSorts(of: try await loader.reload(sort.continuation, credentials), selected: id, from: serverSorts)
        } else {
            page = try await loader.page(BrowseTarget(browseId: section), credentials)
        }
        // A section page offers only its own chips (Artists adds Subscriptions); the landing page lists every section.
        var sections = sectionChips
        if sections.isEmpty {
            sections = try await loader.page(.libraryLanding, credentials).sections
        }
        sections = Self.merge(sections, page.sections)
        if !isExplicit, !sections.isEmpty, !sections.contains(where: { $0.target?.browseId == section }) {
            section = Self.defaultSection
            page = try await loader.page(BrowseTarget(browseId: section), credentials)
        }
        let remembered = preferences.librarySort(for: section)
        var applied: String?
        if page.sortOptions.isEmpty {
            applied = remembered.flatMap { [Self.localAscending, Self.localDescending].contains($0) ? $0 : nil }
        } else {
            if requestedSort == nil, let remembered,
               let sort = page.sortOptions.first(where: { $0.title == remembered }), !sort.isSelected {
                page = Self.keepingSorts(of: try await loader.reload(sort.continuation, credentials), selected: remembered, from: page.sortOptions)
            }
            applied = page.sortOptions.first(where: \.isSelected)?.title
        }
        return Fetched(section: section, page: page, appliedSort: applied, sorts: page.sortOptions, sections: sections)
    }

    // A reload may come without the header; the order chosen is then the selected one.
    private static func keepingSorts(of page: LibraryPage, selected: String, from previous: [LibrarySort]) -> LibraryPage {
        guard page.sortOptions.isEmpty else { return page }
        let sorts = previous.map { LibrarySort(title: $0.title, continuation: $0.continuation, isSelected: $0.title == selected) }
        return LibraryPage(sections: page.sections, sortOptions: sorts, items: page.items)
    }

    // Sub-filters a section page adds (Artists offers Subscriptions) go right after their sibling.
    static func merge(_ base: [Chip], _ extra: [Chip]) -> [Chip] {
        var merged = base
        var anchor: Int?
        for chip in extra {
            if let index = merged.firstIndex(where: { $0.target?.browseId == chip.target?.browseId }) {
                anchor = index
            } else {
                let position = anchor.map { $0 + 1 } ?? merged.endIndex
                merged.insert(chip, at: position)
                anchor = position
            }
        }
        return merged
    }

    private func apply(_ fetched: Fetched) {
        section = fetched.section
        if !fetched.sections.isEmpty { sectionChips = fetched.sections }
        serverSorts = fetched.sorts
        appliedSort = fetched.appliedSort
        sortOptions = fetched.page.sortOptions.isEmpty
            ? Self.localOptions(selected: fetched.appliedSort)
            : fetched.page.sortOptions.map { SortOption(id: $0.title, title: $0.title, isSelected: $0.title == fetched.appliedSort) }
        let kind = Self.kind(of: fetched.section)
        seen = [Route.likedMusicBrowseId]
        rawItems = fresh(fetched.page.items.items)
        let server = fetched.page.items.items.compactMap(\.likedMusic).first
        let liked: Playlist? = kind == .playlists ? Playlist(
            browseId: Route.likedMusicBrowseId, title: String(localized: "Liked music"), subtitle: String(localized: "Auto-generated"),
            thumbnailURL: server?.thumbnailURL, playTarget: server?.playTarget) : nil
        let finished = fetched.page.items.continuation == nil
        continuation = fetched.page.items.continuation
        state = .loaded(Content(kind: kind, items: sorted(rawItems), likedMusic: liked, paging: finished ? .done : .idle))
    }

    private func append(_ page: Page<MusicItem>, requestedWith token: String) {
        let items = fresh(page.items)
        let finished = items.isEmpty || page.continuation == nil || page.continuation == token
        rawItems += items
        continuation = finished ? nil : page.continuation
        update {
            $0.items = sorted(rawItems)
            $0.paging = finished ? .done : .idle
        }
    }

    private func fresh(_ items: [MusicItem]) -> [MusicItem] {
        items.filter { seen.insert($0.dedupeKey).inserted }
    }

    private func rebuildItems() {
        update { $0.items = sorted(rawItems) }
    }

    private func sorted(_ items: [MusicItem]) -> [MusicItem] {
        switch appliedSort {
        case Self.localAscending: items.sorted { $0.sortTitle.localizedStandardCompare($1.sortTitle) == .orderedAscending }
        case Self.localDescending: items.sorted { $0.sortTitle.localizedStandardCompare($1.sortTitle) == .orderedDescending }
        default: items
        }
    }

    private static func localOptions(selected: String?) -> [SortOption] {
        [
            SortOption(id: localAscending, title: String(localized: "A to Z"), isSelected: selected == localAscending),
            SortOption(id: localDescending, title: String(localized: "Z to A"), isSelected: selected == localDescending),
        ]
    }

    private func update(_ change: (inout Content) -> Void) {
        guard case .loaded(var content) = state else { return }
        change(&content)
        state = .loaded(content)
    }
}

private extension MusicItem {
    var dedupeKey: String {
        switch self {
        case .song(let song): song.videoId
        case .album(let album): album.browseId
        case .playlist(let playlist): playlist.browseId
        case .artist(let artist): artist.browseId
        case .link(let link): link.title
        }
    }

    var sortTitle: String {
        switch self {
        case .song(let song): song.title
        case .album(let album): album.title
        case .playlist(let playlist): playlist.title
        case .artist(let artist): artist.name
        case .link(let link): link.title
        }
    }

    var likedMusic: Playlist? {
        if case .playlist(let playlist) = self, playlist.browseId == Route.likedMusicBrowseId { playlist } else { nil }
    }
}
