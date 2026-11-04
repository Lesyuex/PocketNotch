@testable import StockModule
import Foundation
import XCTest

private struct StubStockMarketDataProvider: StockMarketDataProviding {
    let snapshot: StockIntradaySnapshot

    func fetchIntraday(for code: String) async throws -> StockIntradaySnapshot {
        snapshot
    }
}

@MainActor
final class StockNotificationViewModelTests: XCTestCase {
    func testRefreshReplacesSampleIntradayAndQuote() async throws {
        let suiteName = "StockNotificationViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let points = [
            StockIntradayPoint(minute: 0, price: 100, averagePrice: 100, volume: 10),
            StockIntradayPoint(minute: 1, price: 102, averagePrice: 101, volume: 20)
        ]
        let buyLevels = [StockOrderBookLevel(level: 1, price: 101.90, volume: 12)]
        let sellLevels = [StockOrderBookLevel(level: 1, price: 102.10, volume: 18)]
        let trades = [
            StockTrade(
                id: 1,
                time: "10:00:00",
                price: 102,
                priceChange: 0.1,
                volume: 5,
                amount: 51_000,
                side: .buy
            )
        ]
        let snapshot = StockIntradaySnapshot(
            code: "600519",
            name: "贵州茅台",
            decimalPlaces: 2,
            openPrice: 99.80,
            previousClose: 100,
            points: points,
            buyLevels: buyLevels,
            sellLevels: sellLevels,
            trades: trades
        )
        let viewModel = StockNotificationViewModel(
            settings: StockSettings(defaults: defaults),
            marketDataProvider: StubStockMarketDataProvider(snapshot: snapshot)
        )

        await viewModel.refreshMarketData(for: "600519")

        let quote = try XCTUnwrap(viewModel.quotes.first { $0.id == "600519" })
        XCTAssertEqual(quote.price, "102.00")
        XCTAssertEqual(quote.change, "+2.00%")
        XCTAssertTrue(viewModel.isMarketDataLive(for: quote.id))
        XCTAssertEqual(viewModel.marketSeries(for: quote).openPrice, 99.80)
        XCTAssertEqual(viewModel.marketSeries(for: quote).intraday, points)
        XCTAssertEqual(viewModel.marketSeries(for: quote).buyLevels, buyLevels)
        XCTAssertEqual(viewModel.marketSeries(for: quote).sellLevels, sellLevels)
        XCTAssertEqual(viewModel.marketSeries(for: quote).trades, trades)
        XCTAssertNil(viewModel.marketDataError(for: quote.id))
    }
}
