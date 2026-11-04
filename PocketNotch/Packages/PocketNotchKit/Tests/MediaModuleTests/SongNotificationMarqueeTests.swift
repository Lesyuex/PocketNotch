import XCTest
@testable import MediaModule

final class SongNotificationMarqueeTests: XCTestCase {
    func testLongTextScrollsAcrossItsCompleteOverflow() {
        let metrics = SongNotificationMarquee.metrics(
            contentWidth: 620,
            availableWidth: 220
        )

        XCTAssertEqual(metrics.distance, 408, accuracy: 0.001)
        XCTAssertEqual(metrics.duration, 12.75, accuracy: 0.001)
        XCTAssertGreaterThan(metrics.distance, 160)
        XCTAssertGreaterThan(metrics.duration, 5)
    }

    func testSmallWidthDifferenceDoesNotStartMarquee() {
        let metrics = SongNotificationMarquee.metrics(
            contentWidth: 223,
            availableWidth: 220
        )

        XCTAssertEqual(metrics.distance, 0)
        XCTAssertEqual(metrics.duration, 0)
    }

    func testOneShotOffsetResetsAfterEndingHold() {
        let metrics = SongNotificationMarqueeMetrics(distance: 120, duration: 3)

        XCTAssertEqual(
            SongNotificationMarquee.oneShotOffset(elapsed: 0.5, metrics: metrics),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SongNotificationMarquee.oneShotOffset(
                elapsed: SongNotificationMarquee.initialHold + 1.5,
                metrics: metrics
            ),
            -60,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SongNotificationMarquee.oneShotOffset(
                elapsed: SongNotificationMarquee.initialHold + 3.1,
                metrics: metrics
            ),
            -120,
            accuracy: 0.001
        )

        XCTAssertEqual(
            SongNotificationMarquee.oneShotOffset(
                elapsed: SongNotificationMarquee.initialHold
                    + metrics.duration
                    + SongNotificationMarquee.endingHold
                    - 0.1,
                metrics: metrics
            ),
            -120,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SongNotificationMarquee.oneShotOffset(
                elapsed: SongNotificationMarquee.initialHold
                    + metrics.duration
                    + SongNotificationMarquee.endingHold
                    + 0.1,
                metrics: metrics
            ),
            0,
            accuracy: 0.001
        )
    }
}
