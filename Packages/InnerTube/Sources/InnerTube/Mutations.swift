import Foundation

public enum Rating: Sendable {
    case like, dislike, indifferent

    var endpoint: String {
        switch self {
        case .like: "like/like"
        case .dislike: "like/dislike"
        case .indifferent: "like/removelike"
        }
    }
}

public enum PlaylistPrivacy: String, Sendable {
    case `public` = "PUBLIC"
    case unlisted = "UNLISTED"
    case `private` = "PRIVATE"
}

public enum PlaylistEdit: Sendable, Equatable {
    /// A duplicate of a song already in the playlist is skipped.
    case add(videoId: String)
    case remove(videoId: String, setVideoId: String)
    /// `before` is the `setVideoId` of the row to move in front of; `nil` moves to the end.
    case move(setVideoId: String, before: String?)
    case rename(String)
    case setDescription(String)
    case setPrivacy(PlaylistPrivacy)

    public static let maxTitleLength = 150

    /// The trimmed title, or `nil` when it is empty or longer than 150 characters.
    public static func validTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.count > maxTitleLength ? nil : trimmed
    }

    var isValid: Bool {
        switch self {
        case .add(let videoId): !videoId.isEmpty
        case .remove(let videoId, let setVideoId): !videoId.isEmpty && !setVideoId.isEmpty
        case .move(let setVideoId, let before): !setVideoId.isEmpty && before?.isEmpty != true
        case .rename(let title): Self.validTitle(title) != nil
        case .setDescription, .setPrivacy: true
        }
    }

    var action: [String: any Sendable] {
        switch self {
        case .add(let videoId):
            ["action": "ACTION_ADD_VIDEO", "addedVideoId": videoId, "dedupeOption": "DEDUPE_OPTION_SKIP"]
        case .remove(let videoId, let setVideoId):
            ["action": "ACTION_REMOVE_VIDEO", "setVideoId": setVideoId, "removedVideoId": videoId]
        case .move(let setVideoId, let before):
            ["action": "ACTION_MOVE_VIDEO_BEFORE", "setVideoId": setVideoId].merging(
                before.map { ["movedSetVideoIdSuccessor": $0] } ?? [:]) { $1 }
        case .rename(let title):
            ["action": "ACTION_SET_PLAYLIST_NAME", "playlistName": Self.validTitle(title) ?? title]
        case .setDescription(let description):
            ["action": "ACTION_SET_PLAYLIST_DESCRIPTION", "playlistDescription": description]
        case .setPrivacy(let privacy):
            ["action": "ACTION_SET_PLAYLIST_PRIVACY", "playlistPrivacy": privacy.rawValue]
        }
    }
}

public struct AddedPlaylistRow: Sendable, Equatable {
    public let videoId: String
    public let setVideoId: String
}

extension [AddedPlaylistRow] {
    init(editResponse json: JSONValue) {
        self = (json["playlistEditResults"]?.array ?? []).compactMap {
            guard let data = $0["playlistEditVideoAddedResultData"],
                let videoId = data["videoId"]?.string, let setVideoId = data["setVideoId"]?.string
            else { return nil }
            return AddedPlaylistRow(videoId: videoId, setVideoId: setVideoId)
        }
    }
}
