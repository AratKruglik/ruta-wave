import InnerTube

struct SearchLoader: Sendable {
    var suggestions: @Sendable (String, Credentials?) async throws -> SearchSuggestions
    var search: @Sendable (String, String?, Credentials?) async throws -> SearchResults
    var more: @Sendable (String, Credentials?) async throws -> Page<MusicItem>
    /// One token per call, so a partial failure cannot leave an ambiguous batch.
    var feedback: @Sendable (String, Credentials?) async throws -> Void
    /// The channel id, never the card's browse id, then subscribe or unsubscribe.
    var subscribe: @Sendable (String, Bool, Credentials?) async throws -> Void

    static func live(_ client: InnerTubeClient) -> SearchLoader {
        SearchLoader(
            suggestions: { input, credentials in try await client.searchSuggestions(input, credentials: credentials) },
            search: { query, params, credentials in try await client.search(query, params: params, credentials: credentials) },
            more: { token, credentials in try await client.searchContinuation(token, credentials: credentials) },
            feedback: { token, credentials in try await client.sendFeedback([token], credentials: credentials) },
            subscribe: { id, subscribed, credentials in try await client.setSubscribed(subscribed, channelId: id, credentials: credentials) })
    }
}
