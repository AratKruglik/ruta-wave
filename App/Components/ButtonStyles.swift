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

struct LinkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.accentLink)
            .opacity(isEnabled ? (configuration.isPressed ? Metrics.pressedOpacity : 1) : Metrics.unavailableOpacity)
    }
}

struct BarIconButton: View {
    let symbol: String
    let size: CGFloat
    let label: LocalizedStringKey
    var isOn = false
    var activeTint: Color = .textPrimary
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var showsCircleGlyph: Bool { isOn && differentiateWithoutColor }

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .labelStyle(.iconOnly)
                .symbolVariant(showsCircleGlyph ? .circle.fill : (isOn ? .fill : .none))
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .font(.rwIcon(size))
                .foregroundStyle(isOn ? activeTint : .textPrimary)
                .frame(width: max(size, Metrics.hitTarget), height: max(size, Metrics.hitTarget))
                .background(isOn && !showsCircleGlyph ? .surfaceFill : Color.clear, in: Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(IconButtonStyle())
        .help(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
