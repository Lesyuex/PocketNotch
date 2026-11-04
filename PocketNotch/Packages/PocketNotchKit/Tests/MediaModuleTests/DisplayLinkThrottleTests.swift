import XCTest
@testable import MediaModule

final class DisplayLinkThrottleTests: XCTestCase {
    func testPassesFirstCallbackImmediately() {
        let throttle = DisplayLinkThrottle()
        XCTAssertTrue(throttle.shouldDispatch(at: 100.0))
    }

    func testSkipsCallbacksWithinTargetInterval() {
        let throttle = DisplayLinkThrottle(targetFrameRate: 60)
        XCTAssertTrue(throttle.shouldDispatch(at: 1000.0))
        // 每帧 4ms（高刷面板）回调应被压缩，60Hz 目标下 ~16.7ms 内不再派发。
        XCTAssertFalse(throttle.shouldDispatch(at: 1000.004))
        XCTAssertFalse(throttle.shouldDispatch(at: 1000.012))
        XCTAssertTrue(throttle.shouldDispatch(at: 1000.017))
    }

    func testCadenceMatchesTargetFrameRate() {
        let throttle = DisplayLinkThrottle(targetFrameRate: 60)
        var dispatchTimes: [Double] = []
        for i in 0..<1200 {
            let time = Double(i) / 240.0
            if throttle.shouldDispatch(at: time) { dispatchTimes.append(time) }
        }
        // 240Hz 回调 5s → 60Hz 节流后应为 ~300 次派发（t=0 起每 1/60s 一次）。
        XCTAssertEqual(dispatchTimes.count, 300)
        // 相邻派发间隔稳定在 ~16.67ms（高刷输入不漂移）。
        for j in 1..<dispatchTimes.count {
            let gap = dispatchTimes[j] - dispatchTimes[j - 1]
            XCTAssertEqual(gap, 1.0 / 60, accuracy: 1.0 / 240 + 0.0001)
        }
    }

    func testResetClearsThrottleWindow() {
        let throttle = DisplayLinkThrottle()
        XCTAssertTrue(throttle.shouldDispatch(at: 10.0))
        XCTAssertFalse(throttle.shouldDispatch(at: 10.005))
        throttle.reset()
        XCTAssertTrue(throttle.shouldDispatch(at: 10.005))
    }

    func testLowerTargetFrameRateThrottlesMore() {
        let throttle = DisplayLinkThrottle(targetFrameRate: 30)
        XCTAssertTrue(throttle.shouldDispatch(at: 0.0))
        XCTAssertFalse(throttle.shouldDispatch(at: 0.005))
        XCTAssertTrue(throttle.shouldDispatch(at: 0.034))
    }

    func testUpdatingTargetFrameRateResetsCadenceWindow() {
        let throttle = DisplayLinkThrottle(targetFrameRate: 60)

        XCTAssertTrue(throttle.shouldDispatch(at: 10.0))
        XCTAssertFalse(throttle.shouldDispatch(at: 10.01))

        throttle.updateTargetFrameRate(30)

        XCTAssertTrue(throttle.shouldDispatch(at: 10.01))
        XCTAssertFalse(throttle.shouldDispatch(at: 10.03))
        XCTAssertTrue(throttle.shouldDispatch(at: 10.044))
    }
}
