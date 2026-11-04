import XCTest
@testable import PocketNotchCore

final class AnimationFPSMeterTests: XCTestCase {
    func testUniform120HzStreamReportsZeroDroppedAndCorrectAverage() throws {
        let samples = uniformSamples(frames: 121, gap: 1.0 / 120.0)
        let text = try XCTUnwrap(
            AnimationFPSMeter.makeReport(
                label: "expand",
                samples: samples,
                targetRate: 120
            )
        )
        XCTAssertTrue(text.contains("frames=121"))
        XCTAssertTrue(text.contains("target=120Hz"))
        XCTAssertTrue(text.contains("dropped=0"))
        XCTAssertEqual(averageFPS(from: text) ?? 0, 120, accuracy: 0.5)
    }

    func testStallIsCountedAsDroppedFrame() throws {
        var samples: [CFTimeInterval] = [0]
        for index in 1...120 {
            let gap = index == 10 ? 0.05 : 1.0 / 120.0
            samples.append(samples[index - 1] + gap)
        }
        let text = try XCTUnwrap(
            AnimationFPSMeter.makeReport(
                label: "collapse",
                samples: samples,
                targetRate: 120
            )
        )
        XCTAssertTrue(text.contains("dropped=1"))
    }

    func testFewerThanTwoSamplesReturnsNil() {
        XCTAssertNil(
            AnimationFPSMeter.makeReport(label: "expand", samples: [], targetRate: 120)
        )
        XCTAssertNil(
            AnimationFPSMeter.makeReport(label: "expand", samples: [1.0], targetRate: 120)
        )
    }

    func testZeroDurationReturnsNil() {
        XCTAssertNil(
            AnimationFPSMeter.makeReport(
                label: "expand",
                samples: [1.0, 1.0],
                targetRate: 120
            )
        )
    }

    // MARK: - Helpers

    private func uniformSamples(frames: Int, gap: Double) -> [CFTimeInterval] {
        (0..<frames).map { Double($0) * gap }
    }

    private func averageFPS(from report: String) -> Double? {
        guard let range = report.range(of: "avg=([0-9.]+)", options: .regularExpression) else {
            return nil
        }
        return Double(report[range].dropFirst(4))
    }
}