import Foundation

public enum PlayerCommand: Sendable, Equatable {
    case play, pause, togglePlay, next, previous
    case seek(to: TimeInterval)
    /// Distinct from `seek(to:)` because Swift cannot pattern-match two cases that differ only by label.
    case skip(by: TimeInterval)
    /// 0…1, clamped. NaN and infinity are refused.
    case setVolume(Double)
    case toggleMute, toggleShuffle, cycleRepeat
    /// Signed-in only: goes through `PlayerEngine.rate`, never the page.
    case setLike(LikeStatus)
    /// An index refers to a position in the last `queueChanged`.
    case playQueueItem(index: Int)
    case enqueue(videoIds: [String], playNext: Bool)
    case removeQueueItem(index: Int)
    case moveQueueItem(from: Int, to: Int)
    case load(videoId: String, playlistId: String?)
}
