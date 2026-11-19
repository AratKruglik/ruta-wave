extension WatchNext {
    init(next json: JSONValue) throws(InnerTubeError) {
        let tabs = (json["contents"]?["singleColumnMusicWatchNextResultsRenderer"]?["tabbedRenderer"]?["watchNextTabbedResultsRenderer"]?["tabs"]?.array ?? [])
            .compactMap { $0["tabRenderer"] }
        guard let queue = tabs.first?["content"]?["musicQueueRenderer"], let panel = queue["content"]?["playlistPanelRenderer"] else {
            throw .unexpectedResponse
        }
        // Tabs are keyed on the page type, never on the localized title. A disabled tab keeps its endpoint and is `unselectable`.
        func browseId(_ pageType: String, selectableOnly: Bool = false) -> String? {
            let tab = tabs.first {
                $0["endpoint"]?["browseEndpoint"].flatMap(ItemParser.pageType) == pageType
                    && !(selectableOnly && $0["unselectable"]?.bool == true)
            }
            return tab?["endpoint"]?["browseEndpoint"]?["browseId"]?.string
        }
        let blocks = panel["contents"]?.array ?? []
        self.init(
            queue: Page(
                items: parseBlocks(blocks.filter { $0["automixPreviewVideoRenderer"] == nil }, Self.queueItem),
                continuation: panel.nextContinuation),
            automix: blocks.lazy.compactMap {
                $0["automixPreviewVideoRenderer"]?["content"]?["automixPlaylistVideoRenderer"]?["navigationEndpoint"].flatMap(ItemParser.watchTarget)
            }.first,
            chips: ItemParser.chips(queue["subHeaderChipCloud"]?["chipCloudRenderer"]),
            playingFrom: queue["header"]?["musicQueueHeaderRenderer"]?["subtitle"].flatMap(text),
            playlistId: panel["playlistId"]?.string,
            lyricsBrowseId: browseId("MUSIC_PAGE_TYPE_TRACK_LYRICS", selectableOnly: true),
            relatedBrowseId: browseId("MUSIC_PAGE_TYPE_TRACK_RELATED"))
    }

    fileprivate static func queueItem(_ block: JSONValue) -> QueueItem? {
        if let renderer = block["playlistPanelVideoRenderer"] {
            return ItemParser.queueItem(renderer).map { QueueItem(song: $0, isCurrent: renderer["selected"]?.bool ?? false, counterpart: nil) }
        }
        guard let wrapper = block["playlistPanelVideoWrapperRenderer"],
              let primary = wrapper["primaryRenderer"]?["playlistPanelVideoRenderer"],
              let song = ItemParser.queueItem(primary)
        else { return nil }
        return QueueItem(
            song: song, isCurrent: primary["selected"]?.bool ?? false,
            counterpart: wrapper["counterpart"]?[0]?["counterpartRenderer"]?["playlistPanelVideoRenderer"].flatMap(ItemParser.queueItem))
    }
}

extension Page where Item == QueueItem {
    init(nextContinuation json: JSONValue) throws(InnerTubeError) {
        guard let panel = json["continuationContents"]?["playlistPanelContinuation"] else { throw .unexpectedResponse }
        self.init(items: parseBlocks(panel["contents"]?.array ?? [], WatchNext.queueItem), continuation: panel.nextContinuation)
    }
}
