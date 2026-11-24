import SwiftUI

extension View {
    /// Esc, only while `enabled`. The optional-shortcut overload of `keyboardShortcut` needs macOS 15.
    @ViewBuilder func cancelShortcut(if enabled: Bool) -> some View {
        if enabled { keyboardShortcut(.cancelAction) } else { self }
    }

    /// A plain-styled button is pressed by Space; this adds Return, which activates rows and cards.
    func onReturn(_ action: @escaping () -> Void) -> some View {
        onKeyPress(.return) {
            action()
            return .handled
        }
    }
}
