import InnerTube

struct LibraryLoader: Sendable {
    var page: @Sendable (BrowseTarget, Credentials?) async throws -> LibraryPage
    var more: @Sendable (String, Credentials?) async throws -> Page<MusicItem>
    var history: @Sendable (Credentials?) async throws -> [HistoryDay]
    /// Removes one history entry by its feedback token.
    var feedback: @Sendable (String, Credentials?) async throws -> Void

    static func live(_ client: InnerTubeClient) -> LibraryLoader {
        LibraryLoader(
            page: { target, credentials in try await client.library(target, credentials: credentials) },
            more: { token, credentials in try await client.libraryContinuation(token, credentials: credentials) },
            history: { credentials in try await client.history(credentials: credentials) },
            feedback: { token, credentials in try await client.sendFeedback([token], credentials: credentials) })
    }
}
