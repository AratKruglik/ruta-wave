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
    }
}
