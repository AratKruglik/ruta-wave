import AppKit
import SwiftUI

/// Back / forward from mouse buttons 4 and 5 and trackpad swipes, and Space as play / pause.
struct WindowEventMonitor: NSViewRepresentable {
    let onBack: @MainActor () -> Void
    let onForward: @MainActor () -> Void
    let onTogglePlay: @MainActor () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onBack = onBack
        view.onForward = onForward
        view.onTogglePlay = onTogglePlay
    }

    final class MonitorView: NSView {
        var onBack: @MainActor () -> Void = {}
        var onForward: @MainActor () -> Void = {}
        var onTogglePlay: @MainActor () -> Void = {}
        private var monitor: Any?

        private static let spaceKeyCode: UInt16 = 49
        private static let backMouseButton = 3
        private static let forwardMouseButton = 4

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard let window else { return }
            // AppKit focuses the first control on open, which draws a focus ring nobody asked for; Tab still reaches it.
            DispatchQueue.main.async { window.makeFirstResponder(nil) }
            let mask: NSEvent.EventTypeMask = [.otherMouseDown, .swipe, .scrollWheel, .keyDown]
            monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                nonisolated(unsafe) let event = event
                let isConsumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
                return isConsumed ? nil : event
            }
        }

        private func handle(_ event: NSEvent) -> Bool {
            guard event.window === window else { return false }
            switch event.type {
            case .otherMouseDown:
                switch event.buttonNumber {
                case Self.backMouseButton: onBack()
                case Self.forwardMouseButton: onForward()
                default: return false
                }
                return true
            case .swipe:
                if event.deltaX > 0 { onBack() } else if event.deltaX < 0 { onForward() }
                return true
            case .scrollWheel:
                trackSwipe(from: event)
                return false
            case .keyDown:
                guard event.keyCode == Self.spaceKeyCode, !event.isARepeat,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                      !(window?.firstResponder is NSTextView) else { return false }
                onTogglePlay()
                return true
            default:
                return false
            }
        }

        // shortcut: no scroll-consumption check, so horizontal shelves must exclude themselves when they land.
        private func trackSwipe(from event: NSEvent) {
            guard event.phase == .began, NSEvent.isSwipeTrackingFromScrollEventsEnabled,
                  abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
            var lastAmount: CGFloat = 0
            event.trackSwipeEvent(options: .lockDirection, dampenAmountThresholdMin: -1, max: 1) { [weak self] amount, _, isComplete, _ in
                lastAmount = amount
                guard isComplete else { return }
                MainActor.assumeIsolated {
                    if lastAmount >= 1 { self?.onBack() } else if lastAmount <= -1 { self?.onForward() }
                }
            }
        }
    }
}
