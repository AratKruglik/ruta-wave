import Foundation
import PlayerEngine

/// A feature the user can switch on and off. `start` must return promptly: long-lived work belongs in a task the plugin owns.
@MainActor
public protocol Plugin: AnyObject {
    static var id: String { get }
    static var title: LocalizedStringResource { get }
    static var isEnabledByDefault: Bool { get }
    func start(context: PluginContext) async throws
    func stop() async
}

public struct PluginContext {
    public let player: any PlayerControlling
    public let events: AsyncStream<PlayerEvent>
    public let settings: PluginSettings

    public init(player: any PlayerControlling, events: AsyncStream<PlayerEvent>, settings: PluginSettings) {
        self.player = player
        self.events = events
        self.settings = settings
    }
}
