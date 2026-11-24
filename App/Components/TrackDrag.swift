import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let rutawaveTracks = UTType(exportedAs: "dev.kruhlyk.rutawave.tracks")
}

/// What a row or card carries when dragged. In-process drops read the ids; any other app receives the public URL.
struct TrackDrag: Codable, Transferable, Equatable {
    var videoIds: [String] = []
    /// A card drag: the album or playlist, without its tracks.
    var playlistId: String?
    /// An own-playlist row drag: the playlist the rows came from, and the rows' ids in it (for reorder).
    var sourcePlaylistId: String?
    var setVideoIds: [String] = []

    var externalURL: URL {
        var components = URLComponents(string: "https://music.youtube.com")
        if let playlistId {
            components?.path = "/playlist"
            components?.queryItems = [URLQueryItem(name: "list", value: playlistId)]
        } else if let first = videoIds.first {
            components?.path = "/watch"
            components?.queryItems = [URLQueryItem(name: "v", value: first)]
        }
        return components?.url ?? URL(string: "https://music.youtube.com")!
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .rutawaveTracks)
        ProxyRepresentation(exporting: \.externalURL)
    }
}
