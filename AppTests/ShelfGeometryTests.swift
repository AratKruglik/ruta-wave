import CoreGraphics
import Testing


struct ShelfGeometryTests {
    @Test("Whole columns that fill the width", arguments: [
        (CGFloat(992), CGFloat(280), 3, CGFloat(320)),
        (CGFloat(992), CGFloat(440), 2, CGFloat(488)),
        (CGFloat(300), CGFloat(440), 1, CGFloat(440)),
        (CGFloat(0), CGFloat(440), 1, CGFloat(440)),
    ])
    func fit(width: CGFloat, minimum: CGFloat, count: Int, itemWidth: CGFloat) {
        let result = ShelfGeometry.fit(width: width, minimum: minimum, spacing: 16)
        #expect(result.count == count)
        #expect(result.itemWidth == itemWidth)
    }
}
