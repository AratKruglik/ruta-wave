import Foundation
import PlayerEngine

public enum NotificationAuthorization: Sendable, Equatable {
    case notDetermined, denied, authorized
}

public struct TrackNotificationState: Sendable, Equatable {
    public var announcedVideoId: String?
    public var isAd = false
    /// A track that started under an ad, announced once the ad ends.
    public var pending: SongInfo?

    public init() {}
}

public enum TrackNotificationRules {
    public static let maxArtworkBytes = 1_000_000

    /// A suppressed announce still counts as announced, so the track is not announced later.
    public static func reduce(_ state: TrackNotificationState, _ event: PlayerEvent) -> (state: TrackNotificationState, announce: SongInfo?) {
        var state = state
        switch event {
        case .songChanged(let song):
            return announce(song, in: state)
        case .adChanged(let isAd):
            state.isAd = isAd
            if !isAd, let pending = state.pending { return announce(pending, in: state) }
            return (state, nil)
        case .stopped:
            state.pending = nil
            state.isAd = false
            return (state, nil)
        default:
            return (state, nil)
        }
    }

    public static func shouldPost(isEnabled: Bool, isFrontmost: Bool, authorization: NotificationAuthorization) -> Bool {
        isEnabled && !isFrontmost && authorization == .authorized
    }

    public static func isAcceptableArtwork(_ url: URL) -> Bool {
        PlayerRules.isAllowedArtworkHost(url)
    }

    public static func isAcceptableImage(mimeType: String?, byteCount: Int) -> Bool {
        guard let mimeType, mimeType.lowercased().hasPrefix("image/") else { return false }
        return (1...maxArtworkBytes).contains(byteCount)
    }

    private static func announce(_ song: SongInfo, in state: TrackNotificationState) -> (state: TrackNotificationState, announce: SongInfo?) {
        var state = state
        if song.videoId == state.announcedVideoId {
            state.pending = nil
            return (state, nil)
        }
        if state.isAd {
            state.pending = song
            return (state, nil)
        }
        state.announcedVideoId = song.videoId
        state.pending = nil
        return (state, song)
    }
}
