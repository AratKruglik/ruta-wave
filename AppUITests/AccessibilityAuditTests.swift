import XCTest

@MainActor
final class AccessibilityAuditTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testHome() throws {
        launch()
        try expectAndAudit(app.staticTexts["Mixed for you"])
    }

    func testExplore() throws {
        launch(route: "rutawave://explore")
        try expectAndAudit(app.buttons["Relax"])
    }

    func testLibrary() throws {
        launch(route: "rutawave://library")
        try expectAndAudit(app.staticTexts["Enjoy your favourite music"])
    }

    func testSearchResults() throws {
        launch(route: "rutawave://search?q=radiohead")
        try expectAndAudit(app.descendants(matching: .any)["Community playlists"].firstMatch)
    }

    func testPlaylist() throws {
        launch(route: "rutawave://playlist?list=PL1")
        try expectAndAudit(app.descendants(matching: .any)["Test Playlist With A Fairly Long Title"].firstMatch)
    }

    func testPlayerPage() throws {
        launch()
        let open = app.buttons["Open player page"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.click()
        XCTAssertTrue(app.buttons["Close player page"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.sliders["Playback position"].exists)
        try audit()
    }

    private func launch(route: String? = nil) {
        app.launchWithFixtures(route: route)
    }

    private func expectAndAudit(_ element: XCUIElement) throws {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        try audit()
    }

    private func audit() throws {
        try app.performAccessibilityAudit(for: .all) { try Self.isKnownIssue($0) }
    }

    /// Entries are added only with a tracked issue number, one `if` per issue, e.g.
    /// `if issue.auditType == .contrast, issue.element?.label == "..." { return true } // #NNN`.
    private static func isKnownIssue(_ issue: XCUIAccessibilityAuditIssue) throws -> Bool {
        false
    }
}
