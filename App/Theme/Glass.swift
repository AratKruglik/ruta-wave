import SwiftUI

enum LiquidGlass {
    static var isAvailable: Bool {
        if #available(macOS 26, *) { true } else { false }
    }
}

extension View {
    /// Liquid Glass on macOS 26 and later; before it, `fallback` over the theme base, or nothing when `fallback` is nil.
    @ViewBuilder
    func glassSurface(in shape: some Shape, fallback: Color? = .surfaceRaised, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else if let fallback {
            background(fallback, in: shape).background(.themeBase, in: shape)
        } else {
            self
        }
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
    @ViewBuilder
    func windowBackdrop() -> some View {
        if #available(macOS 15, *) {
            containerBackground(for: .window) {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Color.themeBase.opacity(0.55)
                }
            }
        } else {
            background(.themeBase)
        }
    }

    /// System popovers are Liquid Glass on macOS 26; an opaque fill there would hide it.
    @ViewBuilder
    func popoverSurface() -> some View {
        if LiquidGlass.isAvailable { self } else { background(.themeBase) }
    }
}
