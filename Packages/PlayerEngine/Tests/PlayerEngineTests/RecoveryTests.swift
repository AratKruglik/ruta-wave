import Foundation
import Testing
@testable import PlayerEngine

@MainActor
struct RecoveryTests {
    private func makeSong(_ id: String = "abc") -> SongInfo {
        SongInfo(videoId: id, title: "T", artist: "A", album: nil, artworkURL: nil, duration: 100,
                 elapsed: 0, isPaused: false, playlistId: "PL1", url: URL(string: "https://music.youtube.com/watch?v=\(id)")!)
    }

    private func makeEngine() -> PlayerEngine { PlayerEngine { _ in true } }

    @Test func committedSongBecomesTheRecoveryTarget() {
        let engine = makeEngine()
        engine.commit(makeSong("xyz"))
        #expect(engine.target?.videoId == "xyz")
        #expect(engine.target?.playlistId == "PL1")
    }

    @Test func reloadsAreCappedAndUseTheTarget() throws {
        let engine = makeEngine()
        engine.commit(makeSong("xyz"))
        for _ in 0..<PlayerRules.maxReloadAttempts {
            #expect(try #require(engine.nextRecoveryURL()).absoluteString == "https://music.youtube.com/watch?v=xyz&list=PL1")
        }
        #expect(engine.nextRecoveryURL() == nil)
    }

    @Test func noTargetMeansNoRecovery() {
        #expect(makeEngine().nextRecoveryURL() == nil)
    }

    @Test func committingASongResetsTheAttemptCount() {
        let engine = makeEngine()
        engine.commit(makeSong())
        _ = engine.nextRecoveryURL()
        #expect(engine.attempts == 1)
        engine.commit(makeSong("def"))
        #expect(engine.attempts == 0)
    }

    @Test func restoreCommitKeepsTheAttemptCount() {
        let engine = makeEngine()
        engine.commit(makeSong())
        _ = engine.nextRecoveryURL()
        engine.resumeAt = 42
        engine.commit(makeSong())
        #expect(engine.attempts == 1)
    }

    @Test func reloadingTheCurrentSongEndsTheWatchdog() {
        let engine = makeEngine()
        engine.commit(makeSong())
        _ = engine.nextRecoveryURL()
        let watchdog = Task<Void, Never> { try? await Task.sleep(for: .seconds(60)) }
        engine.watchdog = watchdog
        #expect(engine.handle(.song(makeSong(), artworkWithQuery: nil)) == nil)
        #expect(watchdog.isCancelled)
        #expect(engine.attempts == 1)
    }

    @Test func restoreBypassesTheSongDedupe() async {
        let engine = makeEngine()
        engine.commit(makeSong())
        #expect(engine.handle(.song(makeSong(), artworkWithQuery: nil)) == nil)
        engine.resumeAt = 42
        var iterator = engine.events().makeAsyncIterator()
        _ = engine.handle(.song(makeSong(), artworkWithQuery: nil))
        guard case .songChanged(let song)? = await iterator.next() else { Issue.record("expected songChanged"); return }
        #expect(song.videoId == "abc")
        #expect(engine.resumeAt == nil)
    }

    @Test func adTimeIsNotRecorded() {
        let engine = makeEngine()
        _ = engine.handle(.time(30))
        _ = engine.handle(.ad(true))
        _ = engine.handle(.time(5))
        _ = engine.handle(.playback(isPaused: false, elapsed: 6))
        #expect(engine.position == 30)
        #expect(engine.elapsed == 6)
        _ = engine.handle(.ad(false))
        _ = engine.handle(.time(31))
        #expect(engine.position == 31)
    }

    @Test func crashRemembersThePositionAndStopClearsRecovery() {
        let engine = makeEngine()
        engine.commit(makeSong())
        _ = engine.handle(.time(77))
        #expect(engine.position == 77)
        engine.stop()
        #expect(engine.target == nil && engine.attempts == 0 && engine.resumeAt == nil && engine.position == 0)
    }

    @Test func repeatedSongReportsAfterARestoreKeepTheCrashCap() {
        let engine = makeEngine()
        engine.commit(makeSong())
        _ = engine.nextRecoveryURL()
        engine.resumeAt = 42
        engine.commit(makeSong())
        _ = engine.handle(.song(makeSong(), artworkWithQuery: nil))
        _ = engine.handle(.song(makeSong(), artworkWithQuery: nil))
        #expect(engine.attempts == 1)
        _ = engine.nextRecoveryURL()
        #expect(engine.nextRecoveryURL() == nil)
    }

    @Test func secondCrashKeepsTheFirstSnapshot() {
        let engine = makeEngine()
        engine.commit(makeSong())
        engine.position = 77
        _ = engine.handle(.queue([
            QueueItem(videoId: "abc", title: "T", artist: "A", artworkURL: nil, duration: 1, isCurrent: true),
            QueueItem(videoId: "def", title: "T", artist: "A", artworkURL: nil, duration: 1, isCurrent: false),
        ], offset: 0))
        engine.snapshotForRestore()
        #expect(engine.resumeAt == 77 && engine.resumeQueue == ["def"] && engine.target?.playlistId == nil)
        engine.position = 2
        _ = engine.handle(.queue([], offset: 0))
        engine.snapshotForRestore()
        #expect(engine.resumeAt == 77 && engine.resumeQueue == ["def"])
    }

    @Test func givingUpCancelsTheWatchdog() {
        let engine = makeEngine()
        engine.commit(makeSong())
        engine.attempts = PlayerRules.maxReloadAttempts
        let watchdog = Task<Void, Never> { try? await Task.sleep(for: .seconds(60)) }
        engine.watchdog = watchdog
        #expect(engine.nextRecoveryURL() == nil)
        #expect(watchdog.isCancelled)
    }

    @Test func stablePlaybackEndsTheFailureStreak() {
        let engine = makeEngine()
        engine.commit(makeSong())
        engine.attempts = 1
        _ = engine.handle(.time(5))
        #expect(engine.attempts == 1)
        engine.committedAt = .now - PlayerRules.stablePlayback
        _ = engine.handle(.time(6))
        #expect(engine.attempts == 0)
    }

    @Test func requestedVolumeIsRememberedAndClamped() {
        let engine = makeEngine()
        #expect(engine.requestedVolume == nil)
        engine.send(.setVolume(0.5))
        #expect(engine.requestedVolume == 0.5)
        engine.send(.setVolume(3))
        #expect(engine.requestedVolume == 1)
        engine.send(.setVolume(.nan))
        #expect(engine.requestedVolume == 1)
        engine.stop()
        #expect(engine.requestedVolume == 1)
    }

    @Test func supersededNavigationsAreNotFailures() {
        #expect(PlayerRules.isIgnorableNavigationError(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        #expect(PlayerRules.isIgnorableNavigationError(NSError(domain: "WebKitErrorDomain", code: 102)))
        #expect(!PlayerRules.isIgnorableNavigationError(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)))
    }
}
