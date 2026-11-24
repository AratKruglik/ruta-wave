import SwiftUI
import SystemKit

private struct ReconnectModifier: ViewModifier {
    let action: () -> Void
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?

    func body(content: Content) -> some View {
        content.onChange(of: network?.reconnects) { action() }
    }
}

extension View {
    /// Runs `action` each time the network comes back. Only mounted screens react, so a retry reaches visible content only.
    func onReconnect(_ action: @escaping () -> Void) -> some View {
        modifier(ReconnectModifier(action: action))
    }
}
