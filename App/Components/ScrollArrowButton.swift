import SwiftUI

struct ScrollArrowButton: View {
    let symbol: String
    let label: LocalizedStringKey
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.rwIcon(Metrics.iconRow))
                .foregroundStyle(isEnabled ? .textPrimary : .textDisabled)
                .frame(width: Metrics.shelfControl, height: Metrics.shelfControl)
                .background(.surfaceFill, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(label)
        .accessibilityHidden(true)
    }
}
