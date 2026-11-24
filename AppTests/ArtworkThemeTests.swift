import SwiftUI
import Testing

struct ArtworkThemeTests {
    private let inputs: [(r: Double, g: Double, b: Double)] = [
        (1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0), (0, 0, 0), (1, 1, 1), (0.5, 0.5, 0.5), (0.05, 0.02, 0.1), (0.9, 0.95, 1),
    ]

    @Test func clampKeepsSaturationAndBrightnessInRange() {
        for input in inputs {
            let base = ThemeColor.base(fromAverage: input)
            #expect(base.s >= 0 && base.s <= ThemeColor.maxSaturation)
            #expect(ThemeColor.brightnessRange.contains(base.b))
        }
    }

    @Test func clampKeepsTheHue() {
        let original = ThemeColor.hsb(from: (0.9, 0.2, 0.3))
        let base = ThemeColor.base(fromAverage: (0.9, 0.2, 0.3))
        #expect(abs(base.h - original.h) < 1e-9)
    }

    @Test func secondaryTextKeepsReadableContrastOnEveryClampedExtreme() {
        let extremes = stride(from: 0.0, to: 1.0, by: 1.0 / 36).flatMap { hue in
            [ThemeColor.HSB(h: hue, s: ThemeColor.maxSaturation, b: ThemeColor.brightnessRange.upperBound),
             ThemeColor.HSB(h: hue, s: ThemeColor.maxSaturation, b: ThemeColor.brightnessRange.lowerBound),
             ThemeColor.HSB(h: hue, s: 0, b: ThemeColor.brightnessRange.upperBound)]
        }
        for base in extremes {
            let background = ThemeColor.rgb(from: base)
            let text = (r: 0.7 + 0.3 * background.r, g: 0.7 + 0.3 * background.g, b: 0.7 + 0.3 * background.b)
            #expect(ThemeColor.contrast(text, background) >= 4.5)
        }
    }

    @Test func lighterStaysInRange() {
        for input in inputs {
            let lighter = ThemeColor.lighter(ThemeColor.base(fromAverage: input), by: ThemeColor.headerLift)
            #expect(lighter.b >= 0 && lighter.b <= 1)
        }
        #expect(ThemeColor.lighter(ThemeColor.HSB(h: 0, s: 0, b: 0.95), by: 0.5).b == 1)
    }

    @Test @MainActor func updatingWithNoArtworkResetsToTheNeutralColour() async {
        let theme = ArtworkTheme()
        await theme.update(artworkURL: nil)
        #expect(theme.base == .themeBase)
    }

    @Test func rgbRoundTripsThroughHSB() {
        let color = (r: 0.3, g: 0.6, b: 0.2)
        let back = ThemeColor.rgb(from: ThemeColor.hsb(from: color))
        #expect(abs(back.r - color.r) < 1e-9 && abs(back.g - color.g) < 1e-9 && abs(back.b - color.b) < 1e-9)
    }
}
