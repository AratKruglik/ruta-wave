import Foundation

extension JSONValue {
    // An own playlist wraps the header in `musicEditablePlaylistDetailHeaderRenderer`.
    var twoColumnFirstItem: JSONValue? {
        self["contents"]?["twoColumnBrowseResultsRenderer"]?["tabs"]?[0]?["tabRenderer"]?["content"]?["sectionListRenderer"]?["contents"]?[0]
    }

    var twoColumnHeader: JSONValue? {
        let first = twoColumnFirstItem
        return first?["musicResponsiveHeaderRenderer"]
            ?? first?["musicEditablePlaylistDetailHeaderRenderer"]?["header"]?["musicResponsiveHeaderRenderer"]
    }

    var twoColumnSections: JSONValue? {
        self["contents"]?["twoColumnBrowseResultsRenderer"]?["secondaryContents"]?["sectionListRenderer"]
    }
}

extension PageHeader {
    init?(responsive header: JSONValue) {
        guard let title = header["title"].flatMap(text) else { return nil }
        let buttons = header["buttons"]?.array ?? []
        let menu = buttons.flatMap { $0["menuRenderer"]?["items"]?.array ?? [] }.compactMap { $0["menuNavigationItemRenderer"] }
        func menuTarget(_ icon: String) -> WatchTarget? {
            menu.first { $0["icon"]?["iconType"]?.string == icon }?["navigationEndpoint"].flatMap(ItemParser.watchTarget)
        }
        var artists = ItemParser.refs(header["straplineTextOne"]?["runs"]?.array ?? []).artists
        if artists.isEmpty, let owner = header["facepile"]?["avatarStackViewModel"], let name = owner["text"]?["content"]?.string {
            let link = owner["rendererContext"]?["commandContext"]?["onTap"]?["innertubeCommand"]?["browseEndpoint"]?["browseId"]?.string
            artists = [ItemRef(name: name, browseId: link)]
        }
        let thumbnail = ItemParser.thumbnail(header["thumbnail"])
        self.init(
            title: title,
            subtitle: header["subtitle"].flatMap(text),
            secondSubtitle: header["secondSubtitle"].flatMap(text),
            description: header["description"]?["musicDescriptionShelfRenderer"]?["description"].flatMap(text),
            thumbnailURL: thumbnail.flatMap(lastThumbnailURL),
            artists: artists,
            play: buttons.lazy.compactMap {
                $0["musicPlayButtonRenderer"]?["playNavigationEndpoint"].flatMap(ItemParser.watchTarget)
            }.first,
            shuffle: menuTarget("MUSIC_SHUFFLE"),
            radio: menuTarget("MIX"),
            isExplicit: ItemParser.isExplicit(header),
            isSaved: buttons.contains {
                $0["toggleButtonRenderer"]?["defaultIcon"]?["iconType"]?.string == "BOOKMARK_BORDER"
                    && $0["toggleButtonRenderer"]?["isToggled"]?.bool == true
            })
    }
}
