import AppKit
import ImageIO
import SwiftUI

@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(for url: URL, pixelSize: CGFloat) async -> NSImage? {
        let key = "\(url.absoluteString)#\(Int(pixelSize))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let decoded = await Self.download(url, maxPixel: pixelSize) else { return nil }
        let image = NSImage(cgImage: decoded, size: .zero)
        cache.setObject(image, forKey: key)
        return image
    }

    // Downsampling keeps a scrolling shelf from holding full-size covers in memory.
    private nonisolated static func download(_ url: URL, maxPixel: CGFloat) async -> CGImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Lays out its final frame immediately, so a loading cover never shifts the page.
struct ArtworkImage: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    var isCircle = false
    var cornerRadius = Metrics.radiusCard

    @Environment(\.displayScale) private var displayScale
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.surfaceFill)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
            }
        }
        .frame(width: width, height: height)
        .clipShape(isCircle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius)))
        .task(id: url) {
            image = nil
            guard let url else { return }
            image = await ArtworkCache.shared.image(for: url, pixelSize: max(width, height) * displayScale)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ArtworkImage(url: nil, width: 180, height: 180).padding().background(.themeBase)
}
