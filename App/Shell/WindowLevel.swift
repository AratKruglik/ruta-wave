import AppKit
import SwiftUI

/// Puts the hosting window above other apps' windows (`alwaysOnTop`) or back at the normal level.
struct WindowLevel: NSViewRepresentable {
    let isFloating: Bool

    func makeNSView(context: Context) -> LevelView { LevelView() }

    func updateNSView(_ view: LevelView, context: Context) {
        view.isFloating = isFloating
    }

    final class LevelView: NSView {
        var isFloating = false {
            didSet { apply() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            window?.level = isFloating ? .floating : .normal
        }
    }
}
