import AppKit
import AppSettings
import Sparkle
import UserNotifications

/// Owns Sparkle's updater. Created only when the build carries a feed URL and a public key.
@MainActor @Observable
final class UpdateController: NSObject {
    nonisolated static let notificationCategory = "update"
    private static let notificationId = "update-available"

    private(set) var canCheckForUpdates = false
    private(set) var lastUpdateCheckDate: Date?

    var channel: UpdateChannel {
        didSet {
            guard channel != oldValue else { return }
            preferences.updateChannel = channel.rawValue
            updater.resetUpdateCycle()
            // Without this a new beta would wait for the next scheduled check, up to a day.
            if channel == .beta { updater.checkForUpdatesInBackground() }
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { updater.automaticallyDownloadsUpdates = newValue }
    }

    @ObservationIgnored private let preferences = Preferences()
    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    private var updater: SPUUpdater { controller.updater }

    override init() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        channel = UpdateChannel(stored: Preferences().updateChannel, runningVersion: version)
        super.init()
        // Sparkle holds both delegates weakly; this object owns the controller, so they live as long as it does.
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        lastUpdateCheckDate = updater.lastUpdateCheckDate
        canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    private func remindWithNotification(version: String) async {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            status = (try? await center.requestAuthorization(options: [.alert])) == true ? .authorized : .denied
        }
        guard status != .denied else {
            // With no way to notify, fall back to what Sparkle does by default and show its window.
            checkForUpdates()
            return
        }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "RutaWave \(version) is available")
        content.body = String(localized: "Click to see what's new and install it.")
        content.categoryIdentifier = Self.notificationCategory
        try? await center.add(UNNotificationRequest(identifier: Self.notificationId, content: content, trigger: nil))
    }

    private func removeReminder() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.notificationId])
    }
}

extension UpdateController: SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        channel.sparkleChannels
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        lastUpdateCheckDate = updater.lastUpdateCheckDate
    }
}

// Sparkle calls the user driver delegate on the main thread but does not annotate the protocol.
extension UpdateController: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        UpdateReminder.sparkleShowsScheduledUpdate(
            immediateFocus: immediateFocus, notificationsEnabled: preferences.updateNotifications)
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        let version = update.displayVersionString
        Task { await remindWithNotification(version: version) }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        removeReminder()
    }

    func standardUserDriverWillFinishUpdateSession() {
        removeReminder()
    }
}
