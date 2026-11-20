import AppKit
import Foundation
import Testing
@testable import PlayerEngine

@MainActor
struct LivePlaybackTests {
    private func wait(for engine: PlayerEngine, seconds: Double = 30, until match: @escaping @Sendable (PlayerEvent) -> Bool) async -> Bool {
        let stream = engine.events()
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await event in stream where match(event) { return true }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["REDWAVE_LIVE_TESTS"] == "1"))
    func guestPausesAndSeeks() async throws {
        let engine = PlayerEngine()
        await engine.start(.signedOut)
        let view = try #require(engine.webView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        defer { engine.stop() }

        engine.load(videoId: "dQw4w9WgXcQ", playlistId: nil)
        #expect(await wait(for: engine) { if case .songChanged = $0 { true } else { false } })

        engine.send(.pause)
        #expect(await wait(for: engine, seconds: 10) { if case .playbackChanged(true, _) = $0 { true } else { false } })

        engine.send(.seek(to: 30))
        #expect(await wait(for: engine, seconds: 10) { if case .timeChanged(let time) = $0 { abs(time - 30) <= 1 } else { false } })
    }
}
