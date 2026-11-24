import Foundation
import InnerTube
import Observation

@MainActor @Observable
final class EntityModel {
    enum Kind: Hashable, Sendable {
        case album(BrowseTarget)
        case artist(browseId: String)
        case playlist(browseId: String)
    }

    enum Entity {
        case album(AlbumPage)
        case artist(ArtistPage)
        case playlist(PlaylistPage)
    }

    enum Paging: Equatable { case idle, loading, failed, done }

    /// A successful save or unsave, for the sidebar and the Library.
    enum LibraryChange: Equatable {
        case playlist(Playlist, saved: Bool)
        case album
    }

    struct Content {
        var entity: Entity
        /// The playlist rows; empty for an album and an artist.
        var tracks: [Song]
        var paging: Paging
        /// Suggestions for an own playlist, Related for any other; playlist only.
        var sections: [Shelf]
        var isSaved: Bool
        var isSubscribed: Bool?
    }

    enum State {
        case loading
        case loaded(Content)
        case notAvailable
        case failed
    }

    struct LoadKey: Hashable {
        let kind: Kind
        let attempt: Int
        let isReady: Bool
    }

    private(set) var state: State = .loading
    let kind: Kind
    /// A guest loads only after the guest visitor is connected, so a page and its continuation share one visitor.
    var isReady = true

    @ObservationIgnored private let loader: EntityLoader
    @ObservationIgnored private let credentials: @MainActor () -> Credentials?
    @ObservationIgnored private let toasts: ToastCenter
    @ObservationIgnored private let onLibraryChange: @MainActor (LibraryChange) -> Void
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var lastLoadFailed = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isRetired = false
    @ObservationIgnored private var loadedKey: LoadKey?
    @ObservationIgnored private var continuation: String?
    @ObservationIgnored private var sectionsToken: String?
    @ObservationIgnored private var seen: Set<String> = []
    @ObservationIgnored private var moreTask: Task<Void, Never>?
    @ObservationIgnored private var sectionsTask: Task<Void, Never>?
    @ObservationIgnored private var saveIntent = 0
    @ObservationIgnored private var subscribeIntent = 0

    init(
        kind: Kind, loader: EntityLoader, credentials: @escaping @MainActor () -> Credentials?, toasts: ToastCenter,
        onLibraryChange: @escaping @MainActor (LibraryChange) -> Void = { _ in }
    ) {
        self.kind = kind
        self.loader = loader
        self.credentials = credentials
        self.toasts = toasts
        self.onLibraryChange = onLibraryChange
    }

    var loadKey: LoadKey { LoadKey(kind: kind, attempt: attempt, isReady: isReady) }

    func load() async {
        let key = loadKey
        guard !isRetired, key.isReady, loadedKey != key else { return }
        let captured = generation
        if case .loaded = state {} else { state = .loading }
        do {
            let content = try await fetch()
            guard !Task.isCancelled, !isRetired, generation == captured else { return }
            moreTask?.cancel()
            sectionsTask?.cancel()
            prime(content)
            state = .loaded(content)
            loadedKey = key
            lastLoadFailed = false
        } catch {
            guard !Task.isCancelled, generation == captured else { return }
            if case InnerTubeError.notAvailable = error { state = .notAvailable } else if case .loaded = state { lastLoadFailed = true } else { state = .failed }
        }
    }

    func retry() {
        attempt += 1
    }

    /// Called when the network comes back: reloads a failed page, or lets the footer retry a failed continuation.
    func reloadIfFailed() {
        if case .failed = state { attempt += 1 } else if lastLoadFailed { attempt += 1 } else { if case .loaded(let content) = state, content.paging == .failed { update { $0.paging = .idle } } }
    }

    func loadMore() {
        guard !isRetired, case .loaded(var content) = state, content.paging == .idle, let token = continuation else { return }
        content.paging = .loading
        state = .loaded(content)
        let captured = generation
        let credentials = credentials()
        moreTask = Task { [loader] in
            do {
                let page = try await loader.moreTracks(token, credentials)
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

    /// Suggestions or Related: non-essential, so a failure leaves the shelves out. Starts once, after the last track page.
    func loadSections() {
        guard !isRetired, case .loaded(let content) = state, content.paging == .done, let token = sectionsToken else { return }
        sectionsToken = nil
        let captured = generation
        let credentials = credentials()
        sectionsTask = Task { [loader] in
            guard let page = try? await loader.sections(token, credentials), !Task.isCancelled, generation == captured else { return }
            update { $0.sections = page.items }
        }
    }

    func cancelInFlight() {
        isRetired = true
        generation += 1
        moreTask?.cancel()
        sectionsTask?.cancel()
        continuation = nil
        sectionsToken = nil
    }

    // MARK: Mutations

    /// Optimistic; the last intent wins, so an older failure never reverts a newer toggle.
    func toggleSaved() {
        guard !isRetired, case .loaded(let content) = state, let id = saveId, let credentials = credentials() else { return }
        let saved = !content.isSaved
        update { $0.isSaved = saved }
        saveIntent += 1
        let intent = saveIntent
        let captured = generation
        let change = libraryChange(saved: saved)
        Task { [loader] in
            do {
                try await loader.save(id, saved, credentials)
                guard generation == captured, saveIntent == intent, let change else { return }
                onLibraryChange(change)
            } catch {
                guard generation == captured, saveIntent == intent else { return }
                update { $0.isSaved = !saved }
                toasts.show("Couldn't update your library")
            }
        }
    }

    /// The playlist was deleted or removed from the library elsewhere (the sidebar).
    func playlistRemoved(deleted: Bool) {
        guard case .playlist = kind else { return }
        if deleted {
            cancelInFlight()
            state = .notAvailable
        } else {
            update { $0.isSaved = false }
        }
    }

    func toggleSubscribed() {
        guard !isRetired, case .loaded(let content) = state, case .artist(let page) = content.entity, let subscribed = content.isSubscribed,
              let channelId = page.channelId, let credentials = credentials() else { return }
        update { $0.isSubscribed = !subscribed }
        subscribeIntent += 1
        let intent = subscribeIntent
        let captured = generation
        Task { [loader] in
            do {
                try await loader.subscribe(channelId, !subscribed, credentials)
            } catch {
                guard generation == captured, subscribeIntent == intent else { return }
                update { $0.isSubscribed = subscribed }
                toasts.show("Couldn't update the subscription")
            }
        }
    }

    /// The row is not appended: its `playlistSetVideoId` is unknown here, and a row without it could not be removed or moved.
    /// It shows up on the next load.
    func add(_ song: Song) {
        guard !isRetired, case .playlist(let browseId) = kind, let credentials = credentials() else { return }
        let captured = generation
        Task { [loader] in
            do {
                _ = try await loader.edit(browseId, [.add(videoId: song.videoId)], credentials)
                guard generation == captured else { return }
                update { $0.sections = $0.sections.removing(videoId: song.videoId) }
                toasts.show("Added to playlist")
            } catch {
                guard generation == captured else { return }
                toasts.show("Couldn't add to the playlist")
            }
        }
    }

    // MARK: Own-playlist editing

    var canEdit: Bool {
        if case .playlist(let playlist) = page { playlist.isOwned && kind != .playlist(browseId: Route.likedMusicBrowseId) } else { false }
    }

    var playlistBrowseId: String? {
        if case .playlist(let browseId) = kind { browseId } else { nil }
    }

    var canEditPrivacy: Bool {
        if case .playlist(let playlist) = page { playlist.privacy != nil } else { false }
    }

    var editDraft: NewPlaylistDraft? {
        if case .playlist(let playlist) = page { NewPlaylistDraft(page: playlist) } else { nil }
    }

    /// Sends only the changed fields. Undo sends the previous values.
    func editDetails(_ draft: NewPlaylistDraft) async -> Bool {
        guard canEdit, let original = editDraft, case .playlist(let browseId) = kind, let credentials = credentials() else { return false }
        let edits = draft.edits(from: original)
        guard !edits.isEmpty else { return true }
        let captured = generation
        do {
            _ = try await loader.edit(browseId, edits, credentials)
            guard generation == captured else { return false }
            toasts.show("Playlist updated", undo: { [weak self] in self?.send(original.edits(from: draft), failure: "Couldn't undo") })
            retry()
            return true
        } catch {
            guard generation == captured else { return false }
            toasts.show("Couldn't update the playlist")
            return false
        }
    }

    /// Optimistic; a failure restores the rows. Rows without a set id (not loaded from this playlist) cannot be removed.
    func removeRows(_ keys: [String]) {
        guard canEdit, case .playlist(let browseId) = kind, case .loaded(let content) = state, let credentials = credentials() else { return }
        let wanted = Set(keys)
        let removed = content.tracks.enumerated().filter { wanted.contains($0.element.rowKey) && $0.element.playlistSetVideoId != nil }
        guard !removed.isEmpty else { return }
        let before = content.tracks
        let removedKeys = Set(removed.map(\.element.rowKey))
        let captured = generation
        update { $0.tracks.removeAll { removedKeys.contains($0.rowKey) } }
        let edits = removed.compactMap { entry in
            entry.element.playlistSetVideoId.map { PlaylistEdit.remove(videoId: entry.element.videoId, setVideoId: $0) }
        }
        let placements = Self.placements(of: removed.map(\.offset), in: before)
        Task { [weak self, loader] in
            guard let self else { return }
            do {
                _ = try await loader.edit(browseId, edits, credentials)
                guard generation == captured else { return }
                let count = removed.count
                toasts.show(
                    count == 1 ? "Removed from the playlist" : "Removed \(count) songs",
                    undo: { [weak self] in self?.restore(removed.map(\.element.videoId), placements: placements) })
            } catch {
                guard generation == captured else { return }
                update { $0.tracks = before }
                toasts.show("Couldn't update the playlist")
            }
        }
    }

    /// For each removed row, the set id of the next row that survives; `nil` when nothing survives after it.
    private static func placements(of removedIndexes: [Int], in tracks: [Song]) -> [String?] {
        let removed = Set(removedIndexes)
        return removedIndexes.map { index in
            tracks[(index + 1)...].enumerated().first { !removed.contains(index + 1 + $0.offset) }?.element.playlistSetVideoId
        }
    }

    // Re-adding appends, so each row is moved before the row that followed it; rows that were last stay where the append put them.
    // The first-to-last order keeps rows that shared a successor in order.
    private func restore(_ videoIds: [String], placements: [String?]) {
        guard case .playlist(let browseId) = kind, let credentials = credentials() else { return }
        let captured = generation
        Task { [weak self, loader] in
            guard let self else { return }
            do {
                let added = try await loader.edit(browseId, videoIds.map { .add(videoId: $0) }, credentials)
                guard generation == captured else { return }
                guard added.count == videoIds.count else {
                    toasts.show("Couldn't undo")
                    retry()
                    return
                }
                let moves = zip(added, placements).compactMap { row, before in
                    before.map { PlaylistEdit.move(setVideoId: row.setVideoId, before: $0) }
                }
                if !moves.isEmpty { _ = try await loader.edit(browseId, moves, credentials) }
                guard generation == captured else { return }
                retry()
            } catch {
                guard generation == captured else { return }
                toasts.show("Couldn't undo")
                retry()
            }
        }
    }

    /// Moves an own-playlist row in front of another one (`nil` = to the end). Optimistic, with rollback.
    func moveRow(_ key: String, before beforeKey: String?) {
        guard canEdit, case .playlist(let browseId) = kind, case .loaded(let content) = state, key != beforeKey,
              let credentials = credentials(),
              let from = content.tracks.firstIndex(where: { $0.rowKey == key }), let moving = content.tracks[from].playlistSetVideoId
        else { return }
        let target = beforeKey.flatMap { id in content.tracks.firstIndex { $0.rowKey == id } }
        if beforeKey != nil, target == nil { return }
        let successor = from + 1 < content.tracks.count ? content.tracks[from + 1].playlistSetVideoId : nil
        let before = content.tracks
        var reordered = before
        let song = reordered.remove(at: from)
        let insertion = target.map { $0 > from ? $0 - 1 : $0 } ?? reordered.count
        reordered.insert(song, at: insertion)
        guard reordered != before else { return }
        let captured = generation
        update { $0.tracks = reordered }
        Task { [weak self, loader] in
            guard let self else { return }
            do {
                _ = try await loader.edit(browseId, [.move(setVideoId: moving, before: beforeKey)], credentials)
                guard generation == captured else { return }
                toasts.show("Moved in playlist", undo: { [weak self] in
                    self?.send([.move(setVideoId: moving, before: successor)], failure: "Couldn't undo")
                    self?.update { $0.tracks = before }
                })
            } catch {
                guard generation == captured else { return }
                update { $0.tracks = before }
                toasts.show("Couldn't update the playlist")
            }
        }
    }

    private func send(_ edits: [PlaylistEdit], failure: LocalizedStringResource) {
        guard !edits.isEmpty, case .playlist(let browseId) = kind, let credentials = credentials() else { return }
        let captured = generation
        Task { [weak self, loader] in
            guard let self else { return }
            do {
                _ = try await loader.edit(browseId, edits, credentials)
                guard generation == captured else { return }
                retry()
            } catch {
                guard generation == captured else { return }
                toasts.show(failure)
            }
        }
    }

    /// Every track id for Like all: an album has them all, a playlist is paged to the end first.
    func allTrackIds() async -> [String] {
        guard !isRetired else { return [] }
        let captured = generation
        let credentials = credentials()
        while let token = continuation {
            guard let page = try? await loader.moreTracks(token, credentials), generation == captured, !Task.isCancelled else { break }
            append(page, requestedWith: token)
        }
        guard !isRetired, generation == captured, case .loaded(let content) = state else { return [] }
        var ids: [String]
        if case .album(let album) = content.entity { ids = album.tracks.map(\.song.videoId) } else { ids = content.tracks.map(\.videoId) }
        var seenIds = Set<String>()
        ids = ids.filter { seenIds.insert($0).inserted }
        return ids
    }

    // MARK: Derived

    private var page: Entity? {
        if case .loaded(let content) = state { content.entity } else { nil }
    }

    private var saveId: String? {
        switch page {
        case .album(let album): album.audioPlaylistId
        case .playlist: canSave ? playlistId : nil
        default: nil
        }
    }

    private func libraryChange(saved: Bool) -> LibraryChange? {
        switch (kind, page) {
        case (.album, _): return .album
        case (.playlist(let browseId), .playlist(let playlist)?):
            return .playlist(Playlist(browseId: browseId, title: playlist.header.title, thumbnailURL: playlist.header.thumbnailURL), saved: saved)
        default: return nil
        }
    }

    private var playlistId: String? {
        if case .playlist(let browseId) = kind { browseId.hasPrefix("VL") ? String(browseId.dropFirst(2)) : browseId } else { nil }
    }

    /// Not for Liked music or an own playlist; an album needs its audio playlist.
    var canSave: Bool {
        switch page {
        case .album(let album): album.audioPlaylistId != nil
        case .playlist(let playlist): kind != .playlist(browseId: Route.likedMusicBrowseId) && !playlist.isOwned
        default: false
        }
    }

    var canAddSuggestions: Bool {
        if case .playlist(let playlist) = page { playlist.isOwned } else { false }
    }

    var playTarget: WatchTarget? {
        switch page {
        case .album(let album): album.header.play
        case .playlist(let playlist): playlist.header.play ?? playlistId.map { WatchTarget(playlistId: $0) }
        default: nil
        }
    }

    var shuffleTarget: WatchTarget? {
        switch page {
        case .album(let album): album.header.shuffle ?? playTarget
        case .playlist(let playlist): playlist.header.shuffle ?? playTarget
        case .artist(let artist): artist.shuffle
        case nil: nil
        }
    }

    /// Nil when the page has no public URL (Liked music, an album without an audio playlist).
    var shareURL: URL? {
        var components = URLComponents(string: "https://music.youtube.com")
        switch kind {
        case .artist(let browseId):
            components?.path = "/channel/" + browseId
        case .album:
            guard case .album(let album) = page, let id = album.audioPlaylistId else { return nil }
            components?.path = "/playlist"
            components?.queryItems = [URLQueryItem(name: "list", value: id)]
        case .playlist(let browseId):
            return PlaylistLink.shareURL(browseId: browseId)
        }
        return components?.url
    }

    // MARK: Loading

    private func fetch() async throws -> Content {
        let credentials = credentials()
        switch kind {
        case .album(let target):
            let album = try await loader.album(target, credentials)
            return Content(entity: .album(album), tracks: [], paging: .done, sections: [], isSaved: album.header.isSaved, isSubscribed: nil)
        case .artist(let browseId):
            let artist = try await loader.artist(browseId, credentials)
            return Content(entity: .artist(artist), tracks: [], paging: .done, sections: [], isSaved: false, isSubscribed: artist.isSubscribed)
        case .playlist(let browseId):
            let playlist = try await loader.playlist(browseId, credentials)
            return Content(
                entity: .playlist(playlist), tracks: playlist.tracks.items, paging: playlist.tracks.continuation == nil ? .done : .idle,
                sections: [],
                isSaved: playlist.header.isSaved, isSubscribed: nil)
        }
    }

    private func prime(_ content: Content) {
        if case .playlist(let playlist) = content.entity {
            continuation = playlist.tracks.continuation
            sectionsToken = playlist.sectionsContinuation
            seen = Set(content.tracks.map(\.rowKey))
        } else {
            continuation = nil
            sectionsToken = nil
        }
    }

    // The `seen` set also catches the guest continuation that silently returns page 1 again.

    private func append(_ page: Page<Song>, requestedWith token: String) {
        var fresh: [Song] = []
        for song in page.items where seen.insert(song.rowKey).inserted { fresh.append(song) }
        let finished = fresh.isEmpty || page.continuation == nil || page.continuation == token
        continuation = finished ? nil : page.continuation
        update {
            $0.tracks += fresh
            $0.paging = finished ? .done : .idle
        }
    }

    private func update(_ change: (inout Content) -> Void) {
        guard case .loaded(var content) = state else { return }
        change(&content)
        state = .loaded(content)
    }
}

private extension [Shelf] {
    func removing(videoId: String) -> [Shelf] {
        map { shelf in
            Shelf(
                title: shelf.title, strapline: shelf.strapline, more: shelf.more, layout: shelf.layout,
                items: shelf.items.filter { if case .song(let song) = $0 { song.videoId != videoId } else { true } })
        }
    }
}

enum PlaylistLink {
    /// Nil for Liked music, which has no public URL.
    static func shareURL(browseId: String) -> URL? {
        guard browseId != Route.likedMusicBrowseId else { return nil }
        let id = browseId.hasPrefix("VL") ? String(browseId.dropFirst(2)) : browseId
        var components = URLComponents(string: "https://music.youtube.com")
        components?.path = "/playlist"
        components?.queryItems = [URLQueryItem(name: "list", value: id)]
        return components?.url
    }
}
