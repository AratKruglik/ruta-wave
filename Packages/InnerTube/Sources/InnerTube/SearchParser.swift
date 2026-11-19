extension SearchResults {
    // protobuf filter field 9/10/11 = episodes, podcasts, profiles; out of scope (#7)
    private static let hiddenFilterPrefixes = ["EgWKAQJI", "EgWKAQJQ", "EgWKAQJY"]

    init(search json: JSONValue) throws(InnerTubeError) {
        if let paged = json["continuationContents"]?["musicShelfContinuation"] {
            self.init(
                chips: [], topResult: nil,
                items: Page(items: parseBlocks(paged["contents"]?.array ?? [], ItemParser.item), continuation: paged.nextContinuation),
                correction: nil)
            return
        }
        guard let list = json["contents"]?["tabbedSearchResultsRenderer"]?["tabs"]?[0]?["tabRenderer"]?["content"]?["sectionListRenderer"]
        else { throw .unexpectedResponse }
        let sections = list["contents"]?.array ?? []
        var blocks: [JSONValue] = []
        var topResult: MusicItem?
        var continuation: String?
        for section in sections {
            if let card = section["musicCardShelfRenderer"] {
                topResult = topResult ?? ItemParser.card(card)
            } else if let inner = section["itemSectionRenderer"]?["contents"]?.array {
                blocks += inner
            } else if let shelf = section["musicShelfRenderer"] {
                blocks += shelf["contents"]?.array ?? []
                continuation = continuation ?? shelf.nextContinuation
            } else {
                parserLog.notice("Skipped block \(blockKey(section), privacy: .public)")
            }
        }
        let corrections = blocks.compactMap(Self.correction)
        self.init(
            chips: ItemParser.chips(list["header"]?["chipCloudRenderer"]).filter { $0.searchParams.map { params in !Self.hiddenFilterPrefixes.contains(where: params.hasPrefix) } ?? false },
            topResult: topResult,
            items: Page(
                items: parseBlocks(blocks.filter { Self.correction($0) == nil }, ItemParser.item),
                continuation: continuation),
            correction: corrections.first)
    }

    private static func correction(_ block: JSONValue) -> SearchCorrection? {
        guard let renderer = block["showingResultsForRenderer"] ?? block["didYouMeanRenderer"],
              let corrected = renderer["correctedQueryEndpoint"]?["searchEndpoint"]?["query"]?.string,
              let original = renderer["originalQueryEndpoint"]?["searchEndpoint"]
        else { return nil }
        guard let originalQuery = original["query"]?.string else { return nil }
        return SearchCorrection(correctedQuery: corrected, originalQuery: originalQuery, originalParams: original["params"]?.string)
    }
}
