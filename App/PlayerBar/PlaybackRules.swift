import Foundation
import PlayerEngine

enum PlaybackRules {
    static let volumeStep = 0.05
    static let maxEnqueueBatch = 200
    static let unavailableSkipDelay: Duration = .seconds(3)
    /// Seconds of playback between two saves of the position for `resumeOnStart`; pausing and quitting save at once.
    static let positionSaveInterval: TimeInterval = 5
    /// How close to the saved position a resumed track must report before positions are saved again.
    static let resumeTolerance: TimeInterval = 3

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

    static func formatDuration(_ seconds: TimeInterval, locale: Locale = .autoupdatingCurrent) -> String {
        let total = seconds.isFinite ? Int(min(max(seconds, 0), 999_999_999)) : 0
        let duration = Duration.seconds(total)
        let pattern: Duration.TimeFormatStyle.Pattern =
            total >= 3600 ? .hourMinuteSecond(padHourToLength: 1) : .minuteSecond(padMinuteToLength: 1)
        return duration.formatted(.time(pattern: pattern).locale(locale))
    }

    static func formatTime(_ seconds: TimeInterval, locale: Locale = .autoupdatingCurrent) -> String {
        formatDuration(seconds, locale: locale)
    }

    static func formatRemaining(_ elapsed: TimeInterval, duration: TimeInterval, locale: Locale = .autoupdatingCurrent) -> String {
        "-" + formatTime(max(duration - elapsed, 0), locale: locale)
    }

    /// Longest stretch the clock runs past the last tick, so a stalled player cannot drag the lyrics ahead.
    static let maxExtrapolation: TimeInterval = 0.5

    static func extrapolatedElapsed(_ elapsed: TimeInterval, since anchor: Date, now: Date, isRunning: Bool) -> TimeInterval {
        guard isRunning else { return elapsed }
        return elapsed + min(max(now.timeIntervalSince(anchor), 0), maxExtrapolation)
    }
}
