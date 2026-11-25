import AppKit
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
    let lyricsBrowseId: String?
    let relatedBrowseId: String?
}

struct QueueChip: Equatable {
    let title: String
    let target: WatchTarget
    let isSelected: Bool
}

struct QueueInfo: Equatable {
    let playingFrom: String?
    let playlistId: String?
    let chips: [QueueChip]
}

struct QueueRef: Equatable {
    let artists: [ItemRef]
    let album: ItemRef?
}

private struct PendingQueueChange {
    let id: Int
    let isApplied: ([PlayerQueueItem]) -> Bool
    let onApplied: @MainActor ([PlayerQueueItem]) -> Void
}

@MainActor @Observable
final class NowPlayingModel {
    enum LikePrompt { case like, dislike }

    let player: any PlayerControlling
    var details: TrackDetails?
    private(set) var detailsFailed = false
    var likePrompt: LikePrompt?
    var timeShowsRemaining = false
    private(set) var rowRatings: [String: Rating] = [:]
    private(set) var queueInfo: QueueInfo?
    private(set) var queueRefs: [String: QueueRef] = [:]

    @ObservationIgnored private let toasts: ToastCenter
    @ObservationIgnored private var resumesOnReconnect = false
    @ObservationIgnored private var lastRecoverAt: ContinuousClock.Instant?
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let credentials: @MainActor () -> Credentials?
    @ObservationIgnored private let client: InnerTubeClient?
    @ObservationIgnored private let fetchNext: (@MainActor (WatchTarget, Credentials?) async throws -> WatchNext)?
    @ObservationIgnored private let resolveQueue: (@MainActor (WatchTarget, Credentials?) async throws -> [String])?
    @ObservationIgnored private let rateVideo: @MainActor (String, Rating, Credentials) async throws -> Void
    @ObservationIgnored private var pendingQueueChange: PendingQueueChange?
    @ObservationIgnored private var pendingQueueTask: Task<Void, Never>?
    @ObservationIgnored private var pendingQueueCounter = 0
    @ObservationIgnored private let now: @MainActor () -> ContinuousClock.Instant
    @ObservationIgnored private var playTask: Task<Void, Never>?
    @ObservationIgnored private var detailsTask: Task<Void, Never>?
    @ObservationIgnored private var lastLoad: (key: String, at: ContinuousClock.Instant)?
    @ObservationIgnored private var ratingGeneration = 0
    @ObservationIgnored private var skip: (videoId: String, task: Task<Void, Never>)?
    @ObservationIgnored private var unavailableStreak = 0
    @ObservationIgnored private var syncsRepeat = false
    @ObservationIgnored private var syncsShuffle = false
    @ObservationIgnored private var hasResumed = false
    /// The position a resumed track is being brought back to; positions are not saved until the player reaches it.
    @ObservationIgnored private var resumeTarget: LastPlayback?
    @ObservationIgnored var albumChanged: (@MainActor (_ videoId: String, _ album: String?) -> Void)?

    init(
        player: any PlayerControlling, toasts: ToastCenter, preferences: Preferences = Preferences(),
        credentials: @escaping @MainActor () -> Credentials?, client: InnerTubeClient? = InnerTubeClient(),
        resolveQueue: (@MainActor (WatchTarget, Credentials?) async throws -> [String])? = nil,
        watchNext: (@MainActor (WatchTarget, Credentials?) async throws -> WatchNext)? = nil,
        rateVideo: (@MainActor (String, Rating, Credentials) async throws -> Void)? = nil,
        now: @escaping @MainActor () -> ContinuousClock.Instant = { .now }
    ) {
        self.now = now
        self.resolveQueue = resolveQueue
        if let watchNext {
            fetchNext = watchNext
        } else if let client {
            fetchNext = { target, credentials in try await client.watchNext(target, credentials: credentials) }
        } else {
            fetchNext = nil
        }
        self.rateVideo = rateVideo ?? { [client] videoId, rating, credentials in
            try await client?.rate(videoId: videoId, rating, credentials: credentials)
        }
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
            rememberTrack(song)
            unavailableStreak = 0
            if skip?.videoId != song.videoId { cancelSkip() }
            // Loaded here rather than from a view, so Now Playing gets the album with every window closed (#82).
            detailsTask?.cancel()
            detailsTask = Task { [weak self] in await self?.loadDetails(for: song) }
        case .stopped:
            detailsTask?.cancel()
            detailsTask = nil
            details = nil
            detailsFailed = false
        case .timeChanged(let elapsed):
            rememberPosition(elapsed, force: false)
        case .playbackChanged(let isPaused, let elapsed):
            if isPaused { rememberPosition(elapsed, force: true) }
        case .queueChanged(let items):
            if let pending = pendingQueueChange, pending.isApplied(items) {
                clearPendingQueueChange()
                pending.onApplied(items)
            }
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

    /// Brings back the last session's track, paused where it was. Only the first player start of a launch does this,
    /// so a restart for another account (#81) does not.
    func resumeLastSession() {
        guard !hasResumed else { return }
        hasResumed = true
        guard preferences.resumeOnStart, player.song == nil, let last = preferences.lastPlayback else { return }
        resumeTarget = last
        player.send(.resume(videoId: last.videoId, playlistId: last.playlistId, at: last.elapsed))
    }

    /// Saves the position as it is now, for quitting.
    func savePosition() {
        rememberPosition(player.elapsed, force: true)
    }

    private func rememberTrack(_ song: SongInfo) {
        if let resumeTarget, resumeTarget.videoId != song.videoId { self.resumeTarget = nil }
        let previous = preferences.lastPlayback
        let elapsed = previous?.videoId == song.videoId ? previous?.elapsed ?? 0 : 0
        preferences.lastPlayback = LastPlayback(videoId: song.videoId, playlistId: song.playlistId, elapsed: elapsed)
    }

    private func rememberPosition(_ elapsed: TimeInterval, force: Bool) {
        guard !player.isAd, elapsed.isFinite, let song = player.song, var last = preferences.lastPlayback,
              last.videoId == song.videoId else { return }
        if let target = resumeTarget {
            // The page starts every load at 0 before the seek lands; saving that would lose the position.
            guard abs(elapsed - target.elapsed) < PlaybackRules.resumeTolerance else { return }
            resumeTarget = nil
        }
        guard force || abs(elapsed - last.elapsed) >= PlaybackRules.positionSaveInterval else { return }
        last.elapsed = elapsed
        preferences.lastPlayback = last
    }

    func togglePlay() { perform(.togglePlay) }
    func previous() { perform(.previous) }
    func next() { perform(.next) }
    func seek(to seconds: TimeInterval) { perform(.seek(to: seconds)) }
    func skip(by seconds: TimeInterval) { perform(.skip(by: seconds)) }

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

    func perform(_ command: PlayerCommand) {
        cancelSkip()
        resumeTarget = nil
        player.send(command)
    }

    func play(_ item: MusicItem) {
        switch item {
        case .song(let song):
            guard song.isAvailable else { return }
            // A row is a plain button, so a double-click would send the load twice.
            let key = song.videoId + (song.playlistId ?? "")
            let instant = now()
            if let lastLoad, lastLoad.key == key, instant - lastLoad.at < .seconds(NSEvent.doubleClickInterval) { return }
            lastLoad = (key, instant)
            perform(.load(videoId: song.videoId, playlistId: song.playlistId))
        case .album(let album):
            play(album.playTarget)
        case .playlist(let playlist):
            play(playlist.playTarget ?? WatchTarget(playlistId: playlist.browseId.removingPrefix("VL")))
        case .artist, .link:
            break
        }
    }

    // shortcut: RDAMVM{videoId} is the community-known radio id, unverified against a fixture; parse watchEndpoint params if radio starts fail.
    func startRadio(_ song: Song) {
        guard song.isAvailable else { return }
        perform(.load(videoId: song.videoId, playlistId: song.playlistId ?? "RDAMVM" + song.videoId))
    }

    func startRadio(_ item: MusicItem) {
        switch item {
        case .song(let song): startRadio(song)
        // shortcut: RDAMPL{playlistId} is the community-known playlist radio id, unverified against a fixture; fetch the page header's radio target if starts fail.
        case .album(let album): play(album.playTarget?.playlistId.map { WatchTarget(playlistId: "RDAMPL" + $0) })
        case .playlist(let playlist): play(WatchTarget(playlistId: "RDAMPL" + playlist.browseId.removingPrefix("VL")))
        case .artist(let artist): playFetched(of: artist.browseId, item: item, radio: true)
        case .link: break
        }
    }

    /// A card has no shuffle target, so one page request finds the header's.
    func shuffle(_ item: MusicItem) {
        switch item {
        case .song, .link: break
        case .album(let album): playFetched(of: album.browseId, item: item, radio: false)
        case .playlist(let playlist): playFetched(of: playlist.browseId, item: item, radio: false)
        case .artist(let artist): playFetched(of: artist.browseId, item: item, radio: false)
        }
    }

    private func playFetched(of browseId: String, item: MusicItem, radio: Bool) {
        playTask?.cancel()
        playTask = Task { [weak self] in
            guard let self, let client else { return }
            let credentials = credentials()
            let target = BrowseTarget(browseId: browseId)
            let resolved: WatchTarget?
            switch item {
            case .artist:
                let page = try? await client.artist(target, credentials: credentials)
                resolved = radio ? page?.radio : page?.shuffle
            case .album:
                let header = try? await client.album(target, credentials: credentials).header
                resolved = radio ? header?.radio : header?.shuffle ?? header?.play
            default:
                let header = try? await client.playlist(target, credentials: credentials).header
                resolved = radio ? header?.radio : header?.shuffle ?? header?.play
            }
            guard !Task.isCancelled else { return }
            play(resolved)
        }
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

    /// Playback that was running when the network dropped is reloaded where it was once the network is back.
    func networkChanged(isOnline: Bool) {
        if !isOnline {
            resumesOnReconnect = player.song != nil && !player.isPaused
        } else if resumesOnReconnect {
            resumesOnReconnect = false
            let instant = now()
            guard !player.isPaused, lastRecoverAt.map({ instant - $0 >= .seconds(30) }) ?? true else { return }
            lastRecoverAt = instant
            player.send(.recover)
        }
    }

    /// Called when the content identity changes: ratings and a pending collection play belong to the old account.
    func resetAccountState() {
        playTask?.cancel()
        playTask = nil
        resumesOnReconnect = false
        rowRatings = [:]
        queueInfo = nil
        queueRefs = [:]
        clearPendingQueueChange()
        ratingGeneration += 1
    }

    /// The mirrored queue as rows. A row's `playlistSetVideoId` is `q<index>`, so a repeated video still selects as one row.
    var queueSongs: [Song] {
        player.queue.enumerated().map { index, item in
            let ref = queueRefs[item.videoId]
            let seconds = Int(item.duration)
            return Song(
                videoId: item.videoId, title: item.title, artists: ref?.artists ?? [ItemRef(name: item.artist, browseId: nil)],
                album: ref?.album, duration: "\(seconds / 60):" + String(format: "%02d", seconds % 60), thumbnailURL: item.artworkURL,
                playlistSetVideoId: Self.queueKey(index))
        }
    }

    static func queueKey(_ index: Int) -> String { "q\(index)" }
    static func queueIndex(of key: String) -> Int? { key.hasPrefix("q") ? Int(key.dropFirst()) : nil }

    func removeQueueItems(at indexes: [Int]) {
        if indexes.count == 1, let index = indexes.first { return removeQueueItem(at: index) }
        let queue = player.queue
        let valid = Set(indexes).filter { queue.indices.contains($0) && !queue[$0].isCurrent }.sorted(by: >)
        guard canEditQueue, !valid.isEmpty else { return }
        let before = queue.count
        expectQueueChange(isApplied: { $0.count == before - valid.count }) { [weak self] _ in
            self?.toasts.show("Removed \(valid.count) songs")
        }
        for index in valid { player.send(.removeQueueItem(index: index)) }
    }

    var canEditQueue: Bool { player.isReady && !player.isAd }

    func jump(to index: Int) {
        guard canEditQueue else { return }
        perform(.playQueueItem(index: index))
    }

    func enqueue(_ videoIds: [String], playNext: Bool) {
        guard canEditQueue, !videoIds.isEmpty else { return }
        let before = player.queue.count
        let count = videoIds.count
        expectQueueChange(isApplied: { $0.count == before + count }) { [weak self] _ in
            self?.toasts.show(playNext ? "Playing next" : "Added to queue", undo: { self?.undoEnqueue(videoIds, playNext: playNext) })
        }
        perform(.enqueue(videoIds: videoIds, playNext: playNext))
    }

    func enqueue(_ item: MusicItem, playNext: Bool) {
        switch item {
        case .song(let song):
            guard song.isAvailable else { return }
            enqueue([song.videoId], playNext: playNext)
        case .album(let album):
            enqueueCollection(album.playTarget, playNext: playNext)
        case .playlist(let playlist):
            enqueueCollection(playlist.playTarget ?? WatchTarget(playlistId: playlist.browseId.removingPrefix("VL")), playNext: playNext)
        case .artist, .link:
            break
        }
    }

    // shortcut: only the first `next` page (about 25-50 ids) is queued; fetch every page to queue a whole playlist.
    func enqueue(_ drag: TrackDrag, playNext: Bool) {
        if !drag.videoIds.isEmpty {
            enqueue(drag.videoIds, playNext: playNext)
        } else if let id = drag.playlistId {
            enqueueCollection(WatchTarget(playlistId: id), playNext: playNext)
        }
    }

    private func enqueueCollection(_ target: WatchTarget?, playNext: Bool) {
        guard let target else {
            toasts.show("Couldn't add to the queue")
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let captured = ratingGeneration
            let ids = try? await queueIds(of: target, credentials: credentials())
            guard ratingGeneration == captured else { return }
            guard let ids, !ids.isEmpty else {
                toasts.show("Couldn't add to the queue")
                return
            }
            enqueue(Array(ids.prefix(PlaybackRules.maxEnqueueBatch)), playNext: playNext)
        }
    }

    private func undoEnqueue(_ videoIds: [String], playNext: Bool) {
        let queue = player.queue
        let start: Int
        if playNext {
            guard let current = queue.firstIndex(where: \.isCurrent) else { return }
            start = current + 1
        } else {
            start = queue.count - videoIds.count
        }
        let range = start..<(start + videoIds.count)
        guard start >= 0, range.upperBound <= queue.count else { return }
        for index in range.reversed() where queue[index].videoId == videoIds[index - start] {
            player.send(.removeQueueItem(index: index))
        }
    }

    func removeQueueItem(at index: Int) {
        guard canEditQueue, player.queue.indices.contains(index), !player.queue[index].isCurrent else { return }
        let removed = player.queue[index]
        let before = player.queue.count
        expectQueueChange(isApplied: { $0.count == before - 1 }) { [weak self] _ in
            self?.toasts.show("Removed from queue", undo: { self?.undoRemove(removed.videoId, from: index) })
        }
        player.send(.removeQueueItem(index: index))
    }

    // The page has no insert-at-index, so Undo appends the track and moves it back once the append is confirmed.
    private func undoRemove(_ videoId: String, from index: Int) {
        let before = player.queue.count
        expectQueueChange(isApplied: { $0.count == before + 1 && $0.last?.videoId == videoId }) { [weak self] items in
            guard index < items.count - 1 else { return }
            self?.player.send(.moveQueueItem(from: items.count - 1, to: index))
        }
        player.send(.enqueue(videoIds: [videoId], playNext: false))
    }

    func moveQueueItem(from: Int, to: Int) {
        let queue = player.queue
        guard canEditQueue, from != to, queue.indices.contains(from), queue.indices.contains(to) else { return }
        let moved = queue[from]
        expectQueueChange(isApplied: { $0.indices.contains(to) && $0[to].videoId == moved.videoId && $0 != queue }) { [weak self] _ in
            self?.toasts.show("Moved in queue", undo: { self?.player.send(.moveQueueItem(from: to, to: from)) })
        }
        player.send(.moveQueueItem(from: from, to: to))
    }

    func playNext(queueIndex index: Int) {
        let queue = player.queue
        guard let current = queue.firstIndex(where: \.isCurrent), index != current else { return }
        let target = index > current ? current + 1 : current
        guard target != index else { return }
        moveQueueItem(from: index, to: target)
    }

    func selectChip(_ chip: QueueChip) {
        guard canEditQueue, let videoId = player.song?.videoId else { return }
        perform(.load(videoId: videoId, playlistId: chip.target.playlistId))
    }

    private func expectQueueChange(
        isApplied: @escaping ([PlayerQueueItem]) -> Bool, onApplied: @escaping @MainActor ([PlayerQueueItem]) -> Void
    ) {
        clearPendingQueueChange()
        pendingQueueCounter += 1
        let id = pendingQueueCounter
        pendingQueueChange = PendingQueueChange(id: id, isApplied: isApplied, onApplied: onApplied)
        pendingQueueTask = Task { [weak self] in
            try? await Task.sleep(for: Motion.toastDuration)
            guard !Task.isCancelled, self?.pendingQueueChange?.id == id else { return }
            self?.pendingQueueChange = nil
        }
    }

    private func clearPendingQueueChange() {
        pendingQueueTask?.cancel()
        pendingQueueTask = nil
        pendingQueueChange = nil
    }

    /// Sequential on purpose: the service rate-limits bursts, and an identity change must stop the loop.
    /// Credentials and generation are captured before the ids resolve: paging a long playlist can outlive an account switch.
    func rateAll(_ rating: Rating, ids: @escaping @MainActor () async -> [String]) {
        guard let credentials = credentials() else { return }
        let captured = ratingGeneration
        Task { [weak self] in
            let videoIds = await ids()
            guard self?.ratingGeneration == captured else { return }
            var done = 0
            for videoId in videoIds {
                guard let self, ratingGeneration == captured else { return }
                do {
                    try await rateVideo(videoId, rating, credentials)
                    guard ratingGeneration == captured else { return }
                    rowRatings[videoId] = rating
                    done += 1
                } catch {
                    continue
                }
            }
            guard let self, ratingGeneration == captured else { return }
            let total = videoIds.count
            switch (rating, done == total) {
            case (.like, true): toasts.show("Liked \(done) songs")
            case (.like, false): toasts.show("Liked \(done) of \(total) songs")
            case (_, true): toasts.show("Disliked \(done) songs")
            case (_, false): toasts.show("Disliked \(done) of \(total) songs")
            }
        }
    }

    private static func matches(_ playlistId: String?, _ target: WatchTarget?) -> Bool {
        guard let playlistId, let wanted = target?.playlistId else { return false }
        return playlistId == wanted
    }

    // A playlist-only target has no first track yet; one `next` request finds it. The latest request wins.
    func play(_ target: WatchTarget?) {
        playTask?.cancel()
        guard let target else {
            toasts.show("Couldn't play this")
            return
        }
        if let videoId = target.videoId {
            perform(.load(videoId: videoId, playlistId: target.playlistId))
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
            perform(.load(videoId: first, playlistId: target.playlistId))
        }
    }

    private func firstVideo(of target: WatchTarget) async throws -> String? {
        let credentials = credentials()
        return try await queueIds(of: target, credentials: credentials).first
    }

    private func queueIds(of target: WatchTarget, credentials: Credentials?) async throws -> [String] {
        if let resolveQueue { return try await resolveQueue(target, credentials) }
        return try await client?.watchNext(target, credentials: credentials).queue.items.map(\.song.videoId) ?? []
    }

    func loadDetails(for song: SongInfo) async {
        details = nil
        detailsFailed = false
        queueInfo = nil
        guard let fetchNext else { return }
        let target = WatchTarget(videoId: song.videoId, playlistId: song.playlistId)
        let next: WatchNext
        do {
            next = try await fetchNext(target, credentials())
        } catch {
            if !Task.isCancelled, player.song?.videoId == song.videoId { detailsFailed = true }
            return
        }
        guard !Task.isCancelled, player.song?.videoId == song.videoId else { return }
        guard let item = next.queue.items.first(where: { $0.song.videoId == song.videoId }) else {
            detailsFailed = true
            return
        }
        details = TrackDetails(
            videoId: song.videoId, artists: item.song.artists, album: item.song.album, isVideo: item.song.isVideo,
            lyricsBrowseId: next.lyricsBrowseId, relatedBrowseId: next.relatedBrowseId)
        albumChanged?(song.videoId, item.song.album?.name)
        queueInfo = QueueInfo(
            playingFrom: next.playingFrom, playlistId: next.playlistId,
            chips: next.chips.compactMap { chip in
                chip.watchTarget.map { QueueChip(title: chip.title, target: $0, isSelected: chip.isSelected) }
            })
        for entry in next.queue.items {
            queueRefs[entry.song.videoId] = QueueRef(artists: entry.song.artists, album: entry.song.album)
        }
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
