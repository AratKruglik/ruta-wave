import Foundation
import PlayerEngine
import Testing

@testable import Plugins

@MainActor
struct NotificationsPluginTests {
    private let defaults = makeDefaults()
    private let player = FakePlayer()
    private let posting = FakePosting()

    private func song(_ id: String) -> SongInfo {
        SongInfo(videoId: id, title: id, artist: "A", artworkURL: nil, duration: 200, url: URL(string: "https://music.youtube.com/watch?v=\(id)")!)
    }

    private func plugin(artwork: @escaping @Sendable (URL) async -> URL? = { _ in nil }) -> NotificationsPlugin {
        NotificationsPlugin(posting: posting, isFrontmost: { false }, loadArtwork: artwork)
    }

    private func context() -> PluginContext {
        PluginContext(player: player, events: player.events(), settings: PluginSettings(id: NotificationsPlugin.id, defaults: defaults))
    }

    @Test func aTrackChangePostsOnce() async throws {
        let plugin = plugin()
        try await plugin.start(context: context())
        player.emit(.songChanged(song("a")))
        #expect(await eventually { await posting.titles == ["a"] })
        await plugin.stop()
    }

    @Test func nothingPostsAfterStop() async throws {
        let plugin = plugin()
        try await plugin.start(context: context())
        await plugin.stop()
        player.emit(.songChanged(song("a")))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await posting.titles.isEmpty)
        #expect(player.liveStreams == 0)
    }

    @Test func stoppingDuringTheArtworkWaitPostsNothing() async throws {
        let gate = Gate()
        let started = Gate()
        let plugin = plugin { _ in
            await started.open()
            await gate.wait()
            return nil
        }
        try await plugin.start(context: context())
        player.emit(.songChanged(SongInfo(
            videoId: "a", title: "a", artist: "A", artworkURL: URL(string: "https://i.ytimg.com/a.jpg"), duration: 200,
            url: URL(string: "https://music.youtube.com/watch?v=a")!)))
        await started.wait()
        await plugin.stop()
        await gate.open()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await posting.titles.isEmpty)
    }

    @Test func startingMidTrackDoesNotAnnounceTheCurrentSong() async throws {
        player.song = song("a")
        let plugin = plugin()
        try await plugin.start(context: context())
        player.emit(.songChanged(song("a")))
        player.emit(.songChanged(song("b")))
        #expect(await eventually { await posting.titles == ["b"] })
        await plugin.stop()
    }

    @Test func theRestoredTrackIsSkippedOnlyOnce() async throws {
        let plugin = plugin()
        plugin.skipRestored(videoId: "a")
        try await plugin.start(context: context())
        player.emit(.songChanged(song("a")))
        player.emit(.songChanged(song("b")))
        #expect(await eventually { await posting.titles == ["b"] })
        await plugin.stop()

        try await plugin.start(context: context())
        player.emit(.songChanged(song("a")))
        #expect(await eventually { await posting.titles == ["b", "a"] })
        await plugin.stop()
    }

    @Test func startingDuringAnAdHoldsTheTrackUntilTheAdEnds() async throws {
        player.isAd = true
        let plugin = plugin()
        try await plugin.start(context: context())
        player.emit(.songChanged(song("a")))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await posting.titles.isEmpty)
        player.emit(.adChanged(false))
        #expect(await eventually { await posting.titles == ["a"] })
        await plugin.stop()
    }

    @Test func switchingTheSettingOffSuppressesAPostBeforeTheRegistryHearsOfIt() async throws {
        let plugin = plugin()
        try await plugin.start(context: context())
        PluginSettings(id: NotificationsPlugin.id, defaults: defaults).setEnabled(false)
        player.emit(.songChanged(song("a")))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await posting.titles.isEmpty)
        await plugin.stop()
    }

    @Test func migrationCopiesTheLegacyValueAndRemovesIt() {
        defaults.set(false, forKey: "trackNotifications")
        NotificationsPlugin.migrateLegacySetting(in: defaults)
        #expect(!PluginSettings(id: NotificationsPlugin.id, defaults: defaults).isEnabled(default: true))
        #expect(defaults.object(forKey: "trackNotifications") == nil)
    }

    @Test func migrationLeavesTheDefaultWhenNothingWasStored() {
        NotificationsPlugin.migrateLegacySetting(in: defaults)
        #expect(defaults.object(forKey: "plugins.notifications.enabled") == nil)
        #expect(PluginSettings(id: NotificationsPlugin.id, defaults: defaults).isEnabled(default: true))
    }

    @Test func migrationDoesNotOverwriteAnAlreadyMigratedValue() {
        PluginSettings(id: NotificationsPlugin.id, defaults: defaults).setEnabled(true)
        defaults.set(false, forKey: "trackNotifications")
        NotificationsPlugin.migrateLegacySetting(in: defaults)
        #expect(PluginSettings(id: NotificationsPlugin.id, defaults: defaults).isEnabled(default: false))
        #expect(defaults.object(forKey: "trackNotifications") == nil)
    }
}
