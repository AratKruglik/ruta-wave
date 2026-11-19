import Foundation
import os

final class ClientVersion: Sendable {
    static let builtIn = "1.20261115.14.00"
    static let shared = ClientVersion(defaults: .standard)
    private static let key = "innerTubeClientVersion"

    // UserDefaults is thread-safe but not declared Sendable by the SDK.
    nonisolated(unsafe) private let defaults: UserDefaults
    private let lock: OSAllocatedUnfairLock<String>

    init(defaults: UserDefaults) {
        self.defaults = defaults
        lock = OSAllocatedUnfairLock(initialState: Self.validated(defaults.string(forKey: Self.key)) ?? Self.builtIn)
    }

    var current: String {
        lock.withLock { $0 }
    }

    func accept(_ raw: String?) {
        guard let value = Self.validated(raw) else { return }
        lock.withLock { $0 = value }
        defaults.set(value, forKey: Self.key)
    }

    static func validated(_ raw: String?) -> String? {
        guard let raw, raw.count <= 32 else { return nil }
        return raw.wholeMatch(of: /[0-9]+\.[0-9]{8}\.[0-9]{2}\.[0-9]{2}/) == nil ? nil : raw
    }

    static func extract(fromPage html: String) -> String? {
        guard let match = html.firstMatch(of: /"INNERTUBE_CLIENT_VERSION":"([^"]{1,64})"/) else { return nil }
        return validated(String(match.1))
    }
}
