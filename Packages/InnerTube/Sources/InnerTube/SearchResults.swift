/// "Showing results for X, search instead for Y". `originalParams` forces the original query.
public struct SearchCorrection: Sendable, Equatable {
    public let correctedQuery: String
    public let originalQuery: String
    public let originalParams: String?

    public init(correctedQuery: String, originalQuery: String, originalParams: String?) {
        self.correctedQuery = correctedQuery
        self.originalQuery = originalQuery
        self.originalParams = originalParams
    }
}

/// Unfiltered: a flat server-ordered list without a continuation. Filtered: one type, paged.
public struct SearchResults: Sendable, Equatable {
    public let chips: [Chip]
    public let topResult: MusicItem?
    public let items: Page<MusicItem>
    public let correction: SearchCorrection?

    public init(chips: [Chip], topResult: MusicItem?, items: Page<MusicItem>, correction: SearchCorrection?) {
        self.chips = chips
        self.topResult = topResult
        self.items = items
        self.correction = correction
    }
}

public struct SearchHistoryEntry: Sendable, Equatable {
    public let query: String
    public let feedbackToken: String

    public init(query: String, feedbackToken: String) {
        self.query = query
        self.feedbackToken = feedbackToken
    }
}

public struct SearchSuggestions: Sendable, Equatable {
    public let queries: [String]
    public let items: [MusicItem]
    public let history: [SearchHistoryEntry]

    public init(queries: [String] = [], items: [MusicItem] = [], history: [SearchHistoryEntry] = []) {
        self.queries = queries
        self.items = items
        self.history = history
    }
}
