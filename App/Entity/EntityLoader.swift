import InnerTube

struct EntityLoader: Sendable {
    var album: @Sendable (BrowseTarget, Credentials?) async throws -> AlbumPage
    var artist: @Sendable (String, Credentials?) async throws -> ArtistPage
    var playlist: @Sendable (String, Credentials?) async throws -> PlaylistPage
    var moreTracks: @Sendable (String, Credentials?) async throws -> Page<Song>
    var sections: @Sendable (String, Credentials?) async throws -> Page<Shelf>
    /// Playlist id (an album passes its `audioPlaylistId`), then save or remove.
    var save: @Sendable (String, Bool, Credentials?) async throws -> Void
    /// The channel id, never the page's browse id, then subscribe or unsubscribe.
    var subscribe: @Sendable (String, Bool, Credentials?) async throws -> Void
    /// Playlist id, then the video to append.
    var add: @Sendable (String, String, Credentials?) async throws -> Void

    static func live(_ client: InnerTubeClient) -> EntityLoader {
        EntityLoader(
            album: { target, credentials in try await client.album(target, credentials: credentials) },
            artist: { id, credentials in try await client.artist(BrowseTarget(browseId: id), credentials: credentials) },
            playlist: { id, credentials in try await client.playlist(BrowseTarget(browseId: id), credentials: credentials) },
            moreTracks: { token, credentials in try await client.playlistContinuation(token, credentials: credentials) },
            sections: { token, credentials in try await client.browseContinuation(token, credentials: credentials) },
            save: { id, saved, credentials in
                try await client.rate(playlistId: id, saved ? .like : .indifferent, credentials: credentials)
            },
            subscribe: { id, subscribed, credentials in
                try await client.setSubscribed(subscribed, channelId: id, credentials: credentials)
            },
            add: { id, videoId, credentials in
                try await client.editPlaylist(id, [.add(videoId: videoId)], credentials: credentials)
            })
    }
}
