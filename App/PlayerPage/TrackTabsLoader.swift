import InnerTube

struct TrackTabsLoader: Sendable {
    /// `nil` is "Lyrics not available".
    var lyrics: @Sendable (String, Credentials?) async throws -> Lyrics?
    /// `nil` is "no timed lines". Guest only: the mobile request carries no credentials.
    var timedLyrics: @Sendable (String) async throws -> TimedLyrics?
    var related: @Sendable (String, Credentials?) async throws -> BrowsePage

    static func live(_ client: InnerTubeClient) -> TrackTabsLoader {
        TrackTabsLoader(
            lyrics: { id, credentials in try await client.lyrics(id, credentials: credentials) },
            timedLyrics: { id in try await client.timedLyrics(id) },
            related: { id, credentials in try await client.browse(BrowseTarget(browseId: id), credentials: credentials) })
    }
}
