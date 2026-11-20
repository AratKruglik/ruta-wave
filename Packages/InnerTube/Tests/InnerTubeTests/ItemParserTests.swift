import Foundation
import Testing
@testable import InnerTube

private func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private func browse(_ id: String, _ pageType: String) -> String {
    #"{"browseEndpoint":{"browseId":"\#(id)","browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"\#(pageType)"}}}}"#
}

private func watch(_ id: String, type: String? = nil) -> String {
    let config = type.map { #","watchEndpointMusicSupportedConfigs":{"watchEndpointMusicConfig":{"musicVideoType":"\#($0)"}}"# } ?? ""
    return #"{"watchEndpoint":{"videoId":"\#(id)"\#(config)}}"#
}

private func twoRow(endpoint: String, title: String = "Title", extra: String = "") -> String {
    #"{"musicTwoRowItemRenderer":{"navigationEndpoint":\#(endpoint),"title":{"runs":[{"text":"\#(title)"}]}\#(extra)}}"#
}

private func row(endpoint: String? = nil, titleRun: String = #"{"text":"Title"}"#, extra: String = "") -> String {
    let nav = endpoint.map { #""navigationEndpoint":\#($0),"# } ?? ""
    return #"{"musicResponsiveListItemRenderer":{\#(nav)"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[\#(titleRun)]}}}]\#(extra)}}"#
}

@Suite struct ItemParserTests {
    @Test func browsePageTypeDecidesAlbumArtistPlaylist() throws {
        guard case .album(let album) = try ItemParser.item(json(twoRow(endpoint: browse("MPREb_1", "MUSIC_PAGE_TYPE_ALBUM")))) else {
            Issue.record("expected album")
            return
        }
        #expect(album.browseId == "MPREb_1")
        #expect(try ItemParser.item(json(twoRow(endpoint: browse("UC1", "MUSIC_PAGE_TYPE_ARTIST")))) == .artist(Artist(browseId: "UC1", name: "Title")))
        #expect(try ItemParser.item(json(twoRow(endpoint: browse("VLPL1", "MUSIC_PAGE_TYPE_PLAYLIST")))) == .playlist(Playlist(browseId: "VLPL1", title: "Title")))
    }

    @Test func unsupportedBrowseTargetsAreSkipped() throws {
        for type in ["MUSIC_PAGE_TYPE_USER_CHANNEL", "MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE", "MUSIC_PAGE_TYPE_NON_MUSIC_AUDIO_TRACK_PAGE"] {
            #expect(try ItemParser.item(json(twoRow(endpoint: browse("X", type)))) == nil)
        }
    }

    @Test func watchEndpointDecidesSongOrVideo() throws {
        #expect(try ItemParser.item(json(twoRow(endpoint: watch("v1", type: "MUSIC_VIDEO_TYPE_ATV")))) == .song(Song(videoId: "v1", title: "Title")))
        #expect(try ItemParser.item(json(twoRow(endpoint: watch("v2")))) == .song(Song(videoId: "v2", title: "Title")))
        for type in ["MUSIC_VIDEO_TYPE_OMV", "MUSIC_VIDEO_TYPE_UGC"] {
            #expect(try ItemParser.item(json(twoRow(endpoint: watch("v3", type: type)))) == .song(Song(videoId: "v3", title: "Title", isVideo: true)))
        }
        #expect(try ItemParser.item(json(twoRow(endpoint: watch("v4", type: "MUSIC_VIDEO_TYPE_PODCAST_EPISODE")))) == nil)
    }

    @Test func radioCardIsAPlaylist() throws {
        let endpoint = #"{"watchPlaylistEndpoint":{"playlistId":"RD1"}}"#
        #expect(try ItemParser.item(json(twoRow(endpoint: endpoint))) == .playlist(Playlist(browseId: "RD1", title: "Title", playTarget: WatchTarget(playlistId: "RD1"))))
    }

    @Test func overlayPlayButtonIsTheCardsPlayTarget() throws {
        let overlay = #","thumbnailOverlay":{"musicItemThumbnailOverlayRenderer":{"content":{"musicPlayButtonRenderer":{"playNavigationEndpoint":{"watchPlaylistEndpoint":{"playlistId":"OLAK5uy_x","params":"wAEB"}}}}}}"#
        let album = try ItemParser.item(json(twoRow(endpoint: browse("MPREb1", "MUSIC_PAGE_TYPE_ALBUM"), extra: overlay)))
        guard case .album(let value)? = album else {
            Issue.record("expected album")
            return
        }
        #expect(value.playTarget == WatchTarget(playlistId: "OLAK5uy_x", params: "wAEB"))
    }

    @Test func menuEndpointsDoNotChangeTheKind() throws {
        let menu = #","menu":{"menuRenderer":{"items":[{"menuNavigationItemRenderer":{"navigationEndpoint":\#(browse("UCmenu", "MUSIC_PAGE_TYPE_ARTIST"))}},{"menuNavigationItemRenderer":{"navigationEndpoint":\#(browse("MPREbmenu", "MUSIC_PAGE_TYPE_ALBUM"))}}]}}"#
        let song = try ItemParser.item(json(row(titleRun: #"{"text":"Title","navigationEndpoint":\#(watch("v1", type: "MUSIC_VIDEO_TYPE_ATV"))}"#, extra: menu)))
        #expect(song == .song(Song(videoId: "v1", title: "Title")))
    }

    @Test func listRowUsesItsOwnEndpointsInOrder() throws {
        let overlay = #","overlay":{"musicItemThumbnailOverlayRenderer":{"content":{"musicPlayButtonRenderer":{"playNavigationEndpoint":\#(watch("ov", type: "MUSIC_VIDEO_TYPE_PODCAST_EPISODE"))}}}}"#
        #expect(try ItemParser.item(json(row(extra: overlay))) == nil)
        #expect(try ItemParser.item(json(row(endpoint: browse("UC1", "MUSIC_PAGE_TYPE_ARTIST"), extra: overlay))) == .artist(Artist(browseId: "UC1", name: "Title")))
        #expect(try ItemParser.item(json(row(extra: #","playlistItemData":{"videoId":"pl"}"#))) == .song(Song(videoId: "pl", title: "Title")))
        #expect(try ItemParser.item(json(row())) == nil)
    }

    @Test func podcastEpisodeRowWithoutOwnNavigationIsSkipped() throws {
        let overlay = #","overlay":{"musicItemThumbnailOverlayRenderer":{"content":{"musicPlayButtonRenderer":{"playNavigationEndpoint":\#(watch("ep", type: "MUSIC_VIDEO_TYPE_PODCAST_EPISODE"))}}}},"playlistItemData":{"videoId":"ep"}"#
        let titleRun = #"{"text":"Episode","navigationEndpoint":\#(browse("MPEDx", "MUSIC_PAGE_TYPE_NON_MUSIC_AUDIO_TRACK_PAGE"))}"#
        #expect(try ItemParser.item(json(row(titleRun: titleRun, extra: overlay))) == nil)
    }

    @Test func itemWithoutTitleOrIdentityIsDropped() throws {
        #expect(try ItemParser.item(json(#"{"musicTwoRowItemRenderer":{"navigationEndpoint":\#(watch("v1"))}}"#)) == nil)
        #expect(try ItemParser.item(json(twoRow(endpoint: #"{"watchEndpoint":{"videoId":""}}"#))) == nil)
        #expect(try ItemParser.item(json(twoRow(endpoint: browse("", "MUSIC_PAGE_TYPE_ALBUM")))) == nil)
        #expect(try ItemParser.item(json(#"{"somethingElseRenderer":{}}"#)) == nil)
    }

    @Test func explicitBadgeAndDuration() throws {
        let badge = #","badges":[{"musicInlineBadgeRenderer":{"icon":{"iconType":"MUSIC_EXPLICIT_BADGE"}}}]"#
        let renderer = #"""
        {"musicResponsiveListItemRenderer":{"navigationEndpoint":\#(watch("v1")),"flexColumns":[
        {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Title"}]}}},
        {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Artist"},{"text":" • "},{"text":"12M plays"},{"text":" • "},{"text":"1:02:03"}]}}}]\#(badge)}}
        """#
        guard case .song(let song) = try ItemParser.item(json(renderer)) else {
            Issue.record("expected song")
            return
        }
        #expect(song.isExplicit)
        #expect(song.duration == "1:02:03")
        #expect(song.subtitle == "Artist • 12M plays • 1:02:03")
    }

    @Test func subtitleLinksBecomeArtistsAndAlbum() throws {
        let subtitle = #"""
        ,"subtitle":{"runs":[
        {"text":"Single"},{"text":" • "},
        {"text":"Ann","navigationEndpoint":\#(browse("UCa", "MUSIC_PAGE_TYPE_ARTIST"))},{"text":" & "},
        {"text":"Bob","navigationEndpoint":\#(browse("UCb", "MUSIC_PAGE_TYPE_ARTIST"))},{"text":" • "},
        {"text":"Disc","navigationEndpoint":\#(browse("MPREb_d", "MUSIC_PAGE_TYPE_ALBUM"))}]}
        """#
        guard case .song(let song) = try ItemParser.item(json(twoRow(endpoint: watch("v1"), extra: subtitle))) else {
            Issue.record("expected song")
            return
        }
        #expect(song.artists == [ItemRef(name: "Ann", browseId: "UCa"), ItemRef(name: "Bob", browseId: "UCb")])
        #expect(song.album == ItemRef(name: "Disc", browseId: "MPREb_d"))
        #expect(song.subtitle == "Single • Ann & Bob • Disc")
    }

    @Test func thumbnailOutsideTheAllowlistBecomesNil() throws {
        func thumbnail(_ url: String) -> String {
            #","thumbnailRenderer":{"musicThumbnailRenderer":{"thumbnail":{"thumbnails":[{"url":"\#(url)"}]}}}"#
        }
        func url(_ value: String) throws -> URL? {
            guard case .playlist(let playlist) = try ItemParser.item(json(twoRow(endpoint: browse("VL1", "MUSIC_PAGE_TYPE_PLAYLIST"), extra: thumbnail(value)))) else {
                Issue.record("expected playlist")
                return nil
            }
            return playlist.thumbnailURL
        }
        #expect(try url("https://yt3.googleusercontent.com/a=w226") == URL(string: "https://yt3.googleusercontent.com/a=w226"))
        #expect(try url("https://www.youtube.com/img/music/x.png") == nil)
        #expect(try url("http://yt3.googleusercontent.com/a") == nil)
    }

    @Test(arguments: [("ARROW_DROP_UP", ChartRank.Trend.up), ("ARROW_DROP_DOWN", .down), ("ARROW_CHART_NEUTRAL", .neutral)])
    func rankTrendFromIcon(_ icon: String, _ trend: ChartRank.Trend) throws {
        let index = #","customIndexColumn":{"musicCustomIndexColumnRenderer":{"text":{"runs":[{"text":"7"}]},"icon":{"iconType":"\#(icon)"}}}"#
        guard case .song(let song) = try ItemParser.item(json(row(endpoint: watch("v1"), extra: index))) else {
            Issue.record("expected song")
            return
        }
        #expect(song.rank == ChartRank(position: 7, trend: trend))
    }

    @Test func rankWithoutIconHasNoTrend() throws {
        let index = #","customIndexColumn":{"musicCustomIndexColumnRenderer":{"text":{"runs":[{"text":"3"}]}}}"#
        guard case .song(let song) = try ItemParser.item(json(row(endpoint: watch("v1"), extra: index))) else {
            Issue.record("expected song")
            return
        }
        #expect(song.rank == ChartRank(position: 3, trend: nil))
    }

    @Test func navigationButtonBecomesALink() throws {
        let button = #"{"musicNavigationButtonRenderer":{"buttonText":{"runs":[{"text":"Chill"}]},"clickCommand":{"browseEndpoint":{"browseId":"FEmusic_moods_and_genres_category","params":"p1"}}}}"#
        #expect(try ItemParser.item(json(button)) == .link(NavigationLink(title: "Chill", target: BrowseTarget(browseId: "FEmusic_moods_and_genres_category", params: "p1"))))
        let colored = button.replacingOccurrences(of: #""clickCommand""#, with: #""solid":{"leftStripeColor":4288988671},"clickCommand""#)
        #expect(try ItemParser.item(json(colored)) == .link(NavigationLink(title: "Chill", target: BrowseTarget(browseId: "FEmusic_moods_and_genres_category", params: "p1"), stripeColor: 4288988671)))
    }

    @Test func playAllButtonIsNotAMoreTarget() throws {
        let shelf = #"""
        {"musicCarouselShelfRenderer":{"header":{"musicCarouselShelfBasicHeaderRenderer":{"title":{"runs":[{"text":"T"}]},
        "moreContentButton":{"buttonRenderer":{"navigationEndpoint":\#(watch("v1"))}}}},
        "contents":[\#(twoRow(endpoint: watch("v1")))]}}
        """#
        #expect(try ItemParser.section(json(shelf))?.more == nil)
    }

    @Test func titleRunEndpointIsTheMoreFallback() throws {
        let shelf = #"""
        {"musicCarouselShelfRenderer":{"header":{"musicCarouselShelfBasicHeaderRenderer":{"title":{"runs":[{"text":"T","navigationEndpoint":{"browseEndpoint":{"browseId":"FEx","params":"p"}}}]}}},
        "contents":[\#(twoRow(endpoint: watch("v1")))]}}
        """#
        #expect(try ItemParser.section(json(shelf))?.more == BrowseTarget(browseId: "FEx", params: "p"))
    }

    @Test func shelfWhoseItemsAllDropIsDropped() throws {
        let shelf = #"{"musicCarouselShelfRenderer":{"contents":[\#(twoRow(endpoint: browse("X", "MUSIC_PAGE_TYPE_USER_CHANNEL")))]}}"#
        #expect(try ItemParser.section(json(shelf)) == nil)
    }
}
