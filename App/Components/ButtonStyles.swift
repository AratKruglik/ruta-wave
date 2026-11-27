import SwiftUI

struct PillButtonStyle: ButtonStyle {
    var isProminent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rwButton)
            .foregroundStyle(isProminent ? .textOnInverse : .textPrimary)
            .padding(.horizontal, Metrics.space16)
            .frame(height: Metrics.pillHeight)
            .background(isProminent ? .surfaceInverse : .surfaceFill, in: Capsule())
            .fixedSize()
            .opacity(isEnabled ? (configuration.isPressed ? Metrics.pressedOpacity : 1) : Metrics.unavailableOpacity)
    }
}

struct IconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? Metrics.pressedOpacity : 1) : Metrics.unavailableOpacity)
    }
}
