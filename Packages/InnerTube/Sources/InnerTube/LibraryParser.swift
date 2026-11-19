extension LibraryPage {
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
        let blocks = list["contents"]?.array ?? []
        let container = Self.container(blocks)
        let sortEntries = blocks.lazy.compactMap {
            $0["itemSectionRenderer"]?["header"]?["itemSectionTabbedHeaderRenderer"]?["endItems"]?.array
        }.first?.flatMap { $0["dropdownRenderer"]?["entries"]?.array ?? [] } ?? []
        self.init(
            sections: ItemParser.chips(list["header"]?["chipCloudRenderer"]).filter { $0.target != nil },
            sortOptions: sortEntries.compactMap { entry in
                guard let item = entry["dropdownItemRenderer"], let title = item["label"].flatMap(text) ?? item["label"]?.string,
                      let target = item["onSelectCommand"]?["browseEndpoint"].flatMap(ItemParser.browseTarget)
                else { return nil }
                return Chip(title: title, target: target, isSelected: item["isSelected"]?.bool ?? false)
            },
            items: Page(items: parseBlocks(container?.rows ?? [], ItemParser.item), continuation: container?.node.nextContinuation))
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
