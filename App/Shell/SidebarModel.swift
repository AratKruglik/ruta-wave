import Foundation
import InnerTube
import Observation

@MainActor @Observable
final class SidebarModel {
    enum State {
        case loading
        case loaded([Playlist])
        case failed
    }

    enum CreateResult: Equatable {
        case created(String)
        /// The request timed out and may have gone through; it is never resent.
        case mayExist
        case failed
        /// The account changed while the request was in flight.
        case discarded
    }

    private(set) var state: State = .loading
    private(set) var ownership: [String: Bool] = [:]

    @ObservationIgnored private let loader: SidebarLoader
    @ObservationIgnored private let credentials: @MainActor () -> Credentials?
    @ObservationIgnored private let toasts: ToastCenter
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var serverList: [Playlist] = []
    /// Newest first. Kept until the server list contains the id, so a lagging `guide` cannot drop a row that was just added.
    @ObservationIgnored private var pendingInserts: [Playlist] = []
    @ObservationIgnored private var pendingRemovals: Set<String> = []
    @ObservationIgnored private var resolving: Set<String> = []

    init(loader: SidebarLoader, credentials: @escaping @MainActor () -> Credentials?, toasts: ToastCenter) {
        self.loader = loader
        self.credentials = credentials
        self.toasts = toasts
    }

    func load() async {
        let captured = generation
        guard let credentials = credentials() else {
            serverList = []
            state = .loaded([])
            return
        }
        if case .loaded = state {} else { state = .loading }
        do {
            let list = try await loader.playlists(credentials)
            guard !Task.isCancelled, generation == captured else { return }
            serverList = list
            let ids = Set(list.map(\.browseId))
            pendingInserts.removeAll { ids.contains($0.browseId) }
            pendingRemovals.formIntersection(ids)
            publish()
        } catch {
            guard !Task.isCancelled, generation == captured else { return }
            if case .loaded = state { return }
            state = .failed
        }
    }

    /// Called when the content identity changes: nothing of the old account survives.
    func reset() {
        generation += 1
        serverList = []
        pendingInserts = []
        pendingRemovals = []
        resolving = []
        ownership = [:]
        state = .loading
    }

    /// A playlist saved or unsaved from its page.
    func applyLibraryChange(_ playlist: Playlist, saved: Bool) {
        if saved {
            pendingRemovals.remove(playlist.browseId)
            pendingInserts.removeAll { $0.browseId == playlist.browseId }
            pendingInserts.insert(playlist, at: 0)
        } else {
            pendingInserts.removeAll { $0.browseId == playlist.browseId }
            pendingRemovals.insert(playlist.browseId)
        }
        publishIfLoaded()
    }

    func create(_ draft: NewPlaylistDraft) async -> CreateResult {
        guard let credentials = credentials() else { return .failed }
        let captured = generation
        do {
            let id = try await loader.create(draft, credentials)
            guard generation == captured else { return .discarded }
            let browseId = "VL" + id
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            ownership[browseId] = true
            pendingRemovals.remove(browseId)
            pendingInserts.insert(Playlist(browseId: browseId, title: title), at: 0)
            publishIfLoaded()
            return .created(browseId)
        } catch {
            guard generation == captured else { return .discarded }
            switch error {
            case InnerTubeError.network, InnerTubeError.unexpectedResponse: return .mayExist
            case InnerTubeError.httpStatus(let status) where status >= 500: return .mayExist
            default: return .failed
            }
        }
    }

    func delete(_ browseId: String) async -> Bool {
        await remove(browseId) { [loader] credentials in try await loader.delete(browseId, credentials) }
    }

    func removeFromLibrary(_ browseId: String) async -> Bool {
        await remove(browseId) { [loader] credentials in try await loader.removeFromLibrary(browseId, credentials) }
    }

    /// `nil` while unknown. Liked music has no ownership question; editorial, album and radio lists are never owned.
    func ownership(of browseId: String) -> Bool? {
        if browseId == Route.likedMusicBrowseId { return nil }
        if Self.neverOwnedPrefixes.contains(where: browseId.hasPrefix) { return false }
        return ownership[browseId]
    }

    func resolveOwnership(_ browseId: String) async {
        guard ownership(of: browseId) == nil, browseId != Route.likedMusicBrowseId, !resolving.contains(browseId),
              let credentials = credentials() else { return }
        let captured = generation
        resolving.insert(browseId)
        defer { if generation == captured { resolving.remove(browseId) } }
        guard let owned = try? await loader.isOwned(browseId, credentials), generation == captured else { return }
        ownership[browseId] = owned
    }

    static func pinningLikedMusic(_ playlists: [Playlist]) -> [Playlist] {
        let liked = playlists.first { $0.browseId == Route.likedMusicBrowseId }
            ?? Playlist(browseId: Route.likedMusicBrowseId, title: String(localized: "Liked music"))
        return [liked] + playlists.filter { $0.browseId != Route.likedMusicBrowseId }
    }

    private static let neverOwnedPrefixes = ["VLRDCLAK", "VLOLAK5uy", "VLRD"]

    private func remove(_ browseId: String, request: @Sendable (Credentials?) async throws -> Void) async -> Bool {
        guard let credentials = credentials() else { return false }
        let captured = generation
        let previous = pendingInserts.first { $0.browseId == browseId }
        pendingInserts.removeAll { $0.browseId == browseId }
        pendingRemovals.insert(browseId)
        publishIfLoaded()
        do {
            try await request(credentials)
            return generation == captured
        } catch {
            guard generation == captured else { return false }
            pendingRemovals.remove(browseId)
            if let previous { pendingInserts.insert(previous, at: 0) }
            publishIfLoaded()
            toasts.show("Couldn't update your library")
            return false
        }
    }

    private func publishIfLoaded() {
        if case .loaded = state { publish() }
    }

    private func publish() {
        let visible = serverList.filter { !pendingRemovals.contains($0.browseId) }
        let known = Set(visible.map(\.browseId))
        let inserts = pendingInserts.filter { !known.contains($0.browseId) }
        state = .loaded(Self.pinningLikedMusic(inserts + visible))
    }
}
