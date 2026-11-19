extension AlbumPage {
    init(album json: JSONValue) throws(InnerTubeError) {
        guard json["contents"] != nil else { throw .notAvailable }
        guard let renderer = json.twoColumnHeader, let header = PageHeader(responsive: renderer) else { throw .unexpectedResponse }
        let subtitleParts = (renderer["subtitle"]?["runs"]?.array ?? []).compactMap { $0["text"]?.string }
        let sections = json.twoColumnSections?["contents"]?.array ?? []
        let rows = sections.lazy.compactMap { $0["musicShelfRenderer"]?["contents"]?.array }.first ?? []
        self.init(
            header: header,
            type: subtitleParts.first,
            year: subtitleParts.first { $0.wholeMatch(of: /\d{4}/) != nil },
            audioPlaylistId: header.play?.playlistId,
            tracks: parseBlocks(rows) { row in
                ItemParser.song(row).map {
                    AlbumTrack(number: row["musicResponsiveListItemRenderer"]?["index"].flatMap(text).flatMap(Int.init), song: $0)
                }
            },
            shelves: parseBlocks(sections.filter { $0["musicShelfRenderer"] == nil }, ItemParser.section))
    }
}
