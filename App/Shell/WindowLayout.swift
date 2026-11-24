import CoreGraphics

enum WindowLayout {
    static func isNarrow(width: CGFloat) -> Bool { width < Metrics.sidebarAutoCollapseWidth }

    static func isSidebarVisible(width: CGFloat, override: Bool?, collapsedPreference: Bool) -> Bool {
        override ?? (!isNarrow(width: width) && !collapsedPreference)
    }

    static func crossesCollapseThreshold(from: CGFloat, to: CGFloat) -> Bool {
        isNarrow(width: from) != isNarrow(width: to)
    }

    /// nil when `frame` already meets `minSize`; otherwise grown to it, keeping the top-left corner and staying inside `visible`.
    /// shortcut: a `visible` area smaller than `minSize` is not a real Mac screen, so nothing is corrected there.
    static func correctedFrame(_ frame: CGRect, minSize: CGSize, visible: CGRect?) -> CGRect? {
        guard frame.width < minSize.width || frame.height < minSize.height else { return nil }
        if let visible, visible.width < minSize.width || visible.height < minSize.height { return nil }
        var corrected = CGRect(
            x: frame.minX, y: frame.maxY - max(frame.height, minSize.height),
            width: max(frame.width, minSize.width), height: max(frame.height, minSize.height))
        if let visible {
            corrected.origin.x = min(max(corrected.minX, visible.minX), visible.maxX - corrected.width)
            corrected.origin.y = min(max(corrected.minY, visible.minY), visible.maxY - corrected.height)
        }
        return corrected
    }
}
