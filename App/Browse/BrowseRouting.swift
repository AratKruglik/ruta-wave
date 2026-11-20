import InnerTube

extension BrowseTarget {
    static let moodCategoryId = "FEmusic_moods_and_genres_category"

    static func moodCategory(params: String) -> BrowseTarget {
        BrowseTarget(browseId: moodCategoryId, params: params)
    }
}

extension Route {
    init(target: BrowseTarget) {
        let id = target.browseId
        if id == BrowseTarget.moodCategoryId, let params = target.params {
            self = .explore(.mood(params: params))
            return
        }
        switch id {
        case BrowseTarget.newReleases.browseId: self = .explore(.newReleases)
        case BrowseTarget.charts.browseId: self = .explore(.charts)
        case BrowseTarget.moodsAndGenres.browseId: self = .explore(.moods)
        case _ where id.hasPrefix("VL"): self = .playlist(browseId: id)
        case _ where id.hasPrefix("MPREb"): self = .album(browseId: id)
        case _ where id.hasPrefix("UC"): self = .artist(channelId: id)
        default: self = .more(browseId: id, params: target.params)
        }
    }
}

extension MusicItem {
    /// Nil when a click plays the item: songs, videos and radio cards (`RD…`, which have no page).
    var route: Route? {
        switch self {
        case .song: nil
        case .album(let album): .album(browseId: album.browseId)
        case .artist(let artist): .artist(channelId: artist.browseId)
        case .playlist(let playlist): playlist.browseId.hasPrefix("VL") ? .playlist(browseId: playlist.browseId) : nil
        case .link(let link): Route(target: link.target)
        }
    }

    /// Unique per item kind; two items can still share one inside a shelf, so views add the offset.
    var id: String {
        switch self {
        case .song(let song): song.videoId
        case .album(let album): album.browseId
        case .artist(let artist): artist.browseId
        case .playlist(let playlist): playlist.browseId
        case .link(let link): link.target.browseId + (link.target.params ?? "")
        }
    }
}

enum ExploreTile {
    static func symbol(for browseId: String) -> String? {
        switch browseId {
        case BrowseTarget.newReleases.browseId: "music.note.list"
        case BrowseTarget.charts.browseId: "chart.line.uptrend.xyaxis"
        case BrowseTarget.moodsAndGenres.browseId: "face.smiling"
        default: nil
        }
    }
}

extension Shelf {
    private var links: [NavigationLink] {
        items.compactMap { if case .link(let link) = $0 { link } else { nil } }
    }

    private var isAllLinks: Bool { !items.isEmpty && links.count == items.count }

    /// Keyed on the targets, never on a localized title.
    var isExploreTiles: Bool {
        isAllLinks && links.allSatisfy { ExploreTile.symbol(for: $0.target.browseId) != nil }
    }

    var isLinkGrid: Bool { isAllLinks && !isExploreTiles }
}
