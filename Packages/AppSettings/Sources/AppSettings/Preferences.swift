import Foundation

/// UserDefaults is thread-safe but not `Sendable`; this struct only reads and writes it.
public struct Preferences: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var sidebarCollapsed: Bool {
        get { defaults.bool(forKey: Key.sidebarCollapsed) }
        nonmutating set { defaults.set(newValue, forKey: Key.sidebarCollapsed) }
    }

    /// 0…1.
    public var volume: Double {
        get { defaults.object(forKey: Key.volume) == nil ? 1 : min(max(defaults.double(forKey: Key.volume), 0), 1) }
        nonmutating set { defaults.set(min(max(newValue, 0), 1), forKey: Key.volume) }
    }

    /// `off`, `all` or `one`. AppSettings is a leaf package, so it cannot use the player's `RepeatMode`.
    public var repeatMode: String {
        get { defaults.string(forKey: Key.repeatMode).flatMap { Self.repeatModes.contains($0) ? $0 : nil } ?? "off" }
        nonmutating set { if Self.repeatModes.contains(newValue) { defaults.set(newValue, forKey: Key.repeatMode) } }
    }

    public var shuffle: Bool {
        get { defaults.bool(forKey: Key.shuffle) }
        nonmutating set { defaults.set(newValue, forKey: Key.shuffle) }
    }

    /// `nil` follows the system language. `AppleLanguages` is mirrored because macOS reads it at launch, and the merged
    /// global value cannot tell "system" from an explicit choice, so `appLanguage` stays the source of truth.
    public var appLanguage: String? {
        get { defaults.string(forKey: Key.appLanguage) }
        nonmutating set {
            if let newValue {
                defaults.set(newValue, forKey: Key.appLanguage)
                defaults.set([newValue], forKey: Key.appleLanguages)
            } else {
                defaults.removeObject(forKey: Key.appLanguage)
                defaults.removeObject(forKey: Key.appleLanguages)
            }
        }
    }

    /// An explicit chart country pick (ISO alpha-2 or `ZZ`); `nil` follows the system region. Anything but 1…8 uppercase ASCII letters is refused.
    public var chartCountry: String? {
        get { defaults.string(forKey: Key.chartCountry).flatMap(Self.isCountryCode) }
        nonmutating set {
            if let newValue {
                if Self.isCountryCode(newValue) != nil { defaults.set(newValue, forKey: Key.chartCountry) }
            } else {
                defaults.removeObject(forKey: Key.chartCountry)
            }
        }
    }

    /// The last Library section's browse id; anything but an `FEmusic_` id is refused.
    public var librarySection: String? {
        get { defaults.string(forKey: Key.librarySection).flatMap(Self.isLibrarySection) }
        nonmutating set {
            if let newValue {
                if Self.isLibrarySection(newValue) != nil { defaults.set(newValue, forKey: Key.librarySection) }
            } else {
                defaults.removeObject(forKey: Key.librarySection)
            }
        }
    }

    /// An opaque navigation snapshot, owned and validated by the app. Anything over `maxNavigationStateBytes` is removed.
    public var navigationState: Data? {
        get { defaults.data(forKey: Key.navigationState).flatMap { $0.count <= Self.maxNavigationStateBytes ? $0 : nil } }
        nonmutating set {
            if let newValue, newValue.count <= Self.maxNavigationStateBytes {
                defaults.set(newValue, forKey: Key.navigationState)
            } else {
                defaults.removeObject(forKey: Key.navigationState)
            }
        }
    }

    /// Tints the window with the playing track's artwork. On unless switched off.
    public var useArtworkColors: Bool {
        get { defaults.object(forKey: Key.useArtworkColors) == nil ? true : defaults.bool(forKey: Key.useArtworkColors) }
        nonmutating set { defaults.set(newValue, forKey: Key.useArtworkColors) }
    }

    /// Brings back the last track, paused where it was, at launch. On unless switched off.
    public var resumeOnStart: Bool {
        get { defaults.object(forKey: Key.resumeOnStart) == nil ? true : defaults.bool(forKey: Key.resumeOnStart) }
        nonmutating set { defaults.set(newValue, forKey: Key.resumeOnStart) }
    }

    /// The track that was playing when the app last ran. The playlist id can be the account's own (`LM`, a private `PL…`),
    /// so this is cleared whenever the signed-in account changes.
    public var lastPlayback: LastPlayback? {
        get {
            guard let videoId = defaults.string(forKey: Key.lastVideoId).flatMap(Self.isPlayerId) else { return nil }
            let elapsed = defaults.double(forKey: Key.lastElapsed)
            return LastPlayback(
                videoId: videoId, playlistId: defaults.string(forKey: Key.lastPlaylistId).flatMap(Self.isPlayerId),
                elapsed: elapsed.isFinite && elapsed > 0 ? elapsed : 0)
        }
        nonmutating set {
            guard let newValue, Self.isPlayerId(newValue.videoId) != nil else {
                for key in [Key.lastVideoId, Key.lastPlaylistId, Key.lastElapsed] { defaults.removeObject(forKey: key) }
                return
            }
            defaults.set(newValue.videoId, forKey: Key.lastVideoId)
            if let playlistId = newValue.playlistId.flatMap(Self.isPlayerId) {
                defaults.set(playlistId, forKey: Key.lastPlaylistId)
            } else {
                defaults.removeObject(forKey: Key.lastPlaylistId)
            }
            defaults.set(newValue.elapsed.isFinite ? max(newValue.elapsed, 0) : 0, forKey: Key.lastElapsed)
        }
    }

    /// The sidebar section the window opens on: `home`, `explore` or `library`. `nil` (the default) reopens the last one.
    public var startingPage: String? {
        get { defaults.string(forKey: Key.startingPage).flatMap { Self.startingPages.contains($0) ? $0 : nil } }
        nonmutating set {
            if let newValue {
                if Self.startingPages.contains(newValue) { defaults.set(newValue, forKey: Key.startingPage) }
            } else {
                defaults.removeObject(forKey: Key.startingPage)
            }
        }
    }

    /// Keeps the main window above other apps' windows.
    public var alwaysOnTop: Bool {
        get { defaults.bool(forKey: Key.alwaysOnTop) }
        nonmutating set { defaults.set(newValue, forKey: Key.alwaysOnTop) }
    }

    /// Shows the dislike button in the player bar. On unless switched off.
    public var showDislikeButton: Bool {
        get { defaults.object(forKey: Key.showDislikeButton) == nil ? true : defaults.bool(forKey: Key.showDislikeButton) }
        nonmutating set { defaults.set(newValue, forKey: Key.showDislikeButton) }
    }

    public static let maxNavigationStateBytes = 64 * 1024
    public static let startingPages: [String] = ["home", "explore", "library"]

    /// A sort option's label (or a local id), never the opaque request params.
    public func librarySort(for section: String) -> String? {
        (defaults.dictionary(forKey: Key.librarySorts) as? [String: String])?[section]
    }

    public func setLibrarySort(_ sort: String?, for section: String) {
        guard Self.isLibrarySection(section) != nil else { return }
        var sorts = defaults.dictionary(forKey: Key.librarySorts) as? [String: String] ?? [:]
        sorts[section] = sort
        defaults.set(sorts, forKey: Key.librarySorts)
    }

    private static func isLibrarySection(_ value: String) -> String? {
        value.hasPrefix("FEmusic_") ? value : nil
    }

    private static func isCountryCode(_ value: String) -> String? {
        (1...8).contains(value.count) && value.allSatisfy { $0.isASCII && $0.isUppercase && $0.isLetter } ? value : nil
    }

    /// The player's own id rule: 1…64 ASCII letters, digits, `-` and `_`.
    private static func isPlayerId(_ value: String) -> String? {
        (1...64).contains(value.count) && value.allSatisfy(isIdCharacter) ? value : nil
    }

    private static func isIdCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
    }

    private static let repeatModes: Set<String> = ["off", "all", "one"]

    private enum Key {
        static let sidebarCollapsed = "sidebarCollapsed"
        static let volume = "volume"
        static let repeatMode = "repeatMode"
        static let shuffle = "shuffle"
        static let chartCountry = "chartCountry"
        static let librarySection = "librarySection"
        static let librarySorts = "librarySorts"
        static let appLanguage = "appLanguage"
        static let appleLanguages = "AppleLanguages"
        static let navigationState = "navigationState"
        static let useArtworkColors = "useArtworkColors"
        static let resumeOnStart = "resumeOnStart"
        static let lastVideoId = "lastVideoId"
        static let lastPlaylistId = "lastPlaylistId"
        static let lastElapsed = "lastElapsed"
        static let startingPage = "startingPage"
        static let alwaysOnTop = "alwaysOnTop"
        static let showDislikeButton = "showDislikeButton"
    }
}

public struct LastPlayback: Sendable, Equatable {
    public var videoId: String
    public var playlistId: String?
    /// Seconds into the track.
    public var elapsed: TimeInterval

    public init(videoId: String, playlistId: String?, elapsed: TimeInterval) {
        self.videoId = videoId
        self.playlistId = playlistId
        self.elapsed = elapsed
    }
}
