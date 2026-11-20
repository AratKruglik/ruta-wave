import InnerTube
import Observation

@MainActor @Observable
final class GuestModel {
    enum State { case connecting, connected, failed }

    private(set) var state: State = .connecting
    @ObservationIgnored private let client = InnerTubeClient()

    func reset() { state = .connecting }

    func connect() async {
        state = .connecting
        let ok = (try? await client.connectAsGuest()) != nil
        guard !Task.isCancelled else { return }
        state = ok ? .connected : .failed
    }
}
