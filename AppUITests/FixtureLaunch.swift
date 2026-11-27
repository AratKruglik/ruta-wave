import XCTest

extension XCUIApplication {
    func launchWithFixtures(route: String? = nil, extraArguments: [String] = []) {
        launchArguments = ["-UITestFixtures", "-ApplePersistenceIgnoreState", "YES"]
            + (route.map { ["-UITestRoute", $0] } ?? [])
            + extraArguments
        launch()
    }
}
