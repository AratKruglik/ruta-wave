import AppKit
import ImageIO
import SwiftUI

@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSString, NSImage>()

    func cachedImage(for url: URL, pixelSize: CGFloat) -> NSImage? {
        cache.object(forKey: Self.key(url, pixelSize))
    }

    func image(for url: URL, pixelSize: CGFloat) async -> NSImage? {
        let key = Self.key(url, pixelSize)
        if let cached = cache.object(forKey: key) { return cached }
        guard let decoded = await Self.download(url, maxPixel: pixelSize) else { return nil }
        let image = NSImage(cgImage: decoded, size: .zero)
        cache.setObject(image, forKey: key)
        return image
    }

    private static func key(_ url: URL, _ pixelSize: CGFloat) -> NSString {
        "\(url.absoluteString)#\(Int(pixelSize))" as NSString
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
    var placeholderSymbol = "music.note"

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: NSImage?
    @State private var failed = false
    @State private var fadesIn = false

    var body: some View {
        ZStack {
            Rectangle().fill(.surfaceFill)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
                    .transition(.opacity)
            } else if url == nil || failed {
                Image(systemName: placeholderSymbol)
                    .font(.rwIcon(min(width, height) * 0.35))
                    .foregroundStyle(.textTertiary)
            }
        }
        .animation(fadesIn ? Motion.animation(Motion.panel, reduceMotion: reduceMotion) : nil, value: image)
        .frame(width: width, height: height)
        .clipShape(isCircle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius)))
        .task(id: url) {
            fadesIn = false
            image = nil
            failed = false
            guard let url else { return }
            let pixelSize = max(width, height) * displayScale
            if let cached = ArtworkCache.shared.cachedImage(for: url, pixelSize: pixelSize) {
                image = cached
                return
            }
            var loaded = await ArtworkCache.shared.image(for: url, pixelSize: pixelSize)
            if loaded == nil {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                loaded = await ArtworkCache.shared.image(for: url, pixelSize: pixelSize)
            }
            guard !Task.isCancelled else { return }
            fadesIn = true
            image = loaded
            failed = loaded == nil
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ArtworkImage(url: nil, width: 180, height: 180).padding().background(.themeBase)
}
