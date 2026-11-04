import SwiftUI
@testable import PocketNotchCore
import XCTest

final class ExpandedIslandHeightTests: XCTestCase {
    func testPreferredExpandedContentHeightChangesOnlyExpandedHeight() {
        let base = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 220, height: 38),
            notchPhysicalWidth: 220,
            expandedModuleCount: 1
        )
        let stock = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 220, height: 38),
            notchPhysicalWidth: 220,
            expandedModuleCount: 1,
            preferredExpandedContentHeight: 280
        )

        XCTAssertEqual(stock.hiddenSize, base.hiddenSize)
        XCTAssertEqual(stock.expandedWidth, base.expandedWidth)
        XCTAssertEqual(stock.expandedHeight - base.expandedHeight, 158)
    }

    func testPreferredExpandedContentHeightIsClampedToSafeRange() {
        let tooShort = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 220, height: 38),
            notchPhysicalWidth: 220,
            expandedModuleCount: 1,
            preferredExpandedContentHeight: 80
        )
        let tooTall = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 220, height: 38),
            notchPhysicalWidth: 220,
            expandedModuleCount: 1,
            preferredExpandedContentHeight: 1_000
        )

        XCTAssertEqual(
            tooShort.expandedHeight - tooShort.hiddenHeight,
            IslandLayoutToken.expandedContentHeight
                + IslandLayoutToken.expandedContentTopInset
                + IslandLayoutToken.expandedContentVerticalInset
        )
        XCTAssertEqual(
            tooTall.expandedHeight - tooTall.hiddenHeight,
            IslandLayoutToken.maximumExpandedContentHeight
                + IslandLayoutToken.expandedContentTopInset
                + IslandLayoutToken.expandedContentVerticalInset
        )
    }

    func testPreferredExpandedContentWidthDerivesFromContentRatio() {
        let base = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 220, height: 38),
            notchPhysicalWidth: 220,
            expandedModuleCount: 1
        )
        let contentHeight = IslandLayoutToken.expandedContentHeight
        let minimal = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 220, height: 38),
            notchPhysicalWidth: 220,
            expandedModuleCount: 1,
            preferredExpandedContentHeight: contentHeight,
            preferredExpandedContentWidth: contentHeight * 2.7
        )

        XCTAssertEqual(minimal.expandedWidth, max(contentHeight * 2.7, minimal.hiddenWidth))
        XCTAssertLessThan(minimal.expandedWidth, base.expandedWidth)
        XCTAssertEqual(minimal.expandedHeight, base.expandedHeight)
    }

    func testMinimalExpandedHeightUsesDedicatedInsets() {
        let mediaHeight = IslandLayoutToken.expandedMinimalContentMediaHeight
        let minimal = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 220, height: 38),
            notchPhysicalWidth: 220,
            expandedModuleCount: 1,
            preferredExpandedContentHeight: mediaHeight,
            preferredExpandedContentWidth: mediaHeight * 2.7,
            minimumExpandedContentHeight: mediaHeight,
            expandedContentTopInset: IslandLayoutToken.expandedMinimalContentTopInset,
            expandedContentBottomInset: IslandLayoutToken.expandedMinimalContentBottomInset
        )

        XCTAssertEqual(
            minimal.expandedHeight - minimal.hiddenHeight,
            mediaHeight
                + IslandLayoutToken.expandedMinimalContentTopInset
                + IslandLayoutToken.expandedMinimalContentBottomInset
        )
    }

    func testPreferredExpandedContentWidthNeverNarrowsBelowHiddenWidth() {
        let minimal = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 220, height: 38),
            notchPhysicalWidth: 220,
            expandedModuleCount: 1,
            preferredExpandedContentHeight: 144,
            preferredExpandedContentWidth: 100
        )

        XCTAssertEqual(minimal.expandedWidth, minimal.hiddenWidth)
    }
}
