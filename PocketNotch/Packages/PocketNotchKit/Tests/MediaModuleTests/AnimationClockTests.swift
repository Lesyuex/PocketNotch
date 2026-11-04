import XCTest
@testable import MediaModule

final class AnimationClockTests: XCTestCase {
    func testFirstSampleReturnsZeroDelta() {
        var clock = AnimationClock()

        XCTAssertEqual(clock.sample(at: 100), 0)
    }

    func testKeepsNormalFrameDelta() {
        var clock = AnimationClock()
        _ = clock.sample(at: 100)

        XCTAssertEqual(clock.sample(at: 100 + 1.0 / 60.0), 1.0 / 60.0, accuracy: 0.0001)
    }

    func testClampsLongStallToMaxDelta() {
        var clock = AnimationClock()
        _ = clock.sample(at: 100)

        XCTAssertEqual(clock.sample(at: 100.12), 1.0 / 30.0, accuracy: 0.0001)
    }

    func testDoesNotReturnNegativeDeltaWhenTimeMovesBackwards() {
        var clock = AnimationClock()
        _ = clock.sample(at: 100)

        XCTAssertEqual(clock.sample(at: 99.9), 0)
    }

    func testResetStartsANewTimeline() {
        var clock = AnimationClock()
        _ = clock.sample(at: 100)
        clock.reset()

        XCTAssertEqual(clock.sample(at: 150), 0)
    }
}
