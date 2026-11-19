import Foundation
@testable import InnerTube

enum Fixture {
    static let directory = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent("\(name).json"))
    }

    static func json(_ name: String) throws -> JSONValue {
        try JSONValue(response: data(name))
    }

    static var all: [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
