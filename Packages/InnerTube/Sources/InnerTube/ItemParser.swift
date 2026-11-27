import Foundation

enum ItemParser {
    private enum Destination {
        case song(videoId: String, playlistId: String?, isVideo: Bool)
        case album(browseId: String, params: String?)
        case artist(String)
        case playlist(String)
    }

    static func item(_ block: JSONValue) -> MusicItem? {
        if let renderer = block["musicTwoRowItemRenderer"] { return twoRow(renderer) }
        if let renderer = block["musicResponsiveListItemRenderer"] { return listRow(renderer) }
        if let renderer = block["musicNavigationButtonRenderer"] { return link(renderer) }
        return nil
    }

    static func song(_ block: JSONValue) -> Song? {
        guard case .song(let song)? = item(block) else { return nil }
        return song
    }

    static func playlistRow(_ block: JSONValue) -> Song? {
        guard var song = song(block) else { return nil }
        song.playlistSetVideoId = block["musicResponsiveListItemRenderer"]?["playlistItemData"]?["playlistSetVideoId"]?.string
        return song
    }

    static func section(_ block: JSONValue) -> Shelf? {
        let shelf: Shelf
        if let renderer = block["musicCarouselShelfRenderer"] {
            let contents = renderer["contents"]?.array ?? []
            let header = renderer["header"]?["musicCarouselShelfBasicHeaderRenderer"]
            shelf = makeShelf(
                title: header?["title"], strapline: header?["strapline"], moreCandidates: moreCandidates(header),
                layout: contents.first?["musicResponsiveListItemRenderer"] != nil ? .rows : .cards, contents: contents)
        } else if let renderer = block["gridRenderer"] {
            shelf = makeShelf(
                title: renderer["header"]?["gridHeaderRenderer"]?["title"], strapline: nil, moreCandidates: [],
                layout: .grid, contents: renderer["items"]?.array ?? [])
        } else if let renderer = block["musicShelfRenderer"] {
            shelf = makeShelf(
                title: renderer["title"], strapline: nil,
                moreCandidates: [renderer["bottomEndpoint"], renderer["title"]?["runs"]?[0]?["navigationEndpoint"]],
                layout: .list, contents: renderer["contents"]?.array ?? [])
        } else {
            return nil
        }
        guard !shelf.items.isEmpty else {
            parserLog.notice("Skipped shelf without supported items")
            return nil
        }
        return shelf
    }

    /// An artist, album or playlist from a search card's `onTap`, or any other item that has no row renderer.
    static func card(_ renderer: JSONValue) -> MusicItem? {
        build(
            destination: destination(renderer["onTap"]), title: renderer["title"].flatMap(text),
            subtitleRuns: renderer["subtitle"]?["runs"]?.array ?? [],
            thumbnail: thumbnail(renderer["thumbnail"]), renderer: renderer)
    }

    /// A cover sits in a `musicThumbnailRenderer`, or a `croppedSquareThumbnailRenderer` on generated mixes.
    static func thumbnail(_ container: JSONValue?) -> JSONValue? {
        container?["musicThumbnailRenderer"]?["thumbnail"] ?? container?["croppedSquareThumbnailRenderer"]?["thumbnail"]
    }

    static func chips(_ chipCloud: JSONValue?) -> [Chip] {
        (chipCloud?["chips"]?.array ?? []).compactMap { block in
            guard let chip = block["chipCloudChipRenderer"], let title = chip["text"].flatMap(text) else { return nil }
            let endpoint = chip["navigationEndpoint"]
            return Chip(
                title: title,
                target: endpoint?["browseEndpoint"].flatMap(browseTarget),
                searchParams: endpoint?["searchEndpoint"]?["params"]?.string,
                isSelected: chip["isSelected"]?.bool ?? false,
                watchTarget: endpoint?["queueUpdateCommand"]?["fetchContentsCommand"].flatMap(watchTarget))
        }
    }

    /// Reads a `watchEndpoint` or a `watchPlaylistEndpoint` held by `parent`, or by the endpoint itself.
    static func watchTarget(_ parent: JSONValue) -> WatchTarget? {
        guard let endpoint = parent["watchEndpoint"] ?? parent["watchPlaylistEndpoint"] else { return nil }
        let target = WatchTarget(
            videoId: endpoint["videoId"]?.string, playlistId: endpoint["playlistId"]?.string, params: endpoint["params"]?.string)
        return target.videoId == nil && target.playlistId == nil ? nil : target
    }

    /// A row of the Up next queue (`playlistPanelVideoRenderer`).
    static func queueItem(_ renderer: JSONValue) -> Song? {
        guard renderer["unplayableText"] == nil, let title = renderer["title"].flatMap(text), case .song(let videoId, let playlistId, let isVideo)? = destination(renderer["navigationEndpoint"])
        else { return nil }
        let byline = renderer["longBylineText"]
        let (artists, album) = refs(byline?["runs"]?.array ?? [])
        return Song(
            videoId: videoId, playlistId: playlistId, title: title, subtitle: byline.flatMap(text), artists: artists, album: album,
            duration: renderer["lengthText"]?["runs"]?.array.flatMap(duration), thumbnailURL: renderer["thumbnail"].flatMap(lastThumbnailURL),
            isExplicit: isExplicit(renderer), isVideo: isVideo)
    }

    static func browseTarget(_ endpoint: JSONValue) -> BrowseTarget? {
        guard let browseId = endpoint["browseId"]?.string, !browseId.isEmpty else { return nil }
        return BrowseTarget(browseId: browseId, params: endpoint["params"]?.string)
    }

    private static func makeShelf(
        title: JSONValue?, strapline: JSONValue?, moreCandidates: [JSONValue?], layout: Shelf.Layout, contents: [JSONValue]
    ) -> Shelf {
        Shelf(
            title: title.flatMap(text),
            strapline: strapline.flatMap(text),
            more: moreCandidates.lazy.compactMap { $0?["browseEndpoint"].flatMap(browseTarget) }.first,
            layout: layout,
            items: parseBlocks(contents, item))
    }

    // "Play all" buttons carry a watch endpoint and are not a More target.
    private static func moreCandidates(_ header: JSONValue?) -> [JSONValue?] {
        [
            header?["moreContentButton"]?["buttonRenderer"]?["navigationEndpoint"],
            header?["title"]?["runs"]?[0]?["navigationEndpoint"],
        ]
    }

    private static func twoRow(_ renderer: JSONValue) -> MusicItem? {
        let endpoint = renderer["navigationEndpoint"] ?? renderer["title"]?["runs"]?[0]?["navigationEndpoint"]
        let overlay = renderer["thumbnailOverlay"]?["musicItemThumbnailOverlayRenderer"]?["content"]?["musicPlayButtonRenderer"]?["playNavigationEndpoint"]
        // A signed-in mix card has an empty overlay: its own endpoint is the play target.
        let playTarget = overlay.flatMap(watchTarget) ?? endpoint.flatMap { $0["watchPlaylistEndpoint"] == nil ? nil : watchTarget($0) }
        return build(
            destination: destination(endpoint), title: renderer["title"].flatMap(text),
            subtitleRuns: renderer["subtitle"]?["runs"]?.array ?? [],
            thumbnail: thumbnail(renderer["thumbnailRenderer"]), renderer: renderer,
            playTarget: playTarget)
    }

    private static func listRow(_ renderer: JSONValue) -> MusicItem? {
        let columns = (renderer["flexColumns"]?.array ?? []).compactMap { $0["musicResponsiveListItemFlexColumnRenderer"]?["text"] }
        // Only the item's own endpoints decide its kind. Menus hold unrelated artist and album endpoints.
        let own = renderer["navigationEndpoint"]
            ?? columns.first?["runs"]?[0]?["navigationEndpoint"]
            ?? renderer["overlay"]?["musicItemThumbnailOverlayRenderer"]?["content"]?["musicPlayButtonRenderer"]?["playNavigationEndpoint"]
        let destination: Destination?
        if let own {
            destination = Self.destination(own)
        } else {
            destination = renderer["playlistItemData"]?["videoId"]?.string.map { .song(videoId: $0, playlistId: nil, isVideo: false) }
        }
        let details = columns.dropFirst()
        let fixed = (renderer["fixedColumns"]?.array ?? []).flatMap {
            $0["musicResponsiveListItemFixedColumnRenderer"]?["text"]?["runs"]?.array ?? []
        }
        return build(
            destination: destination, title: columns.first.flatMap(text),
            subtitleRuns: details.flatMap { $0["runs"]?.array ?? [] },
            subtitle: details.compactMap(text).joined(separator: " • "), durationRuns: fixed,
            thumbnail: thumbnail(renderer["thumbnail"]), renderer: renderer)
    }

    private static func link(_ renderer: JSONValue) -> MusicItem? {
        guard let title = renderer["buttonText"].flatMap(text),
              let target = renderer["clickCommand"]?["browseEndpoint"].flatMap(browseTarget)
        else { return nil }
        let stripe = renderer["solid"]?["leftStripeColor"]?.double.flatMap { UInt32(exactly: $0) }
        return .link(NavigationLink(title: title, target: target, stripeColor: stripe))
    }

    private static func build(
        destination: Destination?, title: String?, subtitleRuns: [JSONValue], subtitle: String? = nil,
        durationRuns: [JSONValue] = [], thumbnail: JSONValue?, renderer: JSONValue, playTarget: WatchTarget? = nil
    ) -> MusicItem? {
        guard let destination, let title else { return nil }
        let subtitle = (subtitle ?? text(.object(["runs": .array(subtitleRuns)]))).flatMap { $0.isEmpty ? nil : $0 }
        let (artists, album) = refs(subtitleRuns)
        let url = thumbnail.flatMap(lastThumbnailURL)
        let isExplicit = isExplicit(renderer)
        let rank = rank(renderer)
        switch destination {
        case .song(let videoId, let playlistId, let isVideo):
            return .song(Song(
                videoId: videoId, playlistId: playlistId, title: title, subtitle: subtitle, artists: artists, album: album,
                duration: duration(subtitleRuns + durationRuns), thumbnailURL: url, isExplicit: isExplicit, isVideo: isVideo, rank: rank,
                isAvailable: renderer["musicItemRendererDisplayPolicy"]?.string != "MUSIC_ITEM_RENDERER_DISPLAY_POLICY_GREY_OUT"))
        case .album(let browseId, let params):
            return .album(Album(
                browseId: browseId, title: title, subtitle: subtitle, artists: artists, thumbnailURL: url, isExplicit: isExplicit,
                playTarget: playTarget, params: params))
        case .artist(let browseId):
            return .artist(Artist(browseId: browseId, name: title, subtitle: subtitle, thumbnailURL: url, rank: rank))
        case .playlist(let browseId):
            return .playlist(Playlist(browseId: browseId, title: title, subtitle: subtitle, thumbnailURL: url, playTarget: playTarget))
        }
    }

    private static func destination(_ endpoint: JSONValue?) -> Destination? {
        if let browse = endpoint?["browseEndpoint"], let browseId = browse["browseId"]?.string, !browseId.isEmpty {
            switch pageType(browse) {
            case "MUSIC_PAGE_TYPE_ALBUM": return .album(browseId: browseId, params: browse["params"]?.string)
            case "MUSIC_PAGE_TYPE_ARTIST": return .artist(browseId)
            // A library artist (`MPLA` + channel id) opens the public artist page.
            case "MUSIC_PAGE_TYPE_LIBRARY_ARTIST" where browseId.hasPrefix("MPLAUC"): return .artist(String(browseId.dropFirst(4)))
            case "MUSIC_PAGE_TYPE_PLAYLIST": return .playlist(browseId)
            default: return nil
            }
        }
        if let watch = endpoint?["watchEndpoint"], let videoId = watch["videoId"]?.string, !videoId.isEmpty {
            let type = watch["watchEndpointMusicSupportedConfigs"]?["watchEndpointMusicConfig"]?["musicVideoType"]?.string
            let playlistId = watch["playlistId"]?.string
            switch type {
            case nil, "MUSIC_VIDEO_TYPE_ATV", "MUSIC_VIDEO_TYPE_OFFICIAL_SOURCE_MUSIC":
                return .song(videoId: videoId, playlistId: playlistId, isVideo: false)
            case "MUSIC_VIDEO_TYPE_OMV", "MUSIC_VIDEO_TYPE_UGC":
                return .song(videoId: videoId, playlistId: playlistId, isVideo: true)
            default: return nil
            }
        }
        if let playlistId = endpoint?["watchPlaylistEndpoint"]?["playlistId"]?.string, !playlistId.isEmpty {
            return .playlist(playlistId)
        }
        return nil
    }

    static func pageType(_ browse: JSONValue) -> String? {
        browse["browseEndpointContextSupportedConfigs"]?["browseEndpointContextMusicConfig"]?["pageType"]?.string
    }

    static func refs(_ runs: [JSONValue]) -> (artists: [ItemRef], album: ItemRef?) {
        var artists: [ItemRef] = []
        var album: ItemRef?
        for run in runs {
            guard let browse = run["navigationEndpoint"]?["browseEndpoint"], let name = run["text"]?.string,
                  let browseId = browse["browseId"]?.string
            else { continue }
            switch pageType(browse) {
            case "MUSIC_PAGE_TYPE_ARTIST": artists.append(ItemRef(name: name, browseId: browseId))
            case "MUSIC_PAGE_TYPE_ALBUM": album = album ?? ItemRef(name: name, browseId: browseId)
            default: continue
            }
        }
        return (artists, album)
    }

    private static func duration(_ runs: [JSONValue]) -> String? {
        runs.compactMap { $0["text"]?.string }.last { $0.wholeMatch(of: /\d+(:\d{2})+/) != nil }
    }

    static func isExplicit(_ renderer: JSONValue) -> Bool {
        ["badges", "subtitleBadges"].contains { key in
            (renderer[key]?.array ?? []).contains {
                $0["musicInlineBadgeRenderer"]?["icon"]?["iconType"]?.string == "MUSIC_EXPLICIT_BADGE"
            }
        }
    }

    private static func rank(_ renderer: JSONValue) -> ChartRank? {
        guard let column = renderer["customIndexColumn"]?["musicCustomIndexColumnRenderer"],
              let position = column["text"].flatMap(text).flatMap(Int.init)
        else { return nil }
        let trend: ChartRank.Trend? = switch column["icon"]?["iconType"]?.string {
        case "ARROW_DROP_UP": .up
        case "ARROW_DROP_DOWN": .down
        case "ARROW_CHART_NEUTRAL": .neutral
        default: nil
        }
        return ChartRank(position: position, trend: trend)
    }
}
