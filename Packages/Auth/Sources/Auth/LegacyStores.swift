import Foundation

public enum LegacyStores {
    static let legacyID = "dev.kruhlyk.tunewave"

    // Runs on every launch until nothing is left: a denied Keychain prompt or a still-running old build must not leave Google cookies behind.
    public static func remove() {
        remove(
            library: FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0],
            keychain: KeychainItem(service: legacyID + ".session", account: "default")
        )
        UserDefaults.standard.removePersistentDomain(forName: legacyID)
    }

    static func remove(library: URL, keychain: any KeychainStore) {
        for path in paths {
            try? FileManager.default.removeItem(at: library.appendingPathComponent(path))
        }
        try? keychain.delete()
    }

    static var paths: [String] {
        ["HTTPStorages/\(legacyID)", "HTTPStorages/\(legacyID).binarycookies", "WebKit/\(legacyID)", "Caches/\(legacyID)"]
    }
}
