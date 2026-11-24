import SwiftUI

enum LiquidGlass {
    static var isAvailable: Bool {
        if #available(macOS 26, *) { true } else { false }
    }
}

private struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let fallback: Color?
    let interactive: Bool
    @Environment(\.themeBase) private var themeBase

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else if let fallback {
            content.background(fallback, in: shape).background(themeBase, in: shape)
        } else {
            content
        }
    }
}

private struct WindowBackdrop: ViewModifier {
    @Environment(\.themeBase) private var themeBase

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.containerBackground(for: .window) {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    themeBase.opacity(0.55)
                }
            }
        } else {
            content.background(themeBase)
        }
    }
}

private struct PopoverSurface: ViewModifier {
    @Environment(\.themeBase) private var themeBase

    func body(content: Content) -> some View {
        if LiquidGlass.isAvailable { content } else { content.background(themeBase) }
    }
}

extension View {
    /// Liquid Glass on macOS 26 and later; before it, `fallback` over the theme base, or nothing when `fallback` is nil.
    func glassSurface(in shape: some Shape, fallback: Color? = .surfaceRaised, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, fallback: fallback, interactive: interactive))
    }

    /// Lets neighbouring glass shapes blend; a no-op before macOS 26.
    @ViewBuilder
    func glassGroup() -> some View {
        if #available(macOS 26, *) {
            GlassEffectContainer { self }
        } else {
            self
        }
    }

    /// Translucent window: the desktop shows through a material tinted with the theme base. Opaque before macOS 15.
    func windowBackdrop() -> some View { modifier(WindowBackdrop()) }

    /// System popovers are Liquid Glass on macOS 26; an opaque fill there would hide it.
    func popoverSurface() -> some View { modifier(PopoverSurface()) }
}
