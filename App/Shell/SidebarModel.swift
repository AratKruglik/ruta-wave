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

    private(set) var state: State = .loading
    @ObservationIgnored private let client: InnerTubeClient?

    init(client: InnerTubeClient? = InnerTubeClient()) {
        self.client = client
    }

    func load(credentials: Credentials?) async {
        guard let credentials else {
            state = .loaded([])
            return
        }
        guard let client else { return }
        state = .loading
        do {
            let playlists = try await client.sidebarPlaylists(credentials: credentials)
            guard !Task.isCancelled else { return }
            state = .loaded(Self.pinningLikedMusic(playlists))
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed
        }
    }

    static func pinningLikedMusic(_ playlists: [Playlist]) -> [Playlist] {
        let liked = playlists.first { $0.browseId == Route.likedMusicBrowseId }
            ?? Playlist(browseId: Route.likedMusicBrowseId, title: String(localized: "Liked music"))
        return [liked] + playlists.filter { $0.browseId != Route.likedMusicBrowseId }
    }
}
