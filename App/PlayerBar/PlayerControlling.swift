import Foundation
import PlayerEngine

typealias PlayerQueueItem = QueueItem

@MainActor
protocol PlayerControlling: AnyObject {
    var song: SongInfo? { get }
    var elapsed: TimeInterval { get }
    var isPaused: Bool { get }
    var isReady: Bool { get }
    var isBuffering: Bool { get }
    var isAd: Bool { get }
    var volume: Double { get }
    var isMuted: Bool { get }
    var like: LikeStatus { get }
    var repeatMode: RepeatMode { get }
    var isShuffled: Bool { get }
    var queue: [QueueItem] { get }
    func send(_ command: PlayerCommand)
    func events() -> AsyncStream<PlayerEvent>
}

extension PlayerEngine: PlayerControlling {}
