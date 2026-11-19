extension Array where Element == HistoryDay {
    /// One day per shelf, in server order. A guest gets a sign-in message and so no days.
    init(history json: JSONValue) throws(InnerTubeError) {
        guard let list = json.sectionList else { throw .unexpectedResponse }
        self = list["contents"]?.array?.compactMap { block in
            guard let shelf = block["musicShelfRenderer"] else {
                if block["itemSectionRenderer"] == nil { parserLog.notice("Skipped block \(blockKey(block), privacy: .public)") }
                return nil
            }
            let entries = parseBlocks(shelf["contents"]?.array ?? []) { row in
                ItemParser.song(row).map { HistoryEntry(song: $0, feedbackToken: Self.removalToken(row)) }
            }
            return entries.isEmpty ? nil : HistoryDay(title: shelf["title"].flatMap(text) ?? "", entries: entries)
        } ?? []
    }

    // Found by icon, never by the localized label.
    private static func removalToken(_ row: JSONValue) -> String? {
        row["musicResponsiveListItemRenderer"]?["menu"]?["menuRenderer"]?["items"]?.array?.lazy.compactMap { item -> String? in
            guard let service = item["menuServiceItemRenderer"], service["icon"]?["iconType"]?.string == "REMOVE_FROM_HISTORY" else { return nil }
            return service["serviceEndpoint"]?["feedbackEndpoint"]?["feedbackToken"]?.string
        }.first
    }
}
