import Foundation

enum BridgeMessage: Equatable {
    case ready
    case song(SongInfo, artworkWithQuery: URL?)
    case playback(isPaused: Bool, elapsed: Double)
    case time(Double)

    static let maxBytes = 256 * 1024

    private struct Envelope: Decodable {
        let type: String
        let paused: Bool?
        let time: Double?
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
        default:
            return nil
        }
    }
}
