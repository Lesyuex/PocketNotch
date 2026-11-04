import SwiftUI
import XCTest
import PocketNotchCore
@testable import MediaModule

final class VolumeBarFillResolverTests: XCTestCase {
    private let white = VolumeBarColor(red: 1, green: 1, blue: 1)
    private let red = VolumeBarColor(red: 1, green: 0, blue: 0)
    private let blue = VolumeBarColor(red: 0, green: 0, blue: 1)

    func testStandardStyleResolvesToWhiteSolid() {
        let fill = VolumeBarFillResolver.resolve(
            style: .standard,
            palette: [Color.red],
            hasActiveMedia: true,
            customColor: red,
            usesCustomGradient: true,
            customGradientEndColor: blue
        )

        assertSolid(fill, equals: white)
    }

    func testCoverThemeUsesPrimaryPaletteColorOnlyWhileMediaPlays() {
        let palette = Color(red: 0.1, green: 0.9, blue: 0.2)

        assertSolid(
            VolumeBarFillResolver.resolve(
                style: .coverTheme,
                palette: [palette],
                hasActiveMedia: true,
                customColor: red,
                usesCustomGradient: false,
                customGradientEndColor: blue
            ),
            equals: VolumeBarColor(color: palette)
        )

        assertSolid(
            VolumeBarFillResolver.resolve(
                style: .coverTheme,
                palette: [palette],
                hasActiveMedia: false,
                customColor: red,
                usesCustomGradient: false,
                customGradientEndColor: blue
            ),
            equals: white
        )
    }

    func testCoverThemeFallsBackToWhiteWithoutPalette() {
        assertSolid(
            VolumeBarFillResolver.resolve(
                style: .coverTheme,
                palette: [],
                hasActiveMedia: true,
                customColor: red,
                usesCustomGradient: false,
                customGradientEndColor: blue
            ),
            equals: white
        )
    }

    func testCoverThemeGradientUsesPrimaryAndSecondaryPaletteColors() {
        let primary = Color(red: 0.1, green: 0.9, blue: 0.2)
        let secondary = Color(red: 0.3, green: 0.4, blue: 0.5)

        assertGradient(
            VolumeBarFillResolver.resolve(
                style: .coverTheme,
                palette: [primary, secondary],
                hasActiveMedia: true,
                customColor: red,
                usesCustomGradient: true,
                customGradientEndColor: blue
            ),
            equalsStart: VolumeBarColor(color: primary),
            end: VolumeBarColor(color: secondary)
        )
    }

    func testCoverThemeGradientFallsBackToSolidWhenPaletteLacksSecondary() {
        let primary = Color(red: 0.1, green: 0.9, blue: 0.2)

        assertSolid(
            VolumeBarFillResolver.resolve(
                style: .coverTheme,
                palette: [primary],
                hasActiveMedia: true,
                customColor: red,
                usesCustomGradient: true,
                customGradientEndColor: blue
            ),
            equals: VolumeBarColor(color: primary)
        )
    }

    func testGradientStyleUsesHardcodedAppIconThemeColors() {
        let fill = VolumeBarFillResolver.resolve(
            style: .gradient,
            palette: [],
            hasActiveMedia: false,
            customColor: red,
            usesCustomGradient: false,
            customGradientEndColor: blue
        )

        assertGradient(
            fill,
            equalsStart: VolumeBarFillResolver.appIconGradientStart,
            end: VolumeBarFillResolver.appIconGradientEnd
        )
    }

    func testCustomGradientEnabledProducesTwoColorGradient() {
        let fill = VolumeBarFillResolver.resolve(
            style: .custom,
            palette: [],
            hasActiveMedia: false,
            customColor: red,
            usesCustomGradient: true,
            customGradientEndColor: blue
        )

        assertGradient(fill, equalsStart: red, end: blue)
    }

    func testCustomGradientDisabledUsesSingleColor() {
        assertSolid(
            VolumeBarFillResolver.resolve(
                style: .custom,
                palette: [],
                hasActiveMedia: false,
                customColor: red,
                usesCustomGradient: false,
                customGradientEndColor: blue
            ),
            equals: red
        )
    }

    private func assertSolid(_ fill: VolumeBarFillStyle, equals color: VolumeBarColor) {
        guard case .solid(let resolved) = fill else {
            return XCTFail("Expected solid fill")
        }
        XCTAssertEqual(resolved, color)
    }

    private func assertGradient(
        _ fill: VolumeBarFillStyle,
        equalsStart start: VolumeBarColor,
        end: VolumeBarColor
    ) {
        guard case .gradient(let resolvedStart, let resolvedEnd) = fill else {
            return XCTFail("Expected gradient fill")
        }
        XCTAssertEqual(resolvedStart, start)
        XCTAssertEqual(resolvedEnd, end)
    }
}