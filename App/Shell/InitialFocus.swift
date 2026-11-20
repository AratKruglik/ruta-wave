import AppKit
import SwiftUI

extension View {
    /// AppKit focuses the first control when a window or popover first becomes key, which draws a focus ring
    /// nobody asked for; Tab still reaches every control.
    func noInitialFocus() -> some View { background(InitialFocusClearer()) }

    /// Popovers ignore a cleared first responder, so an invisible first stop takes the initial focus instead.
    func noInitialPopoverFocus() -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 0).focusable().focusEffectDisabled().accessibilityHidden(true)
            self
        }
    }
}

private struct InitialFocusClearer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ClearingView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class ClearingView: NSView {
        private var token: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            guard let window else { return }
            if window.isKeyWindow {
                Self.clear(window)
                return
            }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    if let token = self?.token { NotificationCenter.default.removeObserver(token) }
                    self?.token = nil
                }
                MainActor.assumeIsolated { Self.clear(window) }
            }
        }

        private static func clear(_ window: NSWindow?) {
            DispatchQueue.main.async { window?.makeFirstResponder(nil) }
        }
    }
}
