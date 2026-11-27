import InnerTube

extension Song {
    static let placeholder = Song(
        videoId: "placeholder", title: "Placeholder song title", artists: [ItemRef(name: "Placeholder artist", browseId: nil)],
        album: ItemRef(name: "Placeholder album", browseId: nil), duration: "0:00")
}

extension MusicItem {
    static let placeholder = MusicItem.album(
        Album(browseId: "placeholder", title: "Placeholder album title", subtitle: "Album • Placeholder artist"))
}

extension Shelf {
    static func placeholder(layout: Layout, count: Int = 6) -> Shelf {
        Shelf(title: "Placeholder shelf title", layout: layout, items: Array(repeating: .placeholder, count: count))
    }

    static func placeholderLinks(_ targets: [BrowseTarget], title: String? = nil) -> Shelf {
        Shelf(
            title: title, layout: .grid,
            items: targets.map { .link(NavigationLink(title: "Placeholder", target: $0)) })
    }
}
