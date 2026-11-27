import AppKit
import Foundation
import SwiftUI
import Testing

struct AccessibilityThemeTests {
    private struct Variant {
        let rgb: (r: Double, g: Double, b: Double)
        let alpha: Double
    }

    /// The test bundle has no asset catalog, so the catalog's source JSON is the thing under test.
    private func variant(_ set: String, highContrast: Bool) throws -> Variant {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "App/Theme/Colors.xcassets/\(set).colorset/Contents.json")
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let colors = try #require(root["colors"] as? [[String: Any]])
        func matches(_ entry: [String: Any], dark: Bool) -> Bool {
            let appearances = (entry["appearances"] as? [[String: String]]) ?? []
            let isHighContrast = appearances.contains { $0["appearance"] == "contrast" }
            let isDark = appearances.contains { $0["appearance"] == "luminosity" }
            return isHighContrast == highContrast && isDark == dark
        }
        let entry = try #require(colors.first { matches($0, dark: true) } ?? colors.first { matches($0, dark: false) })
        let components = try #require((entry["color"] as? [String: Any])?["components"] as? [String: String])
        func value(_ key: String) throws -> Double {
            let text = try #require(components[key])
            return text.hasPrefix("0x") ? Double(try #require(Int(text.dropFirst(2), radix: 16))) / 255 : try #require(Double(text))
        }
        return Variant(rgb: (try value("red"), try value("green"), try value("blue")), alpha: try value("alpha"))
    }

    private func minimumContrast(of variant: Variant) -> Double {
        let extremes = stride(from: 0.0, to: 1.0, by: 1.0 / 36).flatMap { hue in
            [ThemeColor.HSB(h: hue, s: ThemeColor.maxSaturation, b: ThemeColor.brightnessRange.upperBound),
             ThemeColor.HSB(h: hue, s: ThemeColor.maxSaturation, b: ThemeColor.brightnessRange.lowerBound),
             ThemeColor.HSB(h: hue, s: 0, b: ThemeColor.brightnessRange.upperBound)]
        }
        return extremes.map { base in
            let background = ThemeColor.rgb(from: base)
            let alpha = variant.alpha
            let text = (r: alpha * variant.rgb.r + (1 - alpha) * background.r,
                        g: alpha * variant.rgb.g + (1 - alpha) * background.g,
                        b: alpha * variant.rgb.b + (1 - alpha) * background.b)
            return ThemeColor.contrast(text, background)
        }.min() ?? 0
    }

    @Test func defaultValuesAreUnchanged() throws {
        #expect(try variant("RWTextSecondary", highContrast: false).alpha == 0.70)
        #expect(try variant("RWStrokeSubtle", highContrast: false).alpha == 0.20)
        #expect(try variant("RWSurfaceFill", highContrast: false).alpha == 0.10)
        #expect(try variant("RWSurfaceRaised", highContrast: false).alpha == 0.12)
        #expect(try variant("RWSurfaceField", highContrast: false).alpha == 0.15)
        #expect(try variant("AccentColor", highContrast: false).rgb == (1, 0, 0x33 / 255.0))
        #expect(abs(try variant("RWTextTertiary", highContrast: false).rgb.r - 0xAA / 255.0) < 0.001)
        #expect(abs(try variant("RWTextDisabled", highContrast: false).rgb.r - 0x71 / 255.0) < 0.001)
    }

    @Test func defaultSecondaryTextKeepsFourPointFive() throws {
        #expect(minimumContrast(of: try variant("RWTextSecondary", highContrast: false)) >= 4.5)
    }

    @Test func highContrastSecondaryTextReachesSevenToOne() throws {
        #expect(minimumContrast(of: try variant("RWTextSecondary", highContrast: true)) >= 7)
    }

    @Test func highContrastStrokeReachesThreeToOne() throws {
        #expect(minimumContrast(of: try variant("RWStrokeSubtle", highContrast: true)) >= 3)
    }

    @Test(arguments: ["RWTextTertiary", "RWTextDisabled"])
    func highContrastGreyTextIsStrongerThanDefault(set: String) throws {
        #expect(minimumContrast(of: try variant(set, highContrast: true))
            > minimumContrast(of: try variant(set, highContrast: false)))
    }

    @Test(arguments: [(NSFont.TextStyle.callout, 12.0), (.body, 13.0), (.title3, 15.0)])
    func mappedTextStylesKeepTheirMacSize(style: NSFont.TextStyle, size: Double) {
        let actual = NSFont.preferredFont(forTextStyle: style).pointSize
        #expect(abs(Double(actual) - size) < 0.01)
    }

    @Test func reduceMotionDisablesAnimation() {
        #expect(Motion.animation(Motion.hover, reduceMotion: true) == nil)
        #expect(Motion.pageAnimation(reduceMotion: true) == nil)
        #expect(Motion.animation(Motion.hover, reduceMotion: false) != nil)
        #expect(Motion.pageAnimation(reduceMotion: false) != nil)
    }

    private var catalogURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "App/Theme/Colors.xcassets")
    }

    private func referencedAssetNames() throws -> [String] {
        let source = try String(contentsOf: catalogURL.deletingLastPathComponent().appending(path: "DesignTokens.swift"), encoding: .utf8)
        return source.matches(of: /\.asset\("([^"]+)"\)/).map { String($0.1) }
    }

    @Test func everyReferencedAssetExistsInTheCatalog() throws {
        let names = try referencedAssetNames()
        #expect(names.count >= 8)
        for name in names {
            let contents = catalogURL.appending(path: "\(name).colorset/Contents.json")
            #expect(FileManager.default.fileExists(atPath: contents.path), "missing colorset \(name)")
        }
    }

    @Test func everyReferencedAssetHasAHighContrastVariant() throws {
        for name in Set(try referencedAssetNames()) {
            _ = try variant(name, highContrast: true)
            _ = try variant(name, highContrast: false)
        }
    }

    @Test func highContrastSurfacesAreMoreOpaqueThanDefault() throws {
        for name in ["RWSurfaceFill", "RWSurfaceRaised", "RWSurfaceField"] {
            #expect(try variant(name, highContrast: true).alpha > variant(name, highContrast: false).alpha)
        }
    }

    @Test func motionDurationsKeepTheirValues() {
        #expect(Motion.hover == 0.12)
        #expect(Motion.panel == 0.2)
        #expect(Motion.animation(Motion.panel, reduceMotion: false) == .snappy(duration: Motion.panel))
        #expect(Motion.pageAnimation(reduceMotion: false) == .smooth)
    }
}
