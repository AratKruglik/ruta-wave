import Foundation

public enum PlayerEvent: Sendable, Equatable {
    case ready
    case songChanged(SongInfo)
    case playbackChanged(isPaused: Bool, elapsed: TimeInterval)
    case timeChanged(TimeInterval)
    /// `volume` is 0…1.
    case volumeChanged(volume: Double, isMuted: Bool)
    case likeChanged(LikeStatus)
    case repeatChanged(RepeatMode)
    case shuffleChanged(Bool)
    case queueChanged([QueueItem])
    case adChanged(Bool)
    case error(PlayerError)
}
