import XCTest
@testable import PocketNotchCore

final class CompactIslandWidthHeightIndependenceTests: XCTestCase {
    /// 岛高只控制高度：多出的高度全部变成耳朵的上下间距，岛宽与左右间距保持不变。
    func testIslandWidthIsIndependentOfIslandHeight() {
        func layout(islandHeight: CGFloat) -> ResolvedCompactIslandLayout {
            ResolvedCompactIslandLayout.resolve(
                contentHeight: 24,
                minimumIslandHeight: islandHeight,
                notchPhysicalWidth: 185,
                restingBodyWidth: 249,
                preferredCompactOuterInset: nil,
                preferredCompactVerticalInset: IslandAppearanceConstraints.resolvedCompactVerticalInset(
                    preferred: nil,
                    islandHeight: islandHeight
                ),
                preferredCompactWidth: nil,
                fitsAutomaticContentToMinimumHeight: false
            )
        }

        let short = layout(islandHeight: 32)
        let tall = layout(islandHeight: 48)

        XCTAssertEqual(short.islandWidth, tall.islandWidth, accuracy: 0.001)
        XCTAssertEqual(short.bodyWidth, tall.bodyWidth, accuracy: 0.001)
        XCTAssertEqual(short.sideRegionWidth, tall.sideRegionWidth, accuracy: 0.001)
        XCTAssertEqual(short.leadingContentWidth, tall.leadingContentWidth, accuracy: 0.001)
        XCTAssertEqual(short.trailingContentWidth, tall.trailingContentWidth, accuracy: 0.001)
        XCTAssertEqual(short.outerInset, tall.outerInset, accuracy: 0.001)
        XCTAssertEqual(short.innerGap, tall.innerGap, accuracy: 0.001)
        XCTAssertEqual(short.contentHeight, tall.contentHeight, accuracy: 0.001)

        XCTAssertGreaterThan(tall.verticalInset, short.verticalInset)
        XCTAssertEqual(short.verticalInset, 4, accuracy: 0.001)
        XCTAssertEqual(tall.verticalInset, 12, accuracy: 0.001)
    }

    /// 耳朵为自动（customEarHeight 为 nil，即默认）时，灵动岛宽也不得随岛高变化。
    func testCompactIslandWidthIsStableWhenEarHeightIsAutomatic() {
        func metrics(height: CGFloat) -> IslandBackgroundMetrics {
            IslandBackgroundMetrics.resolved(
                hiddenIslandSize: CGSize(width: 200, height: 32),
                notchPhysicalWidth: 185,
                expandedModuleCount: 1,
                showsCompactContent: true,
                preferredRestingHeight: height
            )
        }

        let heights: [CGFloat] = [32, 36, 40, 44, 48]
        let widths = heights.map { metrics(height: $0).hiddenWidth }
        for width in widths {
            XCTAssertEqual(width, widths[0], accuracy: 0.001)
        }
        let earHeights = heights.map { metrics(height: $0).hiddenHeight }
        XCTAssertEqual(earHeights[0], 32, accuracy: 0.001)
        XCTAssertEqual(earHeights[4], 48, accuracy: 0.001)
    }

    /// 隐藏态岛宽同样不随岛高变化。
    func testHiddenIslandWidthIsIndependentOfIslandHeight() {
        func metrics(height: CGFloat) -> IslandBackgroundMetrics {
            IslandBackgroundMetrics.resolved(
                hiddenIslandSize: CGSize(width: 200, height: 32),
                notchPhysicalWidth: 185,
                expandedModuleCount: 1,
                showsCompactContent: false,
                preferredRestingHeight: height
            )
        }

        XCTAssertEqual(
            metrics(height: 32).hiddenWidth,
            metrics(height: 48).hiddenWidth,
            accuracy: 0.001
        )
    }
}
