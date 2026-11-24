import InnerTube

struct SidebarLoader: Sendable {
    var playlists: @Sendable (Credentials?) async throws -> [Playlist]
    /// Returns the bare playlist id.
    var create: @Sendable (NewPlaylistDraft, Credentials?) async throws -> String
    /// One request for all edits; the result lists the rows an `.add` created.
    var edit: @Sendable (String, [PlaylistEdit], Credentials?) async throws -> [AddedPlaylistRow]
    var delete: @Sendable (String, Credentials?) async throws -> Void
    var removeFromLibrary: @Sendable (String, Credentials?) async throws -> Void
    var isOwned: @Sendable (String, Credentials?) async throws -> Bool

    static func live(_ client: InnerTubeClient) -> SidebarLoader {
        SidebarLoader(
            playlists: { credentials in try await client.sidebarPlaylists(credentials: credentials) },
            create: { draft, credentials in
                try await client.createPlaylist(
                    title: draft.title, description: draft.description, privacy: draft.privacy, videoIds: draft.videoIds,
                    credentials: credentials)
            },
            edit: { id, edits, credentials in try await client.editPlaylist(id, edits, credentials: credentials) },
            delete: { id, credentials in try await client.deletePlaylist(id, credentials: credentials) },
            removeFromLibrary: { id, credentials in try await client.rate(playlistId: id, .indifferent, credentials: credentials) },
            isOwned: { id, credentials in try await client.playlist(BrowseTarget(browseId: id), credentials: credentials).isOwned })
    }
}
