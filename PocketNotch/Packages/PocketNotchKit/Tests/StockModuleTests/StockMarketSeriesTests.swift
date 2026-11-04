@testable import StockModule
import XCTest

final class StockMarketSeriesTests: XCTestCase {
    func testSampleSeriesMatchesQuoteAndProducesValidCandles() throws {
        let quote = StockQuote(
            id: "600519",
            name: "贵州茅台",
            code: "600519",
            price: "1,478.00",
            change: "+1.26%",
            isPositive: true,
            changeAmount: "+18.50",
            volume: "12.3k"
        )

        let series = StockMarketSeries.sample(for: quote)
        let lastIntradayPoint = try XCTUnwrap(series.intraday.last)
        let lastCandle = try XCTUnwrap(series.candles.last)

        XCTAssertEqual(series.intraday.count, 49)
        XCTAssertEqual(lastIntradayPoint.price, quote.numericPrice, accuracy: 0.000_1)
        XCTAssertEqual(series.candles.count, 24)
        XCTAssertEqual(lastCandle.close, quote.numericPrice, accuracy: 0.000_1)
        XCTAssertEqual(series.buyLevels.count, 5)
        XCTAssertEqual(series.buyLevels.map(\.level), [1, 2, 3, 4, 5])
        XCTAssertEqual(series.sellLevels.count, 5)
        XCTAssertEqual(series.sellLevels.map(\.level), [1, 2, 3, 4, 5])

        for candle in series.candles {
            XCTAssertGreaterThanOrEqual(candle.high, max(candle.open, candle.close))
            XCTAssertLessThanOrEqual(candle.low, min(candle.open, candle.close))
            XCTAssertGreaterThan(candle.high, candle.low)
        }

        for pair in zip(series.buyLevels, series.buyLevels.dropFirst()) {
            XCTAssertGreaterThan(pair.0.price, pair.1.price)
            XCTAssertGreaterThan(pair.0.volume, 0)
        }

        for pair in zip(series.sellLevels, series.sellLevels.dropFirst()) {
            XCTAssertLessThan(pair.0.price, pair.1.price)
            XCTAssertGreaterThan(pair.0.volume, 0)
        }
    }

    func testNegativeChangeProducesPreviousCloseAboveCurrentPrice() {
        let quote = StockQuote(
            id: "002036",
            name: "联创电子",
            code: "002036",
            price: "7.37",
            change: "-5.38%",
            isPositive: false,
            changeAmount: "-0.42",
            volume: "85.6k"
        )

        let series = StockMarketSeries.sample(for: quote)

        XCTAssertGreaterThan(series.previousClose, quote.numericPrice)
    }
}
