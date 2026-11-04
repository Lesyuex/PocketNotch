import PocketNotchCore
@testable import MediaModule
import XCTest

final class MusicSpectrumUpdateRateTests: XCTestCase {
    func testStandardKeepsFixedFrameRate() {
        XCTAssertFalse(MusicSpectrumUpdateRate.standard.followsDisplayRefreshRate)
        XCTAssertEqual(MusicSpectrumUpdateRate.standard.animationFrameRate, 30)
    }

    func testSmoothFollowsDisplayRefreshRate() {
        XCTAssertTrue(MusicSpectrumUpdateRate.smooth.followsDisplayRefreshRate)
        XCTAssertEqual(
            MusicSpectrumUpdateRate.smooth.animationFrameRate,
            DisplayRefreshRateMonitor.shared.refreshRate
        )
    }

    func testSmoothTitleReflectsCurrentRefreshRate() {
        let expected = Int(DisplayRefreshRateMonitor.shared.refreshRate)
        XCTAssertEqual(MusicSpectrumUpdateRate.smooth.title, "最高 \(expected) Fps")
    }

    func testDefaultIsSmooth() {
        XCTAssertTrue(MediaMonitoringSettings.defaultSpectrumUpdateRate.followsDisplayRefreshRate)
    }
}