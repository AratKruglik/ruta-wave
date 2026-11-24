import Foundation

/// Colour math for the artwork theme: pure, so it can be tested and moved behind the plugin boundary as is.
nonisolated enum ThemeColor {
    struct HSB: Equatable {
        var h: Double
        var s: Double
        var b: Double
    }

    /// The neutral base, `#313131`.
    static let neutral = HSB(h: 0, s: 0, b: 0x31 / 255.0)
    static let headerLift = 0.15
    static let maxSaturation = 0.45
    static let brightnessRange = 0.18...0.28

    /// Keeps the artwork's hue and pulls saturation and brightness into the range 07 §3.2 guarantees text contrast for.
    static func base(fromAverage rgb: (r: Double, g: Double, b: Double)) -> HSB {
        let value = hsb(from: rgb)
        return HSB(
            h: value.h, s: min(value.s, maxSaturation),
            b: min(max(value.b, brightnessRange.lowerBound), brightnessRange.upperBound))
    }

    static func lighter(_ color: HSB, by fraction: Double) -> HSB {
        HSB(h: color.h, s: color.s, b: min(color.b * (1 + fraction), 1))
    }

    static func hsb(from rgb: (r: Double, g: Double, b: Double)) -> HSB {
        let r = min(max(rgb.r, 0), 1), g = min(max(rgb.g, 0), 1), b = min(max(rgb.b, 0), 1)
        let high = max(r, g, b), low = min(r, g, b), delta = high - low
        var hue = 0.0
        if delta > 0 {
            switch high {
            case r: hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            case g: hue = (b - r) / delta + 2
            default: hue = (r - g) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return HSB(h: hue, s: high == 0 ? 0 : delta / high, b: high)
    }

    static func rgb(from color: HSB) -> (r: Double, g: Double, b: Double) {
        let h = color.h * 6, chroma = color.b * color.s
        let x = chroma * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = color.b - chroma
        let parts: (Double, Double, Double) = switch Int(h) % 6 {
        case 0: (chroma, x, 0)
        case 1: (x, chroma, 0)
        case 2: (0, chroma, x)
        case 3: (0, x, chroma)
        case 4: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        return (parts.0 + m, parts.1 + m, parts.2 + m)
    }

    static func relativeLuminance(_ rgb: (r: Double, g: Double, b: Double)) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.r) + 0.7152 * linear(rgb.g) + 0.0722 * linear(rgb.b)
    }

    static func contrast(_ a: (r: Double, g: Double, b: Double), _ b: (r: Double, g: Double, b: Double)) -> Double {
        let first = relativeLuminance(a), second = relativeLuminance(b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}
