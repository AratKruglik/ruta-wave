import InnerTube

struct LibraryLoader: Sendable {
    var page: @Sendable (BrowseTarget, Credentials?) async throws -> LibraryPage
    /// The section in another server order, by the `LibrarySort.continuation` token.
    var reload: @Sendable (String, Credentials?) async throws -> LibraryPage
    var more: @Sendable (String, Credentials?) async throws -> Page<MusicItem>
    var history: @Sendable (Credentials?) async throws -> [HistoryDay]
    /// Removes one history entry by its feedback token.
    var feedback: @Sendable (String, Credentials?) async throws -> Void

    static func live(_ client: InnerTubeClient) -> LibraryLoader {
        LibraryLoader(
            page: { target, credentials in try await client.library(target, credentials: credentials) },
            reload: { token, credentials in try await client.libraryReload(token, credentials: credentials) },
            more: { token, credentials in try await client.libraryContinuation(token, credentials: credentials) },
            history: { credentials in try await client.history(credentials: credentials) },
            feedback: { token, credentials in try await client.sendFeedback([token], credentials: credentials) })
    }
}
