import Foundation

public enum PlayerRules {
    static let playerHost = "music.youtube.com"
    static let maxReloadAttempts = 2
    static let playerTimeout: Duration = .seconds(15)
    // A failed load fails again within milliseconds while offline; the pause gives a short outage time to clear.
    static let failedLoadRetryDelay: Duration = .seconds(5)
    // Playback this long after a commit ends a failure streak; a track that crashes sooner keeps counting toward the cap.
    static let stablePlayback: Duration = .seconds(30)
    static let maxQueueItems = 500
    static let maxQueueOffset = 100_000
    // shortcut: one get_queue request for the whole restored tail; split it if the endpoint caps the id count.
    static let maxRestoredQueueItems = 200

    private static let allowedArtworkHostSuffixes = [".googleusercontent.com", ".ggpht.com"]

    /// A running player is kept only for the same mode and, when signed in, the same account.
    static func reusesPlayer(running: (ephemeral: Bool, authUserIndex: Int), wanted: (ephemeral: Bool, authUserIndex: Int)) -> Bool {
        running.ephemeral == wanted.ephemeral && (wanted.ephemeral || running.authUserIndex == wanted.authUserIndex)
    }

    static func isAllowedMainFrameNavigation(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", url.host?.lowercased() == playerHost,
              url.user == nil, url.password == nil else { return false }
        return url.port == nil || url.port == 443
    }

    static func isTrustedMessage(isMainFrame: Bool, scheme: String, host: String, port: Int) -> Bool {
        isMainFrame && scheme == "https" && host.lowercased() == playerHost && (port == 0 || port == 443)
    }

    static func isValidID(_ id: String) -> Bool {
        (1...64).contains(id.count) && id.utf8.allSatisfy { $0.isASCIIIDCharacter }
    }

    static func watchURL(videoId: String, playlistId: String? = nil) -> URL? {
        guard isValidID(videoId), playlistId.map(isValidID) ?? true else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = playerHost
        components.path = "/watch"
        components.queryItems = [URLQueryItem(name: "v", value: videoId)]
        if let playlistId { components.queryItems?.append(URLQueryItem(name: "list", value: playlistId)) }
        return components.url
    }

    /// `authUserIndex` is nil for a guest. The site ignores `authuser` on `/watch` and keeps the last account it
    /// switched to, so signed-in playback always goes through `/signin`, the site's own account switch, even for index 0.
    static func loadURL(videoId: String, playlistId: String?, authUserIndex: Int?) -> URL? {
        guard let watch = watchURL(videoId: videoId, playlistId: playlistId) else { return nil }
        guard let authUserIndex else { return watch }
        guard authUserIndex >= 0, let query = watch.query else { return nil }
        var valueAllowed = CharacterSet.urlQueryAllowed
        valueAllowed.remove(charactersIn: "&=?+")
        guard let next = "/watch?\(query)".addingPercentEncoding(withAllowedCharacters: valueAllowed) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = playerHost
        components.path = "/signin"
        components.percentEncodedQuery = "action_handle_signin=true&authuser=\(authUserIndex)&next=\(next)"
        return components.url
    }

    /// "m:ss" or "h:mm:ss" as the page prints `lengthText`.
    static func parseDuration(_ text: String) -> TimeInterval? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0
        for part in parts {
            guard part.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
                  let value = Int(part), value < 100_000 else { return nil }
            total = total * 60 + value
        }
        return TimeInterval(total)
    }

    public static func isRefusedDuringAd(_ command: PlayerCommand) -> Bool {
        switch command {
        case .next, .seek(to: _), .skip(by: _): true
        default: false
        }
    }

    /// -999 and WebKit 102 come from a superseding `load` or the navigation lock, not from a failed page.
    static func isIgnorableNavigationError(_ error: NSError) -> Bool {
        (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || (error.domain == "WebKitErrorDomain" && error.code == 102)
    }

    /// The named page operation for a command, or nil when the command is not a page operation or is refused.
    /// A queue index travels with the identity of the row it was read from, so the page can refuse a stale index.
    /// `offset` is the page index of `queue[0]`, so a window into a long page queue still addresses the right row.
    static func bridgeCall(for command: PlayerCommand, queue: [QueueItem], offset: Int = 0) -> (action: String, args: [Any])? {
        func row(_ index: Int) -> [Any]? {
            guard queue.indices.contains(index) else { return nil }
            return [offset + index, queue[index].videoId, queue[index].playlistSetVideoId ?? NSNull()]
        }
        switch command {
        case .play: return ("play", [])
        case .pause: return ("pause", [])
        case .togglePlay: return ("togglePlay", [])
        case .next: return ("next", [])
        case .previous: return ("previous", [])
        case .seek(to: let time):
            return time.isFinite && time >= 0 ? ("seekTo", [time]) : nil
        case .skip(by: let delta):
            return delta.isFinite ? ("seekBy", [delta]) : nil
        case .setVolume(let volume):
            return volume.isFinite ? ("setVolume", [(min(max(volume, 0), 1) * 100).rounded()]) : nil
        case .toggleMute: return ("toggleMute", [])
        case .toggleShuffle: return ("toggleShuffle", [])
        case .cycleRepeat: return ("cycleRepeat", [])
        case .playQueueItem(let index):
            return row(index).map { ("jump", $0) }
        case .enqueue(let videoIds, let playNext):
            guard !videoIds.isEmpty, videoIds.count <= maxRestoredQueueItems, videoIds.allSatisfy(isValidID) else { return nil }
            return ("enqueue", [videoIds, playNext])
        case .removeQueueItem(let index):
            guard !queue.indices.contains(index) || !queue[index].isCurrent else { return nil }
            return row(index).map { ("remove", $0) }
        case .moveQueueItem(let from, let to):
            guard queue.indices.contains(to), let args = row(from) else { return nil }
            return ("move", args + [offset + to])
        case .setLike, .load, .resume, .recover: return nil
        }
    }

    /// The rows after the current one, which a reload would replace with the page's own queue.
    static func upcomingVideoIds(_ queue: [QueueItem]) -> [String] {
        guard let current = queue.firstIndex(where: \.isCurrent) else { return [] }
        return Array(queue[(current + 1)...].prefix(maxRestoredQueueItems).map(\.videoId))
    }

    /// A message from the isolated Now Playing script; anything else is dropped.
    static func remoteCommand(from body: Any) -> PlayerCommand? {
        guard let message = body as? [String: Any], let action = message["action"] as? String else { return nil }
        switch action {
        case "play": return .play
        case "pause": return .pause
        case "nexttrack": return .next
        case "previoustrack": return .previous
        case "seekto":
            guard let time = message["time"] as? Double, time.isFinite, time >= 0 else { return nil }
            return .seek(to: time)
        default: return nil
        }
    }

    /// Arguments for `__nowPlaying.update(info)`; artwork off the allowlist is left out so WebKit never fetches it.
    static func nowPlayingArguments(_ info: NowPlayingInfo?) -> [String: Any] {
        guard let info else { return ["info": NSNull()] }
        var fields: [String: Any] = [
            "title": info.title, "artist": info.artist, "duration": info.duration, "elapsed": info.elapsed,
            "playing": info.isPlaying,
        ]
        if let album = info.album { fields["album"] = album }
        if let url = info.artworkURL, isAllowedArtworkHost(url) { fields["artwork"] = url.absoluteString }
        return ["info": fields]
    }

    public static func isAllowedArtworkHost(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "i.ytimg.com" || allowedArtworkHostSuffixes.contains { host.hasSuffix($0) }
    }

    static func resolveArtwork(stripped: URL?, original: URL?, isReachable: @Sendable (URL) async -> Bool) async -> URL? {
        guard let stripped else { return original }
        return await isReachable(stripped) ? stripped : original
    }
}

private extension UInt8 {
    var isASCIIIDCharacter: Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(self)
            || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(self)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(self)
            || self == UInt8(ascii: "_") || self == UInt8(ascii: "-")
    }
}
