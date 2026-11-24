import Testing

@testable import SystemKit

@MainActor
struct NetworkMonitorTests {
    @Test func initialOnlineIsNotAReconnect() {
        let monitor = NetworkMonitor()
        monitor.apply(true)
        #expect(monitor.isOnline)
        #expect(monitor.reconnects == 0)
    }

    @Test func repeatedStatusChangesNothing() {
        let monitor = NetworkMonitor()
        monitor.apply(false)
        monitor.apply(false)
        #expect(monitor.reconnects == 0)
        monitor.apply(true)
        monitor.apply(true)
        #expect(monitor.reconnects == 1)
    }

    @Test func offlineThenOnlineBumpsOnce() {
        let monitor = NetworkMonitor()
        monitor.apply(false)
        #expect(!monitor.isOnline)
        monitor.apply(true)
        #expect(monitor.reconnects == 1)
    }

    @Test func flappingCountsEachReconnect() {
        let monitor = NetworkMonitor()
        for online in [false, true, false, true] { monitor.apply(online) }
        #expect(monitor.reconnects == 2)
    }
}
