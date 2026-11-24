import InnerTube

struct TrackTabsLoader: Sendable {
    /// `nil` is "Lyrics not available".
    var lyrics: @Sendable (String, Credentials?) async throws -> Lyrics?
    var related: @Sendable (String, Credentials?) async throws -> BrowsePage

    static func live(_ client: InnerTubeClient) -> TrackTabsLoader {
        TrackTabsLoader(
            lyrics: { id, credentials in try await client.lyrics(id, credentials: credentials) },
            related: { id, credentials in try await client.browse(BrowseTarget(browseId: id), credentials: credentials) })
    }
}
