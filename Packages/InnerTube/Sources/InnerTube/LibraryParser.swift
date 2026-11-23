extension LibraryPage {
    // Podcasts and uploads are out of scope (#7); profiles are user channels, which have no page here.
    private static func isHiddenSection(_ browseId: String) -> Bool {
        ["FEmusic_library_non_music_audio_list", "FEmusic_library_user_profile_channels_list"].contains(browseId)
            || browseId.hasPrefix("FEmusic_library_privately_owned_")
    }

    private struct Container {
        let node: JSONValue
        let rows: [JSONValue]
    }

    // The grid or shelf sits in an `itemSectionRenderer`, or directly in the section list.
    private static func container(_ blocks: [JSONValue]) -> Container? {
        for block in blocks {
            let inner = block["itemSectionRenderer"]?["contents"]?[0] ?? block
            if let grid = inner["gridRenderer"] { return Container(node: grid, rows: grid["items"]?.array ?? []) }
            if let shelf = inner["musicShelfRenderer"] { return Container(node: shelf, rows: shelf["contents"]?.array ?? []) }
        }
        return nil
    }

    init(library json: JSONValue) throws(InnerTubeError) {
        guard let list = json.sectionList else { throw .unexpectedResponse }
        let container = Self.container(list["contents"]?.array ?? [])
        let header = list["header"]?["musicSideAlignedItemRenderer"]
        self.init(
            sections: (header?["startItems"]?.array ?? []).flatMap { Self.chips($0["chipCloudRenderer"]) },
            sortOptions: (header?["endItems"]?.array ?? []).flatMap { Self.sorts($0["musicSortFilterButtonRenderer"]) },
            items: Page(items: parseBlocks(container?.rows ?? [], ItemParser.item), continuation: container?.node.nextContinuation))
    }

    // A chip runs a `commandExecutorCommand` whose first `browseEndpoint` is the section. The icon-only chip (back to the landing page) has no title.
    private static func chips(_ chipCloud: JSONValue?) -> [Chip] {
        (chipCloud?["chips"]?.array ?? []).compactMap { block in
            guard let chip = block["chipCloudChipRenderer"], let title = chip["text"].flatMap(text) else { return nil }
            let endpoint = chip["navigationEndpoint"]
            let commands = endpoint?["commandExecutorCommand"]?["commands"]?.array ?? endpoint.map { [$0] } ?? []
            guard let target = commands.lazy.compactMap({ $0["browseEndpoint"].flatMap(ItemParser.browseTarget) }).first,
                  !isHiddenSection(target.browseId)
            else { return nil }
            return Chip(title: title, target: target, isSelected: chip["isSelected"]?.bool ?? false)
        }
    }

    // Every option carries a check icon, so the button title is what names the current order.
    private static func sorts(_ button: JSONValue?) -> [LibrarySort] {
        guard let button else { return [] }
        let current = button["title"].flatMap(text)
        return (button["menu"]?["musicMultiSelectMenuRenderer"]?["options"]?.array ?? []).compactMap { option in
            guard let item = option["musicMultiSelectMenuItemRenderer"], let title = item["title"].flatMap(text),
                  let token = (item["selectedCommand"]?["commandExecutorCommand"]?["commands"]?.array ?? []).lazy.compactMap({
                      $0["browseSectionListReloadEndpoint"]?["continuation"]?["reloadContinuationData"]?["continuation"]?.string
                  }).first
            else { return nil }
            return LibrarySort(title: title, continuation: token, isSelected: title == current)
        }
    }
}

extension Page where Item == MusicItem {
    init(libraryContinuation json: JSONValue) throws(InnerTubeError) {
        let continuation = json["continuationContents"]
        if let grid = continuation?["gridContinuation"] {
            self.init(items: parseBlocks(grid["items"]?.array ?? [], ItemParser.item), continuation: grid.nextContinuation)
        } else if let shelf = continuation?["musicShelfContinuation"] {
            self.init(items: parseBlocks(shelf["contents"]?.array ?? [], ItemParser.item), continuation: shelf.nextContinuation)
        } else {
            throw .unexpectedResponse
        }
    }
}

extension Array where Element == Playlist {
    /// The sidebar playlists of `guide`, in server order. Empty for a guest.
    init(guide json: JSONValue) {
        self = Self.entries(json).compactMap { entry in
            guard let browseId = entry["navigationEndpoint"]?["browseEndpoint"]?["browseId"]?.string, browseId.hasPrefix("VL"),
                  let title = entry["formattedTitle"].flatMap(text)
            else { return nil }
            return Playlist(browseId: browseId, title: title, thumbnailURL: entry["thumbnail"].flatMap(lastThumbnailURL))
        }
    }

    // Playlist entries may sit in nested or collapsible sections (`headerEntry`, `sectionItems`). Sorted keys keep the order stable.
    private static func entries(_ node: JSONValue) -> [JSONValue] {
        switch node {
        case .object(let object):
            return object.keys.sorted().flatMap { key in key == "guideEntryRenderer" ? [object[key]!] : entries(object[key]!) }
        case .array(let items):
            return items.flatMap(entries)
        default:
            return []
        }
    }
}
