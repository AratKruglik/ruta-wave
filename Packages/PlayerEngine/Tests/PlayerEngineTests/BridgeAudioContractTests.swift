import Foundation
import Testing

struct BridgeAudioContractTests {
    private var source: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/PlayerEngine/Resources/bridge.js")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    @Test func bridgeExposesRunAndAudioOnFrozenObject() throws {
        #expect(try source.contains("Object.freeze({ run, audio })"))
    }

    @Test func audioContextIsNeverConstructedAtTopLevel() throws {
        let constructions = try source.split(separator: "\n").filter { $0.contains("new AudioContext(") }
        #expect(!constructions.isEmpty)
        for line in constructions {
            #expect(line.hasPrefix("    "), "AudioContext must only be built inside enable(): \(line)")
        }
    }
}
