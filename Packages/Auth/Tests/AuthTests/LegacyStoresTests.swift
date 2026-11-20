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
    private let rutawavePaths = [
        "HTTPStorages/dev.kruhlyk.rutawave", "HTTPStorages/dev.kruhlyk.rutawave.binarycookies",
        "WebKit/dev.kruhlyk.rutawave", "Caches/dev.kruhlyk.rutawave",
    ]

    @Test func removesEveryLegacyStore() throws {
        let library = try Library()
        defer { try? FileManager.default.removeItem(at: library.root) }
        for path in LegacyStores.paths { try library.make(path) }
        let spies = [KeychainSpy(), KeychainSpy()]

        LegacyStores.remove(library: library.root, keychains: spies)

        #expect(LegacyStores.paths.allSatisfy { !library.exists($0) })
        #expect(spies.allSatisfy { $0.deleteCount == 1 })
    }

    @Test func keepsRutawaveStores() throws {
        let library = try Library()
        defer { try? FileManager.default.removeItem(at: library.root) }
        for path in LegacyStores.paths + rutawavePaths { try library.make(path) }

        LegacyStores.remove(library: library.root, keychains: [KeychainSpy()])

        #expect(rutawavePaths.allSatisfy { library.exists($0) })
    }

    @Test func removesLegacyCookieJarTempCopiesOnly() throws {
        let library = try Library()
        defer { try? FileManager.default.removeItem(at: library.root) }
        let legacy = ["redwave", "tunewave"].map { "HTTPStorages/dev.kruhlyk.\($0).binarycookies_tmp_1.dat" }
        let current = "HTTPStorages/dev.kruhlyk.rutawave.binarycookies_tmp_1.dat"
        try FileManager.default.createDirectory(at: library.root.appendingPathComponent("HTTPStorages"), withIntermediateDirectories: true)
        for path in legacy + [current] {
            try Data("x".utf8).write(to: library.root.appendingPathComponent(path))
        }

        LegacyStores.remove(library: library.root, keychains: [KeychainSpy()])

        #expect(legacy.allSatisfy { !library.exists($0) })
        #expect(library.exists(current))
    }

    @Test func emptyLibraryIsNoOp() throws {
        let library = try Library()
        defer { try? FileManager.default.removeItem(at: library.root) }

        LegacyStores.remove(library: library.root, keychains: [KeychainSpy()])

        #expect(try FileManager.default.contentsOfDirectory(atPath: library.root.path).isEmpty)
    }

    @Test func sessionKeychainItemUsesRutawaveService() {
        #expect(KeychainItem.session.service == "dev.kruhlyk.rutawave.session")
        #expect(KeychainItem.session.account == "default")
    }

    @Test func legacyPathsCoverTunewaveAndRedwaveOnly() {
        #expect(LegacyStores.paths.count == 8)
        #expect(LegacyStores.paths.allSatisfy { $0.contains("dev.kruhlyk.tunewave") || $0.contains("dev.kruhlyk.redwave") })
        #expect(LegacyStores.paths.allSatisfy { !$0.contains("rutawave") })
    }

    @Test func symlinkIsRemovedWithoutFollowingIt() throws {
        let library = try Library()
        let outside = try Library()
        defer {
            try? FileManager.default.removeItem(at: library.root)
            try? FileManager.default.removeItem(at: outside.root)
        }
        try outside.make("keep")
        let links = ["Caches/dev.kruhlyk.tunewave", "Caches/dev.kruhlyk.redwave"]
        for path in links {
            let link = library.root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside.root.appendingPathComponent("keep"))
        }

        LegacyStores.remove(library: library.root, keychains: [KeychainSpy()])

        #expect(links.allSatisfy { !library.exists($0) })
        #expect(outside.exists("keep/file"))
    }

    @Test func filesAreGoneBeforeKeychainDeleteIsCalled() throws {
        let library = try Library()
        defer { try? FileManager.default.removeItem(at: library.root) }
        for path in LegacyStores.paths { try library.make(path) }
        let spies = [KeychainSpy(), KeychainSpy()]
        var filesGoneAtDelete = false
        spies[0].onDelete = { filesGoneAtDelete = LegacyStores.paths.allSatisfy { !library.exists($0) } }

        LegacyStores.remove(library: library.root, keychains: spies)

        #expect(spies.allSatisfy { $0.deleteCount == 1 })
        #expect(filesGoneAtDelete)
    }

    @Test func oneKeychainFailureStillDeletesTheOther() throws {
        let library = try Library()
        defer { try? FileManager.default.removeItem(at: library.root) }
        for path in LegacyStores.paths { try library.make(path) }
        let failing = KeychainSpy()
        failing.deleteError = KeychainError(status: errSecAuthFailed)
        let other = KeychainSpy()

        LegacyStores.remove(library: library.root, keychains: [failing, other])

        #expect(other.deleteCount == 1)
        #expect(LegacyStores.paths.allSatisfy { !library.exists($0) })
    }
}
