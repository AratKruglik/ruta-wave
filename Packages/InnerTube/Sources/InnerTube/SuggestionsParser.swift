extension SearchSuggestions {
    init(suggestions json: JSONValue) {
        var queries: [String] = []
        var items: [MusicItem] = []
        var history: [SearchHistoryEntry] = []
        let blocks = (json["contents"]?.array ?? []).flatMap { $0["searchSuggestionsSectionRenderer"]?["contents"]?.array ?? [] }
        _ = parseBlocks(blocks) { (block: JSONValue) -> Void? in
            if let renderer = block["searchSuggestionRenderer"] {
                guard let query = Self.query(renderer) else { return nil }
                queries.append(query)
            } else if let renderer = block["historySuggestionRenderer"] {
                guard let query = Self.query(renderer),
                      let token = renderer["serviceEndpoint"]?["feedbackEndpoint"]?["feedbackToken"]?.string, !token.isEmpty
                else { return nil }
                history.append(SearchHistoryEntry(query: query, feedbackToken: token))
            } else if let item = ItemParser.item(block) {
                items.append(item)
            } else {
                return nil
            }
            return ()
        }
        self.init(queries: queries, items: items, history: history)
    }

    private static func query(_ renderer: JSONValue) -> String? {
        let query = renderer["navigationEndpoint"]?["searchEndpoint"]?["query"]?.string ?? renderer["suggestion"].flatMap(text)
        return query.flatMap { $0.isEmpty ? nil : $0 }
    }
}
