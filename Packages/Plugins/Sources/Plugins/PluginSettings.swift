import Foundation

/// A plugin's slice of `UserDefaults`: every key lives under `plugins.<id>.`. UserDefaults is thread-safe but not `Sendable`.
public struct PluginSettings: @unchecked Sendable {
    private let id: String
    private let defaults: UserDefaults

    public init(id: String, defaults: UserDefaults = .standard) {
        self.id = id
        self.defaults = defaults
    }

    public func isEnabled(default isEnabledByDefault: Bool) -> Bool {
        self["enabled"] as? Bool ?? isEnabledByDefault
    }

    public func setEnabled(_ isEnabled: Bool) {
        self["enabled"] = isEnabled
    }

    public subscript(key: String) -> Any? {
        get { defaults.object(forKey: "plugins.\(id).\(key)") }
        nonmutating set { defaults.set(newValue, forKey: "plugins.\(id).\(key)") }
    }
}
