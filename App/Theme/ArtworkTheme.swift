import AppKit
import SwiftUI

extension EnvironmentValues {
    /// The top of the header gradient: the theme base, lighter.
    @Entry var themeHeaderTop: Color = Color.neutralHeaderTop
}

extension Color {
    fileprivate static let neutralHeaderTop = Color(ThemeColor.lighter(ThemeColor.neutral, by: ThemeColor.headerLift))

    fileprivate init(_ color: ThemeColor.HSB) {
        self.init(hue: color.h, saturation: color.s, brightness: color.b)
    }
}

/// Tints the window with the playing track's artwork. Self-contained so it can later move behind the album-colour plugin.
@MainActor @Observable
final class ArtworkTheme {
    private(set) var base: Color = .themeBase
    private(set) var headerTop: Color = Color.neutralHeaderTop
    @ObservationIgnored private var generation = 0

    /// `nil` returns to the neutral base.
    func update(artworkURL: URL?) async {
        generation += 1
        let captured = generation
        guard let artworkURL else {
            reset()
            return
        }
        guard let image = await ArtworkCache.shared.image(for: artworkURL, pixelSize: Self.sampleSize),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let average = Self.average(of: cgImage), generation == captured else { return }
        let color = ThemeColor.base(fromAverage: average)
        base = Color(color)
        headerTop = Color(ThemeColor.lighter(color, by: ThemeColor.headerLift))
    }

    private func reset() {
        base = .themeBase
        headerTop = Color.neutralHeaderTop
    }

    private static let sampleSize: CGFloat = 32

    private static func average(of image: CGImage) -> (r: Double, g: Double, b: Double)? {
        let side = Int(sampleSize)
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var sums = (r: 0.0, g: 0.0, b: 0.0)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            sums.r += Double(pixels[index])
            sums.g += Double(pixels[index + 1])
            sums.b += Double(pixels[index + 2])
        }
        let divisor = Double(side * side) * 255
        return (sums.r / divisor, sums.g / divisor, sums.b / divisor)
    }
}

/// Fades from a lighter tone of the theme into the base behind an album or playlist page.
struct ThemeHeaderGradient: View {
    @Environment(\.themeBase) private var base
    @Environment(\.themeHeaderTop) private var top

    var body: some View {
        LinearGradient(colors: [top, base.opacity(0)], startPoint: .top, endPoint: .bottom)
            .frame(height: 400)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
