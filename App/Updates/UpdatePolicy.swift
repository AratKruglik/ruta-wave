/// Update decisions kept free of Sparkle so the unit tests can cover them.
enum UpdateChannel: String, CaseIterable, Sendable {
    case stable, beta

    /// Until the user picks a channel, a build with a pre-release suffix (`0.2.0-beta.1`) follows betas.
    init(stored: String?, runningVersion: String) {
        self = stored.flatMap(Self.init(rawValue:)) ?? (runningVersion.contains("-") ? .beta : .stable)
    }

    /// Sparkle offers items without a channel to everyone, so stable needs no channel of its own.
    var sparkleChannels: Set<String> { self == .beta ? ["beta"] : [] }
}

enum UpdateReminder {
    /// Sparkle's window is enough while the app has focus. Otherwise a notification asks for attention instead,
    /// unless the user switched those off, in which case Sparkle shows its window as it would by default.
    static func sparkleShowsScheduledUpdate(immediateFocus: Bool, notificationsEnabled: Bool) -> Bool {
        immediateFocus || !notificationsEnabled
    }
}
