import Foundation
import MediaPlayer
import PlayerEngine

struct NowPlayingState: Equatable, Sendable {
    var videoId: String
    var title: String
    var artist: String
    var album: String?
    var artworkURL: URL?
    var duration: TimeInterval
    var elapsed: TimeInterval
    var isPaused: Bool
    var isAd: Bool
}

enum NowPlayingRules {
    static let skipInterval: TimeInterval = 10

    /// The new state, plus whether the system needs a push. A plain time tick updates `elapsed` silently.
    static func reduce(_ state: NowPlayingState?, _ event: PlayerEvent) -> (state: NowPlayingState?, publish: Bool) {
        if case .songChanged(let song) = event {
            let next = NowPlayingState(
                videoId: song.videoId, title: song.title, artist: song.artist, album: nil, artworkURL: song.artworkURL,
                duration: song.duration, elapsed: 0, isPaused: song.isPaused, isAd: state?.isAd ?? false)
            return (next, true)
        }
        if case .stopped = event { return (nil, true) }
        guard var next = state else { return (nil, false) }
        switch event {
        case .playbackChanged(let paused, let elapsed):
            next.isPaused = paused
            if !next.isAd { next.elapsed = elapsed }
            return (next, true)
        case .timeChanged(let elapsed):
            if !next.isAd { next.elapsed = elapsed }
            return (next, false)
        case .adChanged(let isAd):
            next.isAd = isAd
            return (next, true)
        case .error(.contentProcessCrashed), .error(.playerTimeout):
            next.isPaused = true
            return (next, true)
        default:
            return (next, false)
        }
    }

    static func info(_ state: NowPlayingState) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: state.title,
            MPMediaItemPropertyArtist: state.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPaused || state.isAd ? 0.0 : 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let album = state.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if state.duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = state.duration }
        return info
    }

    static func playbackState(_ state: NowPlayingState?) -> MPNowPlayingPlaybackState {
        guard let state else { return .stopped }
        return state.isPaused ? .paused : .playing
    }
}
