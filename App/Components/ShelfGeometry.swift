import CoreGraphics

enum ShelfGeometry {
    static func fit(width: CGFloat, minimum: CGFloat, spacing: CGFloat) -> (count: Int, itemWidth: CGFloat) {
        guard width > 0 else { return (1, minimum) }
        let count = max(1, Int((width + spacing) / (minimum + spacing)))
        return (count, max(minimum, (width - spacing * CGFloat(count - 1)) / CGFloat(count)))
    }
}
