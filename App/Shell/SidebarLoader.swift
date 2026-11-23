import InnerTube

struct SidebarLoader: Sendable {
    var playlists: @Sendable (Credentials?) async throws -> [Playlist]
    /// Returns the bare playlist id.
    var create: @Sendable (NewPlaylistDraft, Credentials?) async throws -> String
    var delete: @Sendable (String, Credentials?) async throws -> Void
    var removeFromLibrary: @Sendable (String, Credentials?) async throws -> Void
    var isOwned: @Sendable (String, Credentials?) async throws -> Bool

    static func live(_ client: InnerTubeClient) -> SidebarLoader {
        SidebarLoader(
            playlists: { credentials in try await client.sidebarPlaylists(credentials: credentials) },
            create: { draft, credentials in
                try await client.createPlaylist(
                    title: draft.title, description: draft.description, privacy: draft.privacy, credentials: credentials)
            },
            delete: { id, credentials in try await client.deletePlaylist(id, credentials: credentials) },
            removeFromLibrary: { id, credentials in try await client.rate(playlistId: id, .indifferent, credentials: credentials) },
            isOwned: { id, credentials in try await client.playlist(BrowseTarget(browseId: id), credentials: credentials).isOwned })
    }
}
