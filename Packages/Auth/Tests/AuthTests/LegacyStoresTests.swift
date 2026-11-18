import Foundation
import Security
import Testing
@testable import Auth

private final class KeychainSpy: KeychainStore, @unchecked Sendable {
    private(set) var deleteCount = 0
    var deleteError: KeychainError?

    func read() throws(KeychainError) -> Data? { nil }
    func write(_ data: Data) throws(KeychainError) {}
    var onDelete: (() -> Void)?
    func delete() throws(KeychainError) {
        onDelete?()
        deleteCount += 1
        if let deleteError { throw deleteError }
    }
}

private struct Library {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }

    func make(_ path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if path.hasSuffix(".binarycookies") {
            try Data("x".utf8).write(to: url)
        } else {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url.appendingPathComponent("file"))
        }
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
    }
}

@Suite struct LegacyStoresTests {
    private let redwavePaths = [
        "HTTPStorages/dev.kruhlyk.redwave", "HTTPStorages/dev.kruhlyk.redwave.binarycookies",
        "WebKit/dev.kruhlyk.redwave", "Caches/dev.kruhlyk.redwave",
    ]

    @Test func removesEveryLegacyStore() throws {
        let library = try Library()
        defer { try? FileManager.default.removeItem(at: library.root) }
        for path in LegacyStores.paths { try library.make(path) }
        let keychain = KeychainSpy()

        LegacyStores.remove(library: library.root, keychain: keychain)

        #expect(LegacyStores.paths.allSatisfy { !library.exists($0) })
        #expect(keychain.deleteCount == 1)
    }

    @Test func keepsRedwaveStores() throws {
        let library = try Library()
        defer { try? FileManager.default.removeItem(at: library.root) }
        for path in LegacyStores.paths + redwavePaths { try library.make(path) }

        LegacyStores.remove(library: library.root, keychain: KeychainSpy())

        #expect(redwavePaths.allSatisfy { library.exists($0) })
    }

    @Test func emptyLibraryIsNoOp() throws {
        let library = try Library()
        defer { try? FileManager.default.removeItem(at: library.root) }

        LegacyStores.remove(library: library.root, keychain: KeychainSpy())

        #expect(try FileManager.default.contentsOfDirectory(atPath: library.root.path).isEmpty)
    }

    @Test func sessionKeychainItemUsesRedwaveService() {
        #expect(KeychainItem.session.service == "dev.kruhlyk.redwave.session")
        #expect(KeychainItem.session.account == "default")
    }

    @Test func legacyPathsAreAllUnderTunewaveID() {
        #expect(LegacyStores.paths.count == 4)
        #expect(LegacyStores.paths.allSatisfy { $0.contains("dev.kruhlyk.tunewave") && !$0.contains("redwave") })
    }

    @Test func symlinkIsRemovedWithoutFollowingIt() throws {
        let library = try Library()
        let outside = try Library()
        defer {
            try? FileManager.default.removeItem(at: library.root)
            try? FileManager.default.removeItem(at: outside.root)
        }
        try outside.make("keep")
        let link = library.root.appendingPathComponent("Caches/dev.kruhlyk.tunewave")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside.root.appendingPathComponent("keep"))

        LegacyStores.remove(library: library.root, keychain: KeychainSpy())

        #expect(!library.exists("Caches/dev.kruhlyk.tunewave"))
        #expect(outside.exists("keep/file"))
    }

    @Test func filesAreGoneBeforeKeychainDeleteIsCalled() throws {
        let library = try Library()
        defer { try? FileManager.default.removeItem(at: library.root) }
        for path in LegacyStores.paths { try library.make(path) }
        let keychain = KeychainSpy()
        var filesGoneAtDelete = false
        keychain.onDelete = { filesGoneAtDelete = LegacyStores.paths.allSatisfy { !library.exists($0) } }

        LegacyStores.remove(library: library.root, keychain: keychain)

        #expect(keychain.deleteCount == 1)
        #expect(filesGoneAtDelete)
    }

    @Test func keychainFailureStillRemovesFiles() throws {
        let library = try Library()
        defer { try? FileManager.default.removeItem(at: library.root) }
        for path in LegacyStores.paths { try library.make(path) }
        let keychain = KeychainSpy()
        keychain.deleteError = KeychainError(status: errSecAuthFailed)

        LegacyStores.remove(library: library.root, keychain: keychain)

        #expect(LegacyStores.paths.allSatisfy { !library.exists($0) })
    }
}
