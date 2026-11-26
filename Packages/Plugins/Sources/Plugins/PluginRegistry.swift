import Foundation
import Observation
import OSLog
import PlayerEngine

/// Starts and stops plugins to match their `plugins.<id>.enabled` setting. Each plugin has its own serial chain of transitions,
/// so a plugin that fails or hangs in `start` never holds up another.
@MainActor @Observable
public final class PluginRegistry {
    public enum RunState: Sendable, Equatable { case stopped, running, failed }

    public let plugins: [any Plugin]
    public private(set) var states: [String: RunState] = [:]

    @ObservationIgnored private let player: any PlayerControlling
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var wanted: [String: Bool] = [:]
    @ObservationIgnored private var transitions: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let logger = Logger(subsystem: "dev.kruhlyk.rutawave", category: "plugins")

    public init(plugins: [any Plugin], player: any PlayerControlling, defaults: UserDefaults = .standard) {
        self.plugins = plugins
        self.player = player
        self.defaults = defaults
    }

    /// Cheap when nothing changed: it runs on every `UserDefaults` write, including volume and playback position.
    public func sync() {
        for plugin in plugins {
            let type = Swift.type(of: plugin)
            let id = type.id
            let enabled = PluginSettings(id: id, defaults: defaults).isEnabled(default: type.isEnabledByDefault)
            guard wanted[id] != enabled else { continue }
            wanted[id] = enabled
            let previous = transitions[id]
            transitions[id] = Task {
                await previous?.value
                guard wanted[id] == enabled else { return }
                if enabled { await start(plugin) } else { await stop(plugin) }
            }
        }
    }

    private func start(_ plugin: any Plugin) async {
        let id = type(of: plugin).id
        guard states[id] != .running else { return }
        let context = PluginContext(player: player, events: player.events(), settings: PluginSettings(id: id, defaults: defaults))
        do {
            try await plugin.start(context: context)
            states[id] = .running
        } catch {
            logger.error("Plugin \(id, privacy: .public) failed to start: \(error.localizedDescription, privacy: .public)")
            await plugin.stop()
            states[id] = .failed
        }
    }

    private func stop(_ plugin: any Plugin) async {
        let id = type(of: plugin).id
        if states[id] == .running { await plugin.stop() }
        states[id] = .stopped
    }
}
