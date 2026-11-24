import AppKit
import SwiftUI

extension View {
    /// Reports the real window content width, keeps the window at its minimum size, and relays out after
    /// display changes, so the layout never follows a stale or clamped width.
    func windowFrameMonitor(onWidthChange: @escaping (CGFloat) -> Void) -> some View {
        background(WindowFrameMonitor(onWidthChange: onWidthChange))
    }
}

private struct WindowFrameMonitor: NSViewRepresentable {
    let onWidthChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) { view.onWidthChange = onWidthChange }

    final class MonitorView: NSView {
        var onWidthChange: (CGFloat) -> Void = { _ in }
        private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
            guard let window else { return }
            let center = NotificationCenter.default
            let relayoutEvents: [Notification.Name] = [
                NSWindow.didChangeScreenNotification, NSWindow.didChangeBackingPropertiesNotification,
                NSWindow.didChangeOcclusionStateNotification,
            ]
            tokens = relayoutEvents.map { name in
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.handle(relayout: true) }
                }
            }
            tokens.append(
                center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.handle(relayout: false) }
                })
            tokens.append(
                center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) {
                    [weak self] _ in
                    MainActor.assumeIsolated { self?.handle(relayout: true) }
                })
            handle(relayout: false)
        }

        isolated deinit { tokens.forEach(NotificationCenter.default.removeObserver) }

        private func handle(relayout: Bool) {
            guard let window else { return }
            if !window.styleMask.contains(.fullScreen),
                let frame = WindowLayout.correctedFrame(
                    window.frame, minSize: CGSize(width: Metrics.minWindowWidth, height: Metrics.minWindowHeight),
                    visible: window.screen?.visibleFrame)
            {
                window.setFrame(frame, display: true)
            }
            if relayout, let content = window.contentView {
                content.needsLayout = true
                content.needsDisplay = true
            }
            let width = window.contentView?.bounds.width ?? window.frame.width
            DispatchQueue.main.async { [weak self] in self?.onWidthChange(width) }
        }
    }
}
