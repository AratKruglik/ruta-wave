import Foundation
import InnerTube

extension MusicItem {
    var canPlay: Bool {
        switch self {
        case .song, .album, .playlist: true
        case .artist, .link: false
        }
    }

    /// Nil when the item has no public page (Liked music, a link, an album without an audio playlist).
    var shareURL: URL? {
        var components = URLComponents(string: "https://music.youtube.com")
        switch self {
        case .song(let song):
            components?.path = "/watch"
            components?.queryItems = [URLQueryItem(name: "v", value: song.videoId)]
        case .album(let album):
            guard let id = album.playTarget?.playlistId else { return nil }
            components?.path = "/playlist"
            components?.queryItems = [URLQueryItem(name: "list", value: id)]
        case .playlist(let playlist):
            return PlaylistLink.shareURL(browseId: playlist.browseId)
        case .artist(let artist):
            components?.path = "/channel/" + artist.browseId
        case .link:
            return nil
        }
        return components?.url
    }
}

enum ItemPlace: Equatable {
    case plain, ownPlaylistRow, historyRow, queueRow, playerBar
    /// `nil` while the owner is unknown.
    case sidebarPlaylist(owned: Bool?)
    case entityHeader(isOwned: Bool)
}

enum ItemAction: Equatable {
    case play, playNext, addToQueue, startRadio, shuffle, open
    case addToPlaylist, goToAlbum, goToArtist, like, copyLink, share
    case removeFromPlaylist, removeFromHistory, removeFromQueue
    case edit, likeAll, dislikeAll

    /// A guest sees these, and using one shows the sign-in prompt.
    var requiresAccount: Bool {
        switch self {
        case .addToPlaylist, .like, .removeFromPlaylist, .removeFromHistory, .edit, .likeAll, .dislikeAll: true
        default: false
        }
    }
}

enum ItemPopover: Equatable {
    case signIn(reason: String)
    case addToPlaylist(videoIds: [String])
}

enum ItemActions {
    /// Whether the list that owns the menu, not `ItemMenu`, carries the action out. Play next is the list's only at a queue row.
    static func handledByHost(_ action: ItemAction, at place: ItemPlace) -> Bool {
        switch action {
        case .removeFromPlaylist, .removeFromHistory, .removeFromQueue, .edit, .likeAll, .dislikeAll: true
        case .playNext: place == .queueRow
        default: false
        }
    }

    static func actions(for item: MusicItem, at place: ItemPlace) -> [ItemAction] {
        var result: [ItemAction]
        switch item {
        case .song(let song): result = songActions(song, at: place)
        case .album, .playlist: result = collectionActions(item, at: place)
        case .artist: result = [.open, .shuffle, .startRadio]
        case .link: result = [.open]
        }
        if item.shareURL != nil {
            if case .entityHeader = place { result += [.share] } else { result += [.copyLink, .share] }
        }
        return result
    }

    private static func songActions(_ song: Song, at place: ItemPlace) -> [ItemAction] {
        var result: [ItemAction] = []
        let canQueue = song.isAvailable
        switch place {
        case .queueRow:
            if canQueue { result += [.playNext] }
            result += [.removeFromQueue]
            if canQueue { result += [.addToPlaylist] }
        case .playerBar:
            result += [.startRadio, .addToPlaylist]
        default:
            if canQueue { result += [.play, .startRadio, .playNext, .addToQueue, .addToPlaylist] }
            if place == .ownPlaylistRow { result += [.removeFromPlaylist] }
            if place == .historyRow { result += [.removeFromHistory] }
        }
        if song.album?.browseId != nil { result += [.goToAlbum] }
        if song.artists.contains(where: { $0.browseId != nil }) { result += [.goToArtist] }
        if place == .queueRow { result += [.like] }
        return result
    }

    private static func collectionActions(_ item: MusicItem, at place: ItemPlace) -> [ItemAction] {
        switch place {
        case .entityHeader(let isOwned):
            [.playNext, .addToQueue, .likeAll, .dislikeAll] + (isOwned ? [.edit] : [])
        case .sidebarPlaylist:
            [.play, .shuffle, .playNext, .addToQueue]
        default:
            [.open, .play, .startRadio, .playNext, .addToQueue]
        }
    }
}
