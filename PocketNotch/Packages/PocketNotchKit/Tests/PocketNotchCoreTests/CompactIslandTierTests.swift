import XCTest
@testable import PocketNotchCore

final class CompactIslandTierTests: XCTestCase {
    func testWidthThresholdSelectsTier() {
        XCTAssertEqual(
            CompactIslandTier.resolved(forWidth: 344, stockDisplayActive: false),
            .first
        )
        XCTAssertEqual(
            CompactIslandTier.resolved(forWidth: 345, stockDisplayActive: false),
            .second
        )
    }

    func testActiveStockDisplayForcesSecondTierWidth() {
        XCTAssertEqual(
            CompactIslandTier.resolved(forWidth: 200, stockDisplayActive: true),
            .second
        )
        XCTAssertEqual(
            CompactIslandTier.resolvedPreferredWidth(nil, stockDisplayActive: true),
            345
        )
        XCTAssertEqual(
            CompactIslandTier.resolvedPreferredWidth(480, stockDisplayActive: true),
            480
        )
    }

    func testActiveStockDisplayOnlyRaisesWidthsBelowSecondTierMinimum() {
        XCTAssertEqual(
            CompactIslandTier.resolvedPreferredWidth(344, stockDisplayActive: true),
            345
        )
        XCTAssertEqual(
            CompactIslandTier.resolvedPreferredWidth(346, stockDisplayActive: true),
            346
        )
    }

    func testInactiveStockDisplayRestoresPreferredWidth() {
        XCTAssertEqual(
            CompactIslandTier.resolvedPreferredWidth(360, stockDisplayActive: false),
            360
        )
        XCTAssertEqual(
            CompactIslandTier.resolvedPreferredWidth(
                CompactIslandTier.secondTierMinimumWidth,
                stockDisplayActive: false
            ),
            CompactIslandTier.secondTierMinimumWidth
        )
        XCTAssertNil(
            CompactIslandTier.resolvedPreferredWidth(nil, stockDisplayActive: false)
        )
    }

    func testSecondTierPreservesExpandedSideContentBudget() {
        let minimumExpandedSideWidth: CGFloat = 54
        let layout = ResolvedCompactIslandLayout.resolve(
            contentHeight: IslandAppearanceConstraints.defaultCompactHeight,
            notchPhysicalWidth: 0,
            preferredCompactWidth: CompactIslandTier.secondTierMinimumWidth
        )

        XCTAssertEqual(
            layout.bodyWidth,
            CompactIslandTier.secondTierMinimumWidth,
            accuracy: 0.001
        )
        // 二档宽度下耳朵随之加宽，侧区足以容纳二档内容。
        XCTAssertEqual(
            layout.leadingContentWidth,
            layout.trailingContentWidth,
            accuracy: 0.001
        )
        XCTAssertGreaterThanOrEqual(
            layout.leadingContentWidth,
            minimumExpandedSideWidth
        )
        XCTAssertGreaterThanOrEqual(
            layout.sideRegionWidth,
            minimumExpandedSideWidth
        )
    }

    @MainActor
    func testRealtimeContentUsesStockMediaWeatherPriority() {
        let suiteName = "CompactIslandTierTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = CompactResidentSettings(defaults: defaults)

        XCTAssertEqual(settings.activeModule, .none)

        settings.setWeatherMonitoringEnabled(true)
        XCTAssertEqual(settings.activeModule, .weather)

        settings.setMediaCompactDisplayActive(true)
        XCTAssertEqual(settings.activeModule, .media)

        settings.setStockMonitoringEnabled(true)
        XCTAssertEqual(settings.activeModule, .media)
        XCTAssertFalse(settings.isStockCompactDisplayActive)

        settings.selectedModule = .stocks
        XCTAssertEqual(settings.activeModule, .media)
        XCTAssertFalse(settings.isStockCompactDisplayActive)

        settings.setStockPriorityActive(true)
        XCTAssertEqual(settings.activeModule, .stocks)
        XCTAssertTrue(settings.isStockCompactDisplayActive)

        settings.setStockMonitoringEnabled(false)
        XCTAssertEqual(settings.activeModule, .media)
        XCTAssertFalse(settings.isStockCompactDisplayActive)

        settings.setMediaCompactDisplayActive(false)
        XCTAssertEqual(settings.activeModule, .weather)
    }

    @MainActor
    func testMediaInitialStateResolutionSuppressesWeatherUntilResolved() {
        let suiteName = "CompactIslandTierTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = CompactResidentSettings(defaults: defaults)

        settings.setWeatherMonitoringEnabled(true)
        XCTAssertEqual(settings.activeModule, .weather)

        settings.setMediaInitialStateResolving(true)
        XCTAssertEqual(settings.activeModule, .none)

        settings.setMediaCompactDisplayActive(true)
        XCTAssertEqual(settings.activeModule, .media)

        settings.setMediaCompactDisplayActive(false)
        XCTAssertEqual(settings.activeModule, .none)

        settings.setMediaInitialStateResolving(false)
        XCTAssertEqual(settings.activeModule, .weather)
    }

    @MainActor
    func testStockPriorityStillWinsWhileMediaInitialStateIsResolving() {
        let suiteName = "CompactIslandTierTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = CompactResidentSettings(defaults: defaults)

        settings.selectedModule = .stocks
        settings.setStockMonitoringEnabled(true)
        settings.setStockPriorityActive(true)
        settings.setWeatherMonitoringEnabled(true)
        settings.setMediaInitialStateResolving(true)

        XCTAssertEqual(settings.activeModule, .stocks)
    }

    @MainActor
    func testResidentPriorityTableOrder() {
        // 显式优先级表：股票 > 音乐 > 天气 > 不常驻。
        let stocks = CompactResidentModule.stocks.priority
        let media = CompactResidentModule.media.priority
        let weather = CompactResidentModule.weather.priority
        let none = CompactResidentModule.none.priority

        XCTAssertGreaterThan(stocks, media)
        XCTAssertGreaterThan(media, weather)
        XCTAssertGreaterThan(weather, none)
    }

    @MainActor
    func testAgentDisplayStepsAsideForStockAndMediaWeather() {
        let suiteName = "CompactIslandTierTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = CompactResidentSettings(defaults: defaults)

        // 股票常驻激活（用户报告的冲突场景）。
        settings.selectedModule = .stocks
        settings.setStockMonitoringEnabled(true)
        settings.setStockPriorityActive(true)
        settings.setWeatherMonitoringEnabled(true)
        XCTAssertEqual(settings.activeModule, .stocks)

        // Agent 运行中：常驻内容整体让位，独占灵动岛。
        settings.setAgentDisplayActive(true)
        XCTAssertEqual(settings.activeModule, .none)
        XCTAssertTrue(settings.isStockCompactDisplayActive)
        // 宽度也回缩：股票不再驱动二档长度。
        XCTAssertFalse(settings.isStockDisplayActiveForLayout)

        // Agent 结束：股票常驻恢复。
        settings.setAgentDisplayActive(false)
        XCTAssertEqual(settings.activeModule, .stocks)
        XCTAssertTrue(settings.isStockDisplayActiveForLayout)

        // 同样验证媒体常驻在 Agent 运行时也让位。
        settings.setStockMonitoringEnabled(false)
        settings.setMediaCompactDisplayActive(true)
        XCTAssertEqual(settings.activeModule, .media)

        settings.setAgentDisplayActive(true)
        XCTAssertEqual(settings.activeModule, .none)

        settings.setAgentDisplayActive(false)
        XCTAssertEqual(settings.activeModule, .media)
    }
}
