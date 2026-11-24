import CoreGraphics
import Testing

@MainActor
struct WindowLayoutTests {
    private let minSize = CGSize(width: Metrics.minWindowWidth, height: Metrics.minWindowHeight)
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test(arguments: [(960.0, true), (1099.0, true), (1100.0, false), (1280.0, false)])
    func narrowBelowThreshold(width: CGFloat, narrow: Bool) {
        #expect(WindowLayout.isNarrow(width: width) == narrow)
    }

    @Test func overrideWinsBothWays() {
        #expect(WindowLayout.isSidebarVisible(width: 1000, override: true, collapsedPreference: true))
        #expect(!WindowLayout.isSidebarVisible(width: 1400, override: false, collapsedPreference: false))
    }

    @Test func narrowWithoutOverrideHidesSidebar() {
        #expect(!WindowLayout.isSidebarVisible(width: 1000, override: nil, collapsedPreference: false))
    }

    @Test func wideFollowsPreference() {
        #expect(WindowLayout.isSidebarVisible(width: 1400, override: nil, collapsedPreference: false))
        #expect(!WindowLayout.isSidebarVisible(width: 1400, override: nil, collapsedPreference: true))
    }

    @Test(arguments: [(1200.0, 1000.0, true), (1000.0, 1050.0, false), (1100.0, 1099.0, true), (1099.0, 1100.0, true)])
    func thresholdCrossing(from: CGFloat, to: CGFloat, crosses: Bool) {
        #expect(WindowLayout.crossesCollapseThreshold(from: from, to: to) == crosses)
    }

    @Test func validFrameIsNotCorrected() {
        let frame = CGRect(x: 100, y: 100, width: 960, height: 600)
        #expect(WindowLayout.correctedFrame(frame, minSize: minSize, visible: screen) == nil)
        #expect(WindowLayout.correctedFrame(frame, minSize: minSize, visible: nil) == nil)
    }

    @Test func narrowFrameGrowsKeepingOrigin() throws {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 700)
        let corrected = try #require(WindowLayout.correctedFrame(frame, minSize: minSize, visible: screen))
        #expect(corrected == CGRect(x: 100, y: 100, width: 960, height: 700))
    }

    @Test func growthShiftsLeftToStayVisible() throws {
        let frame = CGRect(x: 1200, y: 100, width: 700, height: 700)
        let corrected = try #require(WindowLayout.correctedFrame(frame, minSize: minSize, visible: screen))
        #expect(corrected.maxX == screen.maxX)
        #expect(corrected.width == 960)
    }

    @Test func shortFrameGrowsKeepingTopEdge() throws {
        let frame = CGRect(x: 100, y: 500, width: 1000, height: 400)
        let corrected = try #require(WindowLayout.correctedFrame(frame, minSize: minSize, visible: screen))
        #expect(corrected.maxY == frame.maxY)
        #expect(corrected.height == 600)
    }

    @Test func frameExactlyAtMinimumIsNotCorrected() {
        let frame = CGRect(x: 0, y: 0, width: minSize.width, height: minSize.height)
        #expect(WindowLayout.correctedFrame(frame, minSize: minSize, visible: screen) == nil)
    }

    @Test func fullscreenAndOversizedFramesAreNotCorrected() {
        #expect(WindowLayout.correctedFrame(screen, minSize: minSize, visible: screen) == nil)
        let oversized = CGRect(x: -200, y: -100, width: 2500, height: 1500)
        #expect(WindowLayout.correctedFrame(oversized, minSize: minSize, visible: screen) == nil)
    }

    @Test func growthBelowVisibleBottomShiftsUp() throws {
        let frame = CGRect(x: 100, y: 0, width: 1000, height: 400)
        let corrected = try #require(WindowLayout.correctedFrame(frame, minSize: minSize, visible: screen))
        #expect(corrected == CGRect(x: 100, y: 0, width: 1000, height: 600))
    }

    @Test func growthWithoutVisibleAreaKeepsTopLeft() throws {
        let frame = CGRect(x: -50, y: 300, width: 500, height: 300)
        let corrected = try #require(WindowLayout.correctedFrame(frame, minSize: minSize, visible: nil))
        #expect(corrected == CGRect(x: -50, y: 0, width: 960, height: 600))
    }

    @Test func offscreenLeftFrameIsPulledIn() throws {
        let frame = CGRect(x: -300, y: 100, width: 800, height: 700)
        let corrected = try #require(WindowLayout.correctedFrame(frame, minSize: minSize, visible: screen))
        #expect(corrected.minX == screen.minX)
    }

    @Test func boundaryWidthsAtMinimumAndThreshold() {
        #expect(!WindowLayout.isNarrow(width: Metrics.sidebarAutoCollapseWidth))
        #expect(WindowLayout.isNarrow(width: Metrics.minWindowWidth))
        #expect(!WindowLayout.isSidebarVisible(width: Metrics.minWindowWidth, override: nil, collapsedPreference: false))
        #expect(WindowLayout.isSidebarVisible(width: Metrics.sidebarAutoCollapseWidth, override: nil, collapsedPreference: false))
    }

    @Test func tooSmallScreenIsLeftAlone() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 500)
        let tiny = CGRect(x: 0, y: 0, width: 900, height: 500)
        #expect(WindowLayout.correctedFrame(frame, minSize: minSize, visible: tiny) == nil)
    }
}
