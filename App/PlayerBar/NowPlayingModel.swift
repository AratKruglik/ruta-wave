import AppSettings
import Foundation
import InnerTube
import Observation
import PlayerEngine

struct TrackDetails: Equatable {
    let videoId: String
    let artists: [ItemRef]
    let album: ItemRef?
    let isVideo: Bool
}

@MainActor @Observable
final class NowPlayingModel {
    enum LikePrompt { case like, dislike }

    let player: any PlayerControlling
    var details: TrackDetails?
    var likePrompt: LikePrompt?
    var timeShowsRemaining = false
    private(set) var rowRatings: [String: Rating] = [:]

    @ObservationIgnored private let toasts: ToastCenter
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let credentials: @MainActor () -> Credentials?
    @ObservationIgnored private let client: InnerTubeClient?
    @ObservationIgnored private let resolveFirstVideo: (@MainActor (WatchTarget, Credentials?) async throws -> String?)?
    @ObservationIgnored private var playTask: Task<Void, Never>?
    @ObservationIgnored private var ratingGeneration = 0
    @ObservationIgnored private var skip: (videoId: String, task: Task<Void, Never>)?
    @ObservationIgnored private var unavailableStreak = 0
    @ObservationIgnored private var syncsRepeat = false
    @ObservationIgnored private var syncsShuffle = false

    init(
        player: any PlayerControlling, toasts: ToastCenter, preferences: Preferences = Preferences(),
        credentials: @escaping @MainActor () -> Credentials?, client: InnerTubeClient? = InnerTubeClient(),
        resolveFirstVideo: (@MainActor (WatchTarget, Credentials?) async throws -> String?)? = nil
    ) {
        self.resolveFirstVideo = resolveFirstVideo
        self.player = player
        self.toasts = toasts
        self.preferences = preferences
        self.credentials = credentials
        self.client = client
    }

    var isSignedIn: Bool { credentials() != nil }

    func run() async {
        player.send(.setVolume(preferences.volume))
        for await event in player.events() {
            handle(event)
        }
    }

    private func handle(_ event: PlayerEvent) {
        switch event {
        case .ready:
            syncsRepeat = true
            syncsShuffle = true
        case .repeatChanged(let reported) where syncsRepeat:
            syncsRepeat = false
            let target = RepeatMode(preference: preferences.repeatMode)
            for _ in 0..<PlaybackRules.repeatSteps(from: reported, to: target) { player.send(.cycleRepeat) }
        case .shuffleChanged(let reported) where syncsShuffle:
            syncsShuffle = false
            if reported != preferences.shuffle { player.send(.toggleShuffle) }
        case .songChanged(let song):
            unavailableStreak = 0
            if skip?.videoId != song.videoId { cancelSkip() }
        case .error(.unavailable(let videoId)):
            toasts.show("This track is unavailable")
            unavailableStreak += 1
            scheduleSkip(after: videoId)
        default:
            break
        }
    }

    private func scheduleSkip(after videoId: String) {
        cancelSkip()
        guard unavailableStreak < player.queue.count,
              PlaybackRules.shouldSkipUnavailable(queue: player.queue, repeatMode: player.repeatMode) else { return }
        let task = Task { [weak self] in
            try? await Task.sleep(for: PlaybackRules.unavailableSkipDelay)
            guard !Task.isCancelled, let self else { return }
            skip = nil
            player.send(.next)
        }
        skip = (videoId, task)
    }

    private func cancelSkip() {
        skip?.task.cancel()
        skip = nil
    }

    func togglePlay() { act(.togglePlay) }
    func previous() { act(.previous) }
    func next() { act(.next) }
    func seek(to seconds: TimeInterval) { act(.seek(to: seconds)) }
    func skip(by seconds: TimeInterval) { act(.skip(by: seconds)) }

    func setVolume(_ level: Double) {
        player.send(.setVolume(level))
        if player.isReady { preferences.volume = level }
    }

    func adjustVolume(steps: Int) {
        setVolume(PlaybackRules.volume(player.volume, steppedBy: steps))
    }

    func toggleMute() { player.send(.toggleMute) }

    func cycleRepeat() {
        if player.isReady { preferences.repeatMode = PlaybackRules.nextRepeat(player.repeatMode).preference }
        player.send(.cycleRepeat)
    }

    func toggleShuffle() {
        if player.isReady { preferences.shuffle = !player.isShuffled }
        player.send(.toggleShuffle)
    }

    func toggleLike() { rate(.like, prompt: .like) }
    func toggleDislike() { rate(.dislike, prompt: .dislike) }

    private func rate(_ status: LikeStatus, prompt: LikePrompt) {
        guard isSignedIn else {
            likePrompt = prompt
            return
        }
        player.send(.setLike(player.like == status ? .indifferent : status))
    }

    private func act(_ command: PlayerCommand) {
        cancelSkip()
        player.send(command)
    }

    func play(_ item: MusicItem) {
        switch item {
        case .song(let song):
            act(.load(videoId: song.videoId, playlistId: song.playlistId))
        case .album(let album):
            playCollection(album.playTarget)
        case .playlist(let playlist):
            playCollection(playlist.playTarget ?? WatchTarget(playlistId: playlist.browseId.removingPrefix("VL")))
        case .artist, .link:
            break
        }
    }

    // shortcut: RDAMVM{videoId} is the community-known radio id, unverified against a fixture; parse watchEndpoint params if radio starts fail.
    func startRadio(_ song: Song) {
        act(.load(videoId: song.videoId, playlistId: song.playlistId ?? "RDAMVM" + song.videoId))
    }

    func isPlaying(_ item: MusicItem) -> Bool {
        guard let current = player.song else { return false }
        switch item {
        case .song(let song): return current.videoId == song.videoId
        case .album(let album): return Self.matches(current.playlistId, album.playTarget)
        case .playlist(let playlist):
            return Self.matches(current.playlistId, playlist.playTarget ?? WatchTarget(playlistId: playlist.browseId.removingPrefix("VL")))
        case .artist, .link: return false
        }
    }

    func rate(videoId: String, _ rating: Rating) {
        guard let client, let credentials = credentials() else { return }
        let previous = rowRatings[videoId]
        let captured = ratingGeneration
        rowRatings[videoId] = rating
        Task { [weak self] in
            do {
                try await client.rate(videoId: videoId, rating, credentials: credentials)
            } catch {
                guard let self, ratingGeneration == captured else { return }
                rowRatings[videoId] = previous
                toasts.show("Couldn't update the rating")
            }
        }
    }

    /// Called when the content identity changes: ratings and a pending collection play belong to the old account.
    func resetAccountState() {
        playTask?.cancel()
        playTask = nil
        rowRatings = [:]
        ratingGeneration += 1
    }

    private static func matches(_ playlistId: String?, _ target: WatchTarget?) -> Bool {
        guard let playlistId, let wanted = target?.playlistId else { return false }
        return playlistId == wanted
    }

    // A playlist-only target has no first track yet; one `next` request finds it. The latest request wins.
    private func playCollection(_ target: WatchTarget?) {
        playTask?.cancel()
        guard let target else {
            toasts.show("Couldn't play this")
            return
        }
        if let videoId = target.videoId {
            act(.load(videoId: videoId, playlistId: target.playlistId))
            return
        }
        playTask = Task { [weak self] in
            guard let self else { return }
            let first = try? await firstVideo(of: target)
            guard !Task.isCancelled else { return }
            guard let first else {
                toasts.show("Couldn't play this")
                return
            }
            act(.load(videoId: first, playlistId: target.playlistId))
        }
    }

    private func firstVideo(of target: WatchTarget) async throws -> String? {
        let credentials = credentials()
        if let resolveFirstVideo { return try await resolveFirstVideo(target, credentials) }
        return try await client?.watchNext(target, credentials: credentials).queue.items.first?.song.videoId
    }

    func loadDetails(for song: SongInfo) async {
        details = nil
        guard let client else { return }
        let target = WatchTarget(videoId: song.videoId, playlistId: song.playlistId)
        guard let next = try? await client.watchNext(target, credentials: credentials()),
              !Task.isCancelled, player.song?.videoId == song.videoId,
              let item = next.queue.items.first(where: { $0.song.videoId == song.videoId })
        else { return }
        details = TrackDetails(videoId: song.videoId, artists: item.song.artists, album: item.song.album, isVideo: item.song.isVideo)
    }
}

extension String {
    fileprivate func removingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}

extension RepeatMode {
    fileprivate init(preference: String) {
        switch preference {
        case "all": self = .all
        case "one": self = .one
        default: self = .off
        }
    }

    fileprivate var preference: String {
        switch self {
        case .off: "off"
        case .all: "all"
        case .one: "one"
        }
    }
}
