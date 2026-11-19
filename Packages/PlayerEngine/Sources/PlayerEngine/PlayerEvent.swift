import Foundation

public enum PlayerEvent: Sendable, Equatable {
    case ready
    case songChanged(SongInfo)
    case playbackChanged(isPaused: Bool, elapsed: TimeInterval)
    case timeChanged(TimeInterval)
}
