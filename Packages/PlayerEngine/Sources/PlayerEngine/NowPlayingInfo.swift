import Foundation

/// What the system's Now Playing entry shows; published through the page's Media Session.
public struct NowPlayingInfo: Sendable, Equatable {
    public var title: String
    public var artist: String
    public var album: String?
    public var artworkURL: URL?
    public var duration: TimeInterval
    public var elapsed: TimeInterval
    public var isPlaying: Bool

    public init(
        title: String, artist: String, album: String?, artworkURL: URL?, duration: TimeInterval, elapsed: TimeInterval,
        isPlaying: Bool
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.duration = duration
        self.elapsed = elapsed
        self.isPlaying = isPlaying
    }
}
