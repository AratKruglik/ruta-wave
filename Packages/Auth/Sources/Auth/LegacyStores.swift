import Foundation

public enum LegacyStores {
    static let legacyIDs = ["dev.kruhlyk.tunewave", "dev.kruhlyk.redwave"]

    // Runs on every launch until nothing is left: a denied Keychain prompt or a still-running old build must not leave Google cookies behind.
    public static func remove() {
        remove(
            library: FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0],
            keychains: legacyIDs.map { KeychainItem(service: $0 + ".session", account: "default") }
        )
        for id in legacyIDs { UserDefaults.standard.removePersistentDomain(forName: id) }
    }

    static func remove(library: URL, keychains: [any KeychainStore]) {
        for path in paths {
            try? FileManager.default.removeItem(at: library.appendingPathComponent(path))
        }
        let storages = library.appendingPathComponent("HTTPStorages")
        for name in (try? FileManager.default.contentsOfDirectory(atPath: storages.path)) ?? []
        where legacyIDs.contains(where: { name.hasPrefix($0 + ".binarycookies_tmp_") }) {
            try? FileManager.default.removeItem(at: storages.appendingPathComponent(name))
        }
        for keychain in keychains { try? keychain.delete() }
    }

    static var paths: [String] {
        legacyIDs.flatMap { ["HTTPStorages/\($0)", "HTTPStorages/\($0).binarycookies", "WebKit/\($0)", "Caches/\($0)"] }
    }
}
