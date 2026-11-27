import AppKit
import SwiftUI

/// Back / forward from mouse buttons 4 and 5 and trackpad swipes, and Space as play / pause. Left clicks are only reported.
struct WindowEventMonitor: NSViewRepresentable {
    let onBack: @MainActor () -> Void
    let onForward: @MainActor () -> Void
    let onTogglePlay: @MainActor () -> Void
    var onMouseDown: @MainActor (CGPoint) -> Void = { _ in }

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onBack = onBack
        view.onForward = onForward
        view.onTogglePlay = onTogglePlay
        view.onMouseDown = onMouseDown
    }

    final class MonitorView: NSView {
        var onBack: @MainActor () -> Void = {}
        var onForward: @MainActor () -> Void = {}
        var onTogglePlay: @MainActor () -> Void = {}
        var onMouseDown: @MainActor (CGPoint) -> Void = { _ in }
        private var monitor: Any?

        private static let spaceKeyCode: UInt16 = 49
        private static let backMouseButton = 3
        private static let forwardMouseButton = 4

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            let mask: NSEvent.EventTypeMask = [.leftMouseDown, .otherMouseDown, .swipe, .scrollWheel, .keyDown]
            monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                nonisolated(unsafe) let event = event
                let isConsumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
                return isConsumed ? nil : event
            }
        }

        /// A focused control presses itself on Space; only a window with no first responder, or a list (the sidebar), plays or pauses.
        private var isNothingFocused: Bool {
            guard let window else { return false }
            return window.firstResponder == nil || window.firstResponder === window || window.firstResponder is NSTableView
        }

        private func handle(_ event: NSEvent) -> Bool {
            guard event.window === window else { return false }
            switch event.type {
            case .leftMouseDown:
                onMouseDown(event.locationInWindow)
                return false
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
                      isNothingFocused else { return false }
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
