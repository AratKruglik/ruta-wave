import InnerTube

extension Song {
    static let placeholder = Song(
        videoId: "placeholder", title: "Placeholder song title", artists: [ItemRef(name: "Placeholder artist", browseId: nil)],
        album: ItemRef(name: "Placeholder album", browseId: nil), duration: "0:00")
}

extension Song {
    static let rankedPlaceholder = Song(
        videoId: "placeholder", title: "Placeholder song title", artists: [ItemRef(name: "Placeholder artist", browseId: nil)],
        album: ItemRef(name: "Placeholder album", browseId: nil), duration: "0:00", rank: ChartRank(position: 1, trend: .neutral))
}

extension Artist {
    static let placeholder = Artist(browseId: "placeholder", name: "Placeholder artist", subtitle: "Placeholder subscribers")
}

extension PageHeader {
    static let placeholder = PageHeader(
        title: "Placeholder album title", subtitle: "Album • Placeholder", secondSubtitle: "12 songs • 45 minutes",
        artists: [ItemRef(name: "Placeholder artist", browseId: nil)], play: WatchTarget(playlistId: "placeholder"),
        shuffle: WatchTarget(playlistId: "placeholder"))
}

extension ArtistPage {
    static let placeholder = ArtistPage(
        name: "Placeholder artist", thumbnailURL: nil, subscriberCountText: "Placeholder", isSubscribed: nil, channelId: nil,
        shuffle: WatchTarget(playlistId: "placeholder"), radio: WatchTarget(playlistId: "placeholder"), shelves: [],
        description: nil, viewCountText: nil)
}

extension MusicItem {
    static let placeholder = MusicItem.album(
        Album(browseId: "placeholder", title: "Placeholder album title", subtitle: "Album • Placeholder artist"))
}

extension Shelf {
    static func placeholder(layout: Layout, count: Int = 6, ranked: Bool = false) -> Shelf {
        let item: MusicItem =
            switch layout {
            case .rows, .list: .song(ranked ? .rankedPlaceholder : .placeholder)
            case .cards, .grid: .placeholder
            }
        return Shelf(title: "Placeholder shelf title", layout: layout, items: Array(repeating: item, count: count))
    }

    static func placeholderLinks(_ targets: [BrowseTarget], title: String? = nil) -> Shelf {
        Shelf(
            title: title, layout: .grid,
            items: targets.map { .link(NavigationLink(title: "Placeholder", target: $0)) })
    }
}
