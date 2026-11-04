import PocketNotchCore
@testable import ApplicationsModule
import XCTest

final class ApplicationPageLayoutTests: XCTestCase {
    func testPageHasFiveRowsAndSevenColumns() {
        XCTAssertEqual(ApplicationPageLayout.rowCount, 5)
        XCTAssertEqual(ApplicationPageLayout.columnCount, 7)
        XCTAssertEqual(ApplicationPageLayout.itemsPerPage, 35)
        XCTAssertEqual(ApplicationPageLayout.gridHeight, 444)
        XCTAssertEqual(ApplicationPageLayout.contentHeight, 484)
    }

    func testLargerIconsAndLabelsFitCompactTileWithoutClipping() {
        XCTAssertEqual(ApplicationPageLayout.iconSize, 60)
        XCTAssertEqual(ApplicationPageLayout.rowSpacing, 16)
        XCTAssertEqual(ApplicationPageLayout.columnSpacing, 16)
        XCTAssertEqual(ApplicationPageLayout.tileHeight, 76)
        XCTAssertEqual(
            ApplicationPageLayout.tileHeight,
            ApplicationPageLayout.iconSize
                + ApplicationPageLayout.iconLabelSpacing
                + ApplicationPageLayout.labelHeight
        )
    }

    func testModuleRequestsEnoughSpaceForGridAndFooter() {
        let module = ApplicationsModule()
        XCTAssertEqual(module.expandedPagePreferredContentHeight, ApplicationPageLayout.contentHeight)
        XCTAssertLessThanOrEqual(ApplicationPageLayout.contentHeight, IslandLayoutToken.maximumExpandedContentHeight)

        let metrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 220, height: 38),
            notchPhysicalWidth: 220,
            expandedModuleCount: 1,
            preferredExpandedContentHeight: module.expandedPagePreferredContentHeight
        )
        XCTAssertGreaterThanOrEqual(metrics.expandedWidth, 756)
        XCTAssertEqual(
            metrics.expandedHeight - metrics.hiddenHeight,
            ApplicationPageLayout.contentHeight
                + IslandLayoutToken.expandedContentTopInset
                + IslandLayoutToken.expandedContentVerticalInset
        )
    }

    func testExpandedWindowBudgetContainsApplicationsPage() {
        let maximumMetrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 220, height: 38),
            notchPhysicalWidth: 220,
            expandedModuleCount: 1,
            preferredRestingHeight: IslandAppearanceConstraints.maximumRestingHeight,
            preferredCompactOuterInset: IslandAppearanceConstraints.maximumCompactOuterInset,
            preferredCompactVerticalInset: IslandAppearanceConstraints.maximumCompactVerticalInset,
            preferredCompactWidth: IslandAppearanceConstraints.maximumCompactWidth,
            preferredExpandedContentHeight: IslandLayoutToken.maximumExpandedContentHeight
        )
        let applicationMetrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 220, height: 38),
            notchPhysicalWidth: 220,
            expandedModuleCount: 1,
            preferredExpandedContentHeight: ApplicationPageLayout.contentHeight
        )
        XCTAssertGreaterThanOrEqual(maximumMetrics.expandedWidth, applicationMetrics.expandedWidth)
        XCTAssertGreaterThanOrEqual(
            maximumMetrics.expandedHeight,
            38 + ApplicationPageLayout.contentHeight
                + IslandLayoutToken.expandedContentTopInset
                + IslandLayoutToken.expandedContentVerticalInset
        )
    }

    func testEmptyCatalogHasNoPages() {
        XCTAssertTrue(ApplicationPageLayout.pages(for: []).isEmpty)
    }

    func testExactPageDoesNotAddEmptyTrailingPage() {
        XCTAssertEqual(ApplicationPageLayout.pages(for: applications(count: 70)).map(\.count), [35, 35])
    }

    func testPartialPagePreservesCatalogOrderWithoutDuplicates() {
        let catalog = applications(count: 73)
        let pages = ApplicationPageLayout.pages(for: catalog)
        XCTAssertEqual(pages.map(\.count), [35, 35, 3])
        XCTAssertEqual(pages.flatMap { $0 }, catalog)
    }

    func testLongFlickMovesAtMostOnePage() {
        XCTAssertEqual(destination(from: 1, proposed: 6_000, velocity: 2_000), 2)
        XCTAssertEqual(destination(from: 3, proposed: -6_000, velocity: -2_000), 2)
    }

    func testShortDeliberateSwipeAdvancesBeforeHalfPage() {
        XCTAssertEqual(destination(from: 1, proposed: 760), 2)
        XCTAssertEqual(destination(from: 1, proposed: 520), 0)
    }

    func testSmallSlowMovementReturnsToCurrentPage() {
        XCTAssertEqual(destination(from: 1, proposed: 672, velocity: 40), 1)
        XCTAssertEqual(destination(from: 1, proposed: 608, velocity: -40), 1)
    }

    func testShortFastFlickAdvances() {
        XCTAssertEqual(destination(from: 1, proposed: 672, velocity: 400), 2)
        XCTAssertEqual(destination(from: 1, proposed: 608, velocity: -400), 0)
    }

    func testVelocityWithoutHorizontalTravelDoesNotAdvance() {
        XCTAssertEqual(destination(from: 1, proposed: 640, velocity: 500), 1)
        XCTAssertEqual(destination(from: 1, proposed: 644, velocity: 500), 1)
    }

    func testPageEdgesDoNotWrap() {
        XCTAssertEqual(destination(from: 0, proposed: -300, velocity: -600), 0)
        XCTAssertEqual(destination(from: 4, proposed: 3_200, velocity: 600), 4)
    }

    func testSinglePageAlwaysRemainsOnFirstPage() {
        XCTAssertEqual(ApplicationPageLayout.destination(
            originalOffset: 0, proposedOffset: 500, velocity: 600,
            pageWidth: 640, pageCount: 1
        ), 0)
    }

    func testInterruptedScrollResolvesFromNearestPage() {
        XCTAssertEqual(ApplicationPageLayout.destination(
            originalOffset: 620, proposedOffset: 510, velocity: -400,
            pageWidth: 640, pageCount: 5
        ), 0)
    }

    func testEmptyOrInvalidGeometryResolvesToFirstPage() {
        for width: CGFloat in [0, -1, .nan, .infinity] {
            XCTAssertEqual(ApplicationPageLayout.destination(
                originalOffset: 0, proposedOffset: 100, velocity: 0,
                pageWidth: width, pageCount: 5
            ), 0)
        }
        XCTAssertEqual(ApplicationPageLayout.destination(
            originalOffset: 0, proposedOffset: 100, velocity: 0,
            pageWidth: 640, pageCount: 0
        ), 0)
        XCTAssertEqual(destination(from: 1, proposed: .nan), 0)
    }

    func testSystemSwipeDirectionUsesAppKitDeltaConvention() {
        XCTAssertEqual(ApplicationPageLayout.swipeDirection(horizontal: 1, vertical: 0), 1)
        XCTAssertEqual(ApplicationPageLayout.swipeDirection(horizontal: -1, vertical: 0), -1)
    }

    func testVerticalAndAmbiguousSwipesAreIgnored() {
        XCTAssertNil(ApplicationPageLayout.swipeDirection(horizontal: 0, vertical: 1))
        XCTAssertNil(ApplicationPageLayout.swipeDirection(horizontal: 1, vertical: 1))
        XCTAssertNil(ApplicationPageLayout.swipeDirection(horizontal: 0, vertical: 0))
        XCTAssertNil(ApplicationPageLayout.swipeDirection(horizontal: .nan, vertical: 0))
    }

    private func destination(from page: Int, proposed: CGFloat, velocity: CGFloat = 0) -> Int {
        ApplicationPageLayout.destination(
            originalOffset: CGFloat(page) * 640,
            proposedOffset: proposed,
            velocity: velocity,
            pageWidth: 640,
            pageCount: 5
        )
    }

    private func applications(count: Int) -> [ApplicationItem] {
        (0..<count).map { index in
            ApplicationItem(
                url: URL(fileURLWithPath: "/Applications/App\(index).app"),
                name: "App \(index)"
            )
        }
    }
}
