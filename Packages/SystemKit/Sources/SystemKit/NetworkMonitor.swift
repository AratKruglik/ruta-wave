import Network
import Observation

/// Tracks reachability. `reconnects` bumps only on an observed offline to online edge, so views can key a retry on it.
@MainActor @Observable
public final class NetworkMonitor {
    public private(set) var isOnline = true
    public private(set) var reconnects = 0

    @ObservationIgnored private var monitor: NWPathMonitor?

    public init() {}

    public func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.apply(online) }
        }
        monitor.start(queue: DispatchQueue(label: "dev.kruhlyk.rutawave.network", qos: .utility))
    }

    func apply(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        if online { reconnects += 1 }
    }
}
