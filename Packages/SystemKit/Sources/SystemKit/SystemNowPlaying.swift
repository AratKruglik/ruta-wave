import Foundation
import PlayerEngine

/// Keeps the system's Now Playing entry in step with the player and routes its controls back through the app.
@MainActor
public final class SystemNowPlaying {
    private let send: @MainActor (PlayerCommand) -> Void
    private let publish: @MainActor (NowPlayingInfo?) -> Void
    private var state: NowPlayingState?

    public init(send: @escaping @MainActor (PlayerCommand) -> Void, publish: @escaping @MainActor (NowPlayingInfo?) -> Void) {
        self.send = send
        self.publish = publish
    }

    public func run(_ events: AsyncStream<PlayerEvent>) async {
        for await event in events { handle(event) }
    }

    /// The album arrives after the details load, so a late answer for a previous track is dropped.
    public func setAlbum(_ album: String?, for videoId: String) {
        guard state?.videoId == videoId, state?.album != album else { return }
        state?.album = album
        push()
    }

    func handle(_ event: PlayerEvent) {
        if case .remoteCommand(let command) = event {
            perform(command)
            return
        }
        let (next, shouldPublish) = NowPlayingRules.reduce(state, event)
        state = next
        if shouldPublish { push() }
    }

    @discardableResult
    func perform(_ command: PlayerCommand) -> Bool {
        guard let state else { return false }
        if state.isAd && PlayerRules.isRefusedDuringAd(command) { return false }
        send(command)
        return true
    }

    private func push() {
        publish(state.map(NowPlayingRules.info))
    }
}
