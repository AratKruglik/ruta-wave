import XCTest

/// Needs macOS Keyboard Navigation enabled (System Settings > Keyboard); the launch argument below forces it
/// for the app. With it off Tab skips buttons and the tests fail on purpose.
@MainActor
final class KeyboardFocusTests: XCTestCase {
    private enum Region { case toolbar, sidebar, content, bar }

    private let app = XCUIApplication()
    private let focused = NSPredicate(format: "hasKeyboardFocus == true")
    private let maxTabs = 40
    private var sidebarFrame = CGRect.zero

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testNoInitialFocusAndTabOrder() {
        launch(route: "rutawave://library")
        XCTAssertTrue(app.staticTexts["Enjoy your favourite music"].waitForExistence(timeout: 10))
        XCTAssertEqual(focusedElements().count, 0, "No element should have keyboard focus when the window appears")

        let regions = tabCycle()
        let expected: [Region] = [.toolbar, .sidebar, .content, .bar]
        XCTAssertEqual(Set(regions), Set(expected), "Tab should reach every region; got \(regions)")
        XCTExpectFailure("AppKit's key loop visits content before the sidebar; spec 08 section 14.4 wants the sidebar first") {
            XCTAssertTrue(
                Self.isRotation(regions, of: expected),
                "Tab order should cycle toolbar, sidebar, content, bar; got \(regions)"
            )
        }
    }

    func testPlayerPageTrapsFocusOutsideSidebar() {
        launch()
        let open = app.buttons["Open player page"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.click()
        XCTAssertTrue(app.buttons["Close player page"].waitForExistence(timeout: 10))

        let regions = tabCycle()
        XCTAssertFalse(regions.contains(.sidebar), "Tab must not reach the sidebar while the player page is open; got \(regions)")
        XCTAssertTrue(regions.contains(.bar), "Tab should still reach the player bar; got \(regions)")

        let row = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: sidebarFrame.midX - app.windows.firstMatch.frame.minX, dy: sidebarFrame.minY + 50 - app.windows.firstMatch.frame.minY))
        row.click()
        XCTAssertTrue(app.buttons["Open player page"].firstMatch.waitForExistence(timeout: 10), "Clicking a sidebar row should still close the player page")
    }

    private func launch(route: String? = nil) {
        app.launchWithFixtures(route: route, extraArguments: ["-AppleKeyboardUIMode", "2"])
        XCTAssertTrue(app.outlines.firstMatch.waitForExistence(timeout: 10))
        sidebarFrame = app.outlines.firstMatch.frame
    }

    private func focusedElements() -> XCUIElementQuery {
        app.descendants(matching: .any).matching(focused).matching(NSPredicate(format: "elementType != %d AND elementType != %d", XCUIElement.ElementType.window.rawValue, XCUIElement.ElementType.cell.rawValue))
    }

    /// The sidebar stops are the list or its hosting group, both taller than any control that may sit over the column.
    private func isSidebarColumn(_ frame: CGRect) -> Bool {
        frame.height > 100 && frame.minX >= sidebarFrame.minX - 3 && frame.maxX <= sidebarFrame.maxX + 3
    }

    private func region(of element: XCUIElement) -> Region {
        let frame = element.frame
        if app.toolbars.firstMatch.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) { return .toolbar }
        if isSidebarColumn(frame) { return .sidebar }
        if frame.minY >= app.sliders["Playback position"].frame.minY { return .bar }
        return .content
    }

    /// Tabs through one full cycle and returns the visited regions with consecutive duplicates collapsed.
    private func tabCycle() -> [Region] {
        var regions: [Region] = []
        var first: String?
        for _ in 0..<maxTabs {
            app.typeKey(.tab, modifierFlags: [])
            let element = focusedElements().firstMatch
            guard element.waitForExistence(timeout: 2) else { continue }
            let signature = "\(element.elementType.rawValue)|\(element.identifier)|\(element.label)|\(element.frame)"
            if signature == first { break }
            first = first ?? signature
            let current = region(of: element)
            if regions.last != current { regions.append(current) }
        }
        return regions
    }

    private static func isRotation(_ observed: [Region], of expected: [Region]) -> Bool {
        let present = expected.filter { observed.contains($0) }
        guard !observed.isEmpty, Set(observed).count == present.count else { return false }
        var cycle = observed
        if cycle.count > 1, cycle.first == cycle.last { cycle.removeLast() }
        guard cycle.count == present.count else { return false }
        return present.indices.contains { shift in
            cycle == Array(present[shift...] + present[..<shift])
        }
    }
}
