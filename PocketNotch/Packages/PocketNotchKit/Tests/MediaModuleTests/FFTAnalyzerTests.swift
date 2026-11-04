import Foundation
import XCTest
@testable import MediaModule

final class FFTAnalyzerTests: XCTestCase {
    func testUsesOnlyMostRecentFFTWindow() {
        let fftSize = 64
        let suffix = (0..<fftSize).map { index in
            sin(Float(index) * 0.21)
        }
        let prefixedSamples = [Float](repeating: 0.75, count: 17) + suffix

        let prefixedAnalyzer = FFTAnalyzer(fftSize: fftSize, sampleRate: 44_100, bandCount: 5)
        let suffixAnalyzer = FFTAnalyzer(fftSize: fftSize, sampleRate: 44_100, bandCount: 5)

        XCTAssertEqual(
            prefixedAnalyzer.magnitudes(from: prefixedSamples),
            suffixAnalyzer.magnitudes(from: suffix)
        )
    }

    func testInsufficientSamplesReturnSilentBands() {
        let analyzer = FFTAnalyzer(fftSize: 64, sampleRate: 44_100, bandCount: 5)

        XCTAssertEqual(
            analyzer.magnitudes(from: [Float](repeating: 1, count: 63)),
            [Float](repeating: 0, count: 5)
        )
    }

    func testHighFrequencyTonesDriveExpectedBands() {
        assertTone(frequency: 4_000, drivesBand: 3)
        assertTone(frequency: 10_000, drivesBand: 4)
    }

    func testSevenBandLayoutUsesIndependentFrequencyRanges() {
        assertTone(
            frequency: 80,
            drivesBand: 0,
            bandCount: 7,
            fftSize: 4_096,
            maximumLeakage: 0.2
        )
        assertTone(frequency: 130, drivesBand: 1, bandCount: 7, fftSize: 4_096)
        assertTone(frequency: 300, drivesBand: 2, bandCount: 7, fftSize: 4_096)
        assertTone(frequency: 800, drivesBand: 3, bandCount: 7, fftSize: 4_096)
        assertTone(frequency: 1_500, drivesBand: 4, bandCount: 7, fftSize: 4_096)
        assertTone(frequency: 4_000, drivesBand: 5, bandCount: 7, fftSize: 4_096)
        assertTone(frequency: 10_000, drivesBand: 6, bandCount: 7, fftSize: 4_096)
    }

    func testFiveBarRenderingAggregatesCompatibleSevenBandRanges() {
        let sampled: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7]
        let five = AudioSpectrumConfiguration.renderedLevels(
            from: sampled,
            configuration: MusicSpectrumConfiguration(
                style: .five,
                sensitivity: 0.5,
                attackTime: 0.02,
                releaseTime: 0.2
            )
        )
        let seven = AudioSpectrumConfiguration.renderedLevels(
            from: sampled,
            configuration: MusicSpectrumConfiguration(
                style: .seven,
                sensitivity: 0.5,
                attackTime: 0.02,
                releaseTime: 0.2
            )
        )

        XCTAssertEqual(five.count, 5)
        XCTAssertEqual(seven.count, 7)
        XCTAssertEqual(five[0], pow(CGFloat(0.2), 1.3), accuracy: 0.0001)
        XCTAssertEqual(five[2], pow(CGFloat(0.5), 1.1), accuracy: 0.0001)
    }

    func testSpectrumGeometryFitsMinimumCompactRightEarAtSliderExtremes() {
        for style in MusicSpectrumBarStyle.allCases {
            for widthScale in [0.0, 1.0] {
                for spacingScale in [0.0, 1.0] {
                    let geometry = MusicSpectrumBarGeometry.resolve(
                        configuration: MusicSpectrumConfiguration(
                            style: style,
                            sensitivity: 0.5,
                            attackTime: 0.02,
                releaseTime: 0.2,
                            barWidthScale: widthScale,
                            barSpacingScale: spacingScale
                        )
                    )

                    XCTAssertLessThanOrEqual(
                        geometry.totalWidth,
                        MusicSpectrumBarGeometry.minimumCompactRightEarWidth
                    )
                    XCTAssertGreaterThan(geometry.barWidth, 0)
                    XCTAssertGreaterThan(geometry.spacing, 0)
                }
            }
        }
    }

    func testSevenBarGeometryStaysThinnerThanFiveBars() {
        for widthScale in [0.0, 0.5, 1.0] {
            let five = MusicSpectrumBarGeometry.resolve(
                configuration: MusicSpectrumConfiguration(
                    style: .five,
                    sensitivity: 0.5,
                    attackTime: 0.02,
                releaseTime: 0.2,
                    barWidthScale: widthScale
                )
            )
            let seven = MusicSpectrumBarGeometry.resolve(
                configuration: MusicSpectrumConfiguration(
                    style: .seven,
                    sensitivity: 0.5,
                    attackTime: 0.02,
                releaseTime: 0.2,
                    barWidthScale: widthScale
                )
            )

            XCTAssertLessThan(seven.barWidth, five.barWidth)
        }

        let narrowestFive = MusicSpectrumBarGeometry.resolve(
            configuration: MusicSpectrumConfiguration(
                style: .five,
                sensitivity: 0.5,
                attackTime: 0.02,
                releaseTime: 0.2,
                barWidthScale: 0
            )
        )
        let widestSeven = MusicSpectrumBarGeometry.resolve(
            configuration: MusicSpectrumConfiguration(
                style: .seven,
                sensitivity: 0.5,
                attackTime: 0.02,
                releaseTime: 0.2,
                barWidthScale: 1
            )
        )
        XCTAssertLessThan(widestSeven.barWidth, narrowestFive.barWidth)
    }

    func testSpectrumCornerRadiusCoversSquareToCapsuleRange() {
        let square = MusicSpectrumBarGeometry.resolve(
            configuration: MusicSpectrumConfiguration(
                style: .five,
                sensitivity: 0.5,
                attackTime: 0.02,
                releaseTime: 0.2,
                barCornerRadiusScale: 0
            )
        )
        let capsule = MusicSpectrumBarGeometry.resolve(
            configuration: MusicSpectrumConfiguration(
                style: .five,
                sensitivity: 0.5,
                attackTime: 0.02,
                releaseTime: 0.2,
                barCornerRadiusScale: 1
            )
        )

        XCTAssertEqual(square.cornerRadius, 0)
        XCTAssertEqual(capsule.cornerRadius, capsule.barWidth / 2)
    }

    private func assertTone(
        frequency: Double,
        drivesBand expectedBand: Int,
        bandCount: Int = 5,
        fftSize: Int = 1_024,
        maximumLeakage: Float = 0.05,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let sampleRate = 44_100.0
        let analyzer = FFTAnalyzer(
            fftSize: fftSize,
            sampleRate: sampleRate,
            bandCount: bandCount
        )
        let samples = (0..<fftSize).map { index in
            Float(0.8 * sin(2 * Double.pi * frequency * Double(index) / sampleRate))
        }
        let bands = analyzer.magnitudes(from: samples)
        let dominantBand = bands.enumerated().max { lhs, rhs in
            lhs.element < rhs.element
        }?.offset
        let strongestOtherBand = bands.enumerated()
            .filter { $0.offset != expectedBand }
            .map(\.element)
            .max() ?? 0

        XCTAssertEqual(dominantBand, expectedBand, file: file, line: line)
        XCTAssertGreaterThan(bands[expectedBand], 0.6, file: file, line: line)
        XCTAssertLessThan(strongestOtherBand, maximumLeakage, file: file, line: line)
    }
}
