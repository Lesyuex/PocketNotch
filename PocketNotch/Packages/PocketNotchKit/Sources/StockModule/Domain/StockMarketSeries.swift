import Foundation

struct StockQuote: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let code: String
    let price: String
    let change: String
    let isPositive: Bool
    let changeAmount: String
    let volume: String

    var numericPrice: Double {
        Double(price.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    var changePercent: Double {
        Double(
            change
                .replacingOccurrences(of: "+", with: "")
                .replacingOccurrences(of: "%", with: "")
        ) ?? 0
    }

    var numericChangeAmount: Double {
        Double(changeAmount.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    var numericVolume: Double {
        let normalized = volume.lowercased().replacingOccurrences(of: ",", with: "")
        if normalized.hasSuffix("m") {
            return (Double(normalized.dropLast()) ?? 0) * 1_000_000
        }
        if normalized.hasSuffix("k") {
            return (Double(normalized.dropLast()) ?? 0) * 1_000
        }
        return Double(normalized) ?? 0
    }
}

struct StockIntradayPoint: Identifiable, Equatable, Sendable {
    let minute: Double
    let price: Double
    let averagePrice: Double?
    let volume: Int

    init(
        minute: Double,
        price: Double,
        averagePrice: Double? = nil,
        volume: Int = 0
    ) {
        self.minute = minute
        self.price = price
        self.averagePrice = averagePrice
        self.volume = volume
    }

    var id: Double { minute }
}

struct StockIntradaySnapshot: Equatable, Sendable {
    let code: String
    let name: String
    let decimalPlaces: Int
    let openPrice: Double
    let previousClose: Double
    let points: [StockIntradayPoint]
    let buyLevels: [StockOrderBookLevel]
    let sellLevels: [StockOrderBookLevel]
    let trades: [StockTrade]

    init(
        code: String,
        name: String,
        decimalPlaces: Int,
        openPrice: Double? = nil,
        previousClose: Double,
        points: [StockIntradayPoint],
        buyLevels: [StockOrderBookLevel] = [],
        sellLevels: [StockOrderBookLevel] = [],
        trades: [StockTrade] = []
    ) {
        self.code = code
        self.name = name
        self.decimalPlaces = decimalPlaces
        self.openPrice = openPrice ?? points.first?.price ?? previousClose
        self.previousClose = previousClose
        self.points = points
        self.buyLevels = buyLevels
        self.sellLevels = sellLevels
        self.trades = trades
    }

    var latestPrice: Double? { points.last?.price }
}

struct StockCandle: Identifiable, Equatable, Sendable {
    let index: Double
    let dateLabel: String
    let open: Double
    let high: Double
    let low: Double
    let close: Double

    var id: Double { index }
    var isRising: Bool { close >= open }
}

struct StockOrderBookLevel: Identifiable, Equatable, Sendable {
    let level: Int
    let price: Double
    let volume: Int

    var id: Int { level }
}

enum StockTradeSide: String, Equatable, Sendable {
    case buy = "B"
    case sell = "S"
    case neutral = "M"
}

struct StockTrade: Identifiable, Equatable, Sendable {
    let id: Int
    let time: String
    let price: Double
    let priceChange: Double
    let volume: Int
    let amount: Double
    let side: StockTradeSide
}

struct StockMarketSeries: Equatable, Sendable {
    let openPrice: Double
    let previousClose: Double
    let intraday: [StockIntradayPoint]
    let candles: [StockCandle]
    let buyLevels: [StockOrderBookLevel]
    let sellLevels: [StockOrderBookLevel]
    let trades: [StockTrade]

    static func sample(for quote: StockQuote) -> Self {
        let currentPrice = max(quote.numericPrice, 1)
        let changeFraction = quote.changePercent / 100
        let previousClose = currentPrice / max(1 + changeFraction, 0.01)
        let seedValue = quote.code.compactMap(\.wholeNumberValue).reduce(0, +)
        let seed = Double(seedValue)

        let intraday = (0..<49).map { index in
            let progress = Double(index) / 48
            let primaryWave = sin(progress * .pi * (3.2 + seed.truncatingRemainder(dividingBy: 3)))
            let secondaryWave = sin(progress * .pi * 8 + seed * 0.31)
            let deviation = changeFraction * progress
                + primaryWave * 0.0028
                + secondaryWave * 0.0012
            let price = index == 48
                ? currentPrice
                : previousClose * (1 + deviation)
            return StockIntradayPoint(
                minute: Double(index * 5),
                price: price,
                averagePrice: previousClose * (1 + deviation * 0.72),
                volume: 200 + (seedValue * 97 + index * 283) % 2_600
            )
        }

        let candles = (0..<24).map { index in
            let progress = Double(index) / 23
            let center = previousClose * (
                0.965
                    + progress * (0.035 + changeFraction)
                    + sin(progress * .pi * 3 + seed * 0.13) * 0.012
            )
            let open = center * (1 + sin(Double(index) * 1.17 + seed) * 0.0035)
            let close = index == 23
                ? currentPrice
                : center * (1 + cos(Double(index) * 0.91 + seed) * 0.0038)
            let wick = center * (0.0045 + Double(index % 4) * 0.0008)

            return StockCandle(
                index: Double(index),
                dateLabel: candleDateLabel(index: index),
                open: open,
                high: max(open, close) + wick,
                low: min(open, close) - wick * 0.86,
                close: close
            )
        }

        let buyLevels = (1...5).map { level in
            StockOrderBookLevel(
                level: level,
                price: currentPrice - Double(level) * 0.01,
                volume: 600 + (seedValue * 137 + level * 911) % 4_800
            )
        }

        let sellLevels = (1...5).map { level in
            StockOrderBookLevel(
                level: level,
                price: currentPrice + Double(level) * 0.01,
                volume: 700 + (seedValue * 173 + level * 739) % 4_600
            )
        }

        return StockMarketSeries(
            openPrice: intraday.first?.price ?? previousClose,
            previousClose: previousClose,
            intraday: intraday,
            candles: candles,
            buyLevels: buyLevels,
            sellLevels: sellLevels,
            trades: []
        )
    }

    private static func candleDateLabel(index: Int) -> String {
        let startDay = 2
        let absoluteDay = startDay + index
        let month = 7 + (absoluteDay - 1) / 31
        let day = (absoluteDay - 1) % 31 + 1
        return "\(month)/\(day)"
    }
}
