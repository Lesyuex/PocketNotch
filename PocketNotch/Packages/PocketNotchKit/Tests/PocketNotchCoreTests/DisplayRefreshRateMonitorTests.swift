@testable import PocketNotchCore
import XCTest

final class DisplayRefreshRateMonitorTests: XCTestCase {
    func testResolvesHighestRefreshRateAcrossScreens() {
        XCTAssertEqual(DisplayRefreshRateMonitor.resolveRefreshRate([60, 120, 60]), 120)
        XCTAssertEqual(DisplayRefreshRateMonitor.resolveRefreshRate([144, 60]), 144)
        XCTAssertEqual(DisplayRefreshRateMonitor.resolveRefreshRate([60]), 60)
    }

    func testFixedRateScreensAreSkipped() {
        XCTAssertEqual(DisplayRefreshRateMonitor.resolveRefreshRate([nil, 120]), 120)
    }

    func testInvalidValuesFallBackTo60() {
        XCTAssertEqual(DisplayRefreshRateMonitor.resolveRefreshRate([]), 60)
        XCTAssertEqual(DisplayRefreshRateMonitor.resolveRefreshRate([nil, nil]), 60)
        XCTAssertEqual(DisplayRefreshRateMonitor.resolveRefreshRate([0, -1]), 60)
    }
}