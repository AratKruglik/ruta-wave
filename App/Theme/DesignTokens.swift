import SwiftUI

extension Color {
    fileprivate init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}

extension ShapeStyle where Self == Color {
    static var themeBase: Color { Color(hex: 0x313131) }
    static var surfaceFill: Color { Color.white.opacity(0.10) }
    static var surfaceRaised: Color { Color.white.opacity(0.12) }
    static var surfaceField: Color { Color.white.opacity(0.15) }
    static var surfaceInverse: Color { Color(hex: 0xF1F1F1) }
    static var textPrimary: Color { Color(hex: 0xF1F1F1) }
    static var textSecondary: Color { Color.white.opacity(0.70) }
    static var textTertiary: Color { Color(hex: 0xAAAAAA) }
    static var textOnInverse: Color { Color(hex: 0x0F0F0F) }
    static var textDisabled: Color { Color(hex: 0x717171) }
    static var accentProgress: Color { Color(hex: 0xFF0033) }
    static var accentLink: Color { Color(hex: 0x3EA6FF) }
    static var strokeSubtle: Color { Color.white.opacity(0.20) }
    static var strokeFocus: Color { Color(hex: 0xF1F1F1) }
    static var scrim: Color { Color.black.opacity(0.60) }
}

extension Font {
    static let rwDisplay = Font.system(size: 40, weight: .bold)
    static let rwShelfTitle = Font.system(size: 24, weight: .bold)
    static let rwShelfStrapline = Font.system(size: 12)
    static let rwTab = Font.system(size: 14, weight: .medium)
    static let rwNav = Font.system(size: 16)
    static let rwNavSelected = Font.system(size: 16, weight: .medium)
    static let rwBody = Font.system(size: 14)
    static let rwTitle = Font.system(size: 14, weight: .medium)
    static let rwCaption = Font.system(size: 12)
    static let rwButton = Font.system(size: 14, weight: .medium)
    static let rwWordmark = Font.system(size: 20, weight: .bold)

    static func rwIcon(_ size: CGFloat) -> Font { .system(size: size) }
}

enum Metrics {
    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32
    static let space48: CGFloat = 48

    static let topBarHeight: CGFloat = 64
    static let trafficLightsInset: CGFloat = 80
    static let playerBarHeight: CGFloat = 64
    static let progressHeight: CGFloat = 3
    static let progressHoverHeight: CGFloat = 5
    static let sidebarWidth: CGFloat = 240
    static let sidebarAutoCollapseWidth: CGFloat = 1100
    static let minWindowWidth: CGFloat = 960
    static let minWindowHeight: CGFloat = 600
    static let defaultWindowWidth: CGFloat = 1280
    static let defaultWindowHeight: CGFloat = 800
    static let contentBottomMargin: CGFloat = 48

    static let radiusThumb: CGFloat = 4
    static let radiusCard: CGFloat = 8
    static let radiusTile: CGFloat = 12
    static let radiusCover: CGFloat = 12

    static let iconPin: CGFloat = 10
    static let iconRow: CGFloat = 16
    static let iconBar: CGFloat = 20
    static let iconSidebar: CGFloat = 24
    static let iconTransport: CGFloat = 28
    static let iconPlay: CGFloat = 36
    static let hitTarget: CGFloat = 32
    static let sidebarItemHeight: CGFloat = 48
    static let pillHeight: CGFloat = 32
    static let artworkSize: CGFloat = 40
    static let videoArtworkWidth: CGFloat = 71
    static let avatarSize: CGFloat = 32
    static let playerBarCenterMaxWidth: CGFloat = 560
}

enum Motion {
    static let hover = 0.12
    static let panel = 0.2
    static let toastDuration: Duration = .seconds(3)

    static func animation(_ duration: Double, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: duration)
    }
}
