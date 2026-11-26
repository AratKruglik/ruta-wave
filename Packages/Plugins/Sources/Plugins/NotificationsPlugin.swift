import Foundation
import PlayerEngine
import SystemKit

/// Posts a notification when the track changes.
@MainActor
public final class NotificationsPlugin: Plugin {
    public static let id = "notifications"
    public static let title: LocalizedStringResource = "Notifications"
    public static let isEnabledByDefault = true

    private let posting: any NotificationPosting
    private let isFrontmost: @MainActor () -> Bool
    private let loadArtwork: @Sendable (URL) async -> URL?
    private var restoredVideoId: String?
    private var notifier: TrackNotifier?
    private var runTask: Task<Void, Never>?

    public init(
        posting: any NotificationPosting,
        isFrontmost: @escaping @MainActor () -> Bool,
        loadArtwork: @escaping @Sendable (URL) async -> URL? = TrackNotifier.downloadArtwork
    ) {
        self.posting = posting
        self.isFrontmost = isFrontmost
        self.loadArtwork = loadArtwork
    }

    /// The track restored at launch counts as already announced, once. The player has no song yet when the plugin starts at launch.
    public func skipRestored(videoId: String) {
        restoredVideoId = videoId
    }

    public func start(context: PluginContext) async throws {
        let settings = context.settings
        let notifier = TrackNotifier(
            posting: posting, isEnabled: { settings.isEnabled(default: Self.isEnabledByDefault) },
            isFrontmost: isFrontmost, loadArtwork: loadArtwork)
        if let videoId = context.player.song?.videoId ?? restoredVideoId { notifier.skipRestored(videoId: videoId) }
        restoredVideoId = nil
        if context.player.isAd { notifier.markAdPlaying() }
        self.notifier = notifier
        let events = context.events
        runTask = Task { await notifier.run(events) }
    }

    public func stop() async {
        runTask?.cancel()
        await runTask?.value
        notifier?.cancel()
        runTask = nil
        notifier = nil
    }

    /// Moves the pre-plugin `trackNotifications` flag to `plugins.notifications.enabled`, without overwriting a newer value.
    public static func migrateLegacySetting(in defaults: UserDefaults = .standard) {
        let legacyKey = "trackNotifications"
        guard let legacy = defaults.object(forKey: legacyKey) as? Bool else { return }
        let settings = PluginSettings(id: id, defaults: defaults)
        if settings["enabled"] == nil { settings.setEnabled(legacy) }
        defaults.removeObject(forKey: legacyKey)
    }
}
