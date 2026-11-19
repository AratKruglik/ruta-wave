extension PlaylistPage {
    // Both the two-column page (album-like header) and the single-column page (artist Top songs, Videos) are playlists.
    init(playlist json: JSONValue) throws(InnerTubeError) {
        guard json["contents"] != nil else { throw .notAvailable }
        let header: PageHeader
        let blocks: [JSONValue]
        var sectionsContinuation: String?
        if let renderer = json.twoColumnHeader {
            guard let parsed = PageHeader(responsive: renderer) else { throw .unexpectedResponse }
            header = parsed
            blocks = json.twoColumnSections?["contents"]?.array ?? []
            sectionsContinuation = json.twoColumnSections?.nextContinuation
        } else if let title = json["header"]?["musicHeaderRenderer"]?["title"].flatMap(text) {
            header = PageHeader(title: title)
            blocks = json.sectionList?["contents"]?.array ?? []
        } else {
            throw .unexpectedResponse
        }
        let shelf = blocks.lazy.compactMap { $0["musicPlaylistShelfRenderer"] }.first
        self.init(
            header: header,
            tracks: Page(items: parseBlocks(shelf?["contents"]?.array ?? [], ItemParser.song), continuation: shelf?.nextContinuation),
            sectionsContinuation: sectionsContinuation)
    }
}

extension Page where Item == Song {
    init(playlistContinuation json: JSONValue) throws(InnerTubeError) {
        guard let rows = json["onResponseReceivedActions"]?.array?.lazy.compactMap({
            $0["appendContinuationItemsAction"]?["continuationItems"]?.array
        }).first else { throw .unexpectedResponse }
        self.init(items: parseBlocks(rows, ItemParser.song), continuation: JSONValue.array(rows).nextContinuation)
    }
}
