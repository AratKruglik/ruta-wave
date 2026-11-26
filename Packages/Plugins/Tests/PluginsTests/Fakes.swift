import Foundation
import os
import PlayerEngine
import SystemKit

@testable import Plugins

@MainActor
final class FakePlayer: PlayerControlling {
    var song: SongInfo?
    let elapsed: TimeInterval = 0
    let isPaused = false
    let isReady = true
    let isBuffering = false
    let isAd = false
    let volume = 1.0
    let isMuted = false
    let like = LikeStatus.indifferent
    let repeatMode = RepeatMode.off
    let isShuffled = false
    let queue: [QueueItem] = []

    private let live = OSAllocatedUnfairLock(initialState: [UUID: AsyncStream<PlayerEvent>.Continuation]())

    var liveStreams: Int { live.withLock { $0.count } }

    func send(_ command: PlayerCommand) {}

    func events() -> AsyncStream<PlayerEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<PlayerEvent>.makeStream()
        live.withLock { $0[id] = continuation }
        continuation.onTermination = { [live] _ in live.withLock { $0[id] = nil } }
        return stream
    }

    func emit(_ event: PlayerEvent) {
        live.withLock { $0.values }.forEach { $0.yield(event) }
    }
}

protocol FakeID { static var id: String { get } }
enum IDA: FakeID { static let id = "a" }
enum IDB: FakeID { static let id = "b" }

struct StartFailure: Error {}

@MainActor
final class FakePlugin<ID: FakeID>: Plugin {
    static var id: String { ID.id }
    static var title: LocalizedStringResource { "Fake" }
    static var isEnabledByDefault: Bool { true }

    var failsToStart = false
    var startGate: Gate?
    private(set) var starts = 0
    private(set) var stops = 0
    private var events: AsyncStream<PlayerEvent>?

    func start(context: PluginContext) async throws {
        starts += 1
        if let startGate { await startGate.wait() }
        events = context.events
        if failsToStart { throw StartFailure() }
    }

    func stop() async {
        stops += 1
        events = nil
    }
}

actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

actor FakePosting: NotificationPosting {
    private(set) var titles: [String] = []

    func authorizationStatus() -> NotificationAuthorization { .authorized }
    func requestAuthorization() -> Bool { true }
    func post(identifier: String, title: String, body: String, attachmentURL: URL?) { titles.append(title) }
}

func makeDefaults() -> UserDefaults {
    let name = "PluginsTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<500 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}
