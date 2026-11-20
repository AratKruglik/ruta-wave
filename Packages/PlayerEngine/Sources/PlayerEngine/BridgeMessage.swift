import Foundation

enum BridgeMessage: Equatable {
    case ready
    case song(SongInfo, artworkWithQuery: URL?)
    case playback(isPaused: Bool, elapsed: Double)
    case time(Double)
    case volume(Double, muted: Bool)
    case like(LikeStatus, videoId: String?)
    case repeatMode(RepeatMode)
    case shuffle(Bool)
    case queue([QueueItem], offset: Int)
    case ad(Bool)
    case buffering(Bool)
    case unavailable(videoId: String)

    static let maxBytes = 256 * 1024

    private struct Envelope: Decodable {
        let type: String
        let paused: Bool?
        let time: Double?
        let volume: Double?
        let muted: Bool?
        let status: String?
        let repeatMode: String?
        let shuffle: Bool?
        let items: [QueueItem.Raw]?
        let offset: Int?
        let ad: Bool?
        let buffering: Bool?
        let kind: String?
        let videoId: String?
    }

    static func decode(_ body: Any) -> BridgeMessage? {
        guard let string = body as? String, string.utf8.count <= maxBytes else { return nil }
        let data = Data(string.utf8)
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        if let time = envelope.time, !(time.isFinite && time >= 0) { return nil }
        switch envelope.type {
        case "ready":
            return .ready
        case "song":
            return SongInfo.parse(data).map { .song($0.song, artworkWithQuery: $0.artworkWithQuery) }
        case "playback":
            guard let paused = envelope.paused, let time = envelope.time else { return nil }
            return .playback(isPaused: paused, elapsed: time)
        case "time":
            return envelope.time.map { .time($0) }
        case "volume":
            guard let volume = envelope.volume, let muted = envelope.muted,
                  volume.isFinite, (0...100).contains(volume) else { return nil }
            return .volume(volume / 100, muted: muted)
        case "like":
            let videoId = envelope.videoId.flatMap { PlayerRules.isValidID($0) ? $0 : nil }
            return envelope.status.flatMap(LikeStatus.init(page:)).map { .like($0, videoId: videoId) }
        case "repeat":
            return envelope.repeatMode.flatMap(RepeatMode.init(page:)).map { .repeatMode($0) }
        case "shuffle":
            return envelope.shuffle.map { .shuffle($0) }
        case "queue":
            let offset = envelope.offset ?? 0
            // Swift adds this to queue indices, so an unbounded value from the page would overflow.
            guard (0...PlayerRules.maxQueueOffset).contains(offset) else { return nil }
            return envelope.items.flatMap(QueueItem.parse).map { .queue($0, offset: offset) }
        case "ad":
            return envelope.ad.map { .ad($0) }
        case "buffering":
            return envelope.buffering.map { .buffering($0) }
        case "error":
            guard envelope.kind == "unavailable", let id = envelope.videoId, PlayerRules.isValidID(id) else { return nil }
            return .unavailable(videoId: id)
        default:
            return nil
        }
    }
}
