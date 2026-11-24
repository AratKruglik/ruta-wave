import Foundation
import PlayerEngine

enum PlaybackRules {
    static let volumeStep = 0.05
    static let maxEnqueueBatch = 200
    static let unavailableSkipDelay: Duration = .seconds(3)

    static func nextRepeat(_ mode: RepeatMode) -> RepeatMode {
        switch mode {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    /// How many `cycleRepeat` commands turn `current` into `target`.
    static func repeatSteps(from current: RepeatMode, to target: RepeatMode) -> Int {
        var steps = 0
        var mode = current
        while mode != target {
            mode = nextRepeat(mode)
            steps += 1
        }
        return steps
    }

    /// A fully blocked queue stops at its end instead of looping through error toasts.
    static func shouldSkipUnavailable(queue: [QueueItem], repeatMode: RepeatMode) -> Bool {
        guard let index = queue.firstIndex(where: \.isCurrent) else { return false }
        return index < queue.count - 1 || repeatMode == .all
    }

    static func volume(_ level: Double, steppedBy steps: Int) -> Double {
        let stepped = ((level + Double(steps) * volumeStep) * 100).rounded() / 100
        return min(max(stepped, 0), 1)
    }

    static func formatTime(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? Int(min(max(seconds, 0), 999_999_999)) : 0
        let (hours, minutes, secs) = (total / 3600, total % 3600 / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    static func formatRemaining(_ elapsed: TimeInterval, duration: TimeInterval) -> String {
        "-" + formatTime(max(duration - elapsed, 0))
    }
}
