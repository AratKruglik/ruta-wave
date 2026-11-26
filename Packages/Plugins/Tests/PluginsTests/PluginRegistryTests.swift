import Foundation
import Testing

@testable import Plugins

@MainActor
struct PluginRegistryTests {
    private let defaults = makeDefaults()
    private let player = FakePlayer()
    private let a = FakePlugin<IDA>()
    private let b = FakePlugin<IDB>()

    private func registry() -> PluginRegistry {
        PluginRegistry(plugins: [a, b], player: player, defaults: defaults)
    }

    @Test func aPluginEnabledByDefaultStartsAndADisabledOneDoesNot() async {
        PluginSettings(id: "b", defaults: defaults).setEnabled(false)
        let registry = registry()
        registry.sync()
        #expect(await eventually { registry.states["a"] == .running && registry.states["b"] == .stopped })
        #expect(a.starts == 1)
        #expect(b.starts == 0)
    }

    @Test func writingTheKeyAndSyncingStartsAndStopsThePlugin() async {
        let registry = registry()
        registry.sync()
        #expect(await eventually { registry.states["a"] == .running })
        PluginSettings(id: "a", defaults: defaults).setEnabled(false)
        registry.sync()
        #expect(await eventually { registry.states["a"] == .stopped })
        #expect(a.stops == 1)
        #expect(player.liveStreams == 1)
    }

    @Test func syncingWithoutAChangeDoesNothing() async {
        let registry = registry()
        registry.sync()
        #expect(await eventually { registry.states["a"] == .running })
        registry.sync()
        registry.sync()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(a.starts == 1)
        #expect(a.stops == 0)
    }

    @Test func aFailingPluginLeavesTheOtherRunningAndReleasesItsStream() async {
        a.failsToStart = true
        let registry = registry()
        registry.sync()
        #expect(await eventually { registry.states["a"] == .failed && registry.states["b"] == .running })
        #expect(player.liveStreams == 1)
    }

    @Test func aHangingPluginDoesNotBlockTheOther() async {
        let gate = Gate()
        a.startGate = gate
        let registry = registry()
        registry.sync()
        #expect(await eventually { registry.states["b"] == .running })
        #expect(registry.states["a"] == nil)
        await gate.open()
        #expect(await eventually { registry.states["a"] == .running })
    }

    @Test func switchingOffAndOnLeavesExactlyOneRunningInstance() async {
        let registry = registry()
        let settings = PluginSettings(id: "a", defaults: defaults)
        registry.sync()
        settings.setEnabled(false)
        registry.sync()
        settings.setEnabled(true)
        registry.sync()
        #expect(await eventually { registry.states["a"] == .running })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(a.starts - a.stops == 1)
        #expect(player.liveStreams == 2)
    }

    @Test func stoppingAfterAFailedStartDoesNotCallStop() async {
        a.failsToStart = true
        let registry = registry()
        registry.sync()
        #expect(await eventually { registry.states["a"] == .failed })
        PluginSettings(id: "a", defaults: defaults).setEnabled(false)
        registry.sync()
        #expect(await eventually { registry.states["a"] == .stopped })
        #expect(a.stops == 0)
    }
}

struct PluginSettingsTests {
    @Test func keysAreNamespacedPerPlugin() {
        let defaults = makeDefaults()
        let notifications = PluginSettings(id: "notifications", defaults: defaults)
        let other = PluginSettings(id: "other", defaults: defaults)
        notifications["foo"] = "x"
        #expect(defaults.string(forKey: "plugins.notifications.foo") == "x")
        #expect(other["foo"] == nil)
        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("plugins.") } == ["plugins.notifications.foo"])
    }

    @Test func enabledFallsBackToTheDefault() {
        let settings = PluginSettings(id: "x", defaults: makeDefaults())
        #expect(settings.isEnabled(default: true))
        #expect(!settings.isEnabled(default: false))
        settings.setEnabled(false)
        #expect(!settings.isEnabled(default: true))
    }
}
