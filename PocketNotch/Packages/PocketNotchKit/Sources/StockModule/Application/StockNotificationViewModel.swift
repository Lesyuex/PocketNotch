import Foundation
import Combine

@MainActor
final class StockNotificationViewModel: ObservableObject {
    private let settings: StockSettings
    private let marketDataProvider: any StockMarketDataProviding
    /// 临时样例数据；正式接入自选后由服务层更新此数组。
    private static let allQuotes: [StockQuote] = [
        StockQuote(id: "600519", name: "贵州茅台", code: "600519", price: "1,478.00", change: "+1.26%", isPositive: true, changeAmount: "+18.50", volume: "12.3k"),
        StockQuote(id: "002036", name: "联创电子", code: "002036", price: "7.37", change: "-5.38%", isPositive: false, changeAmount: "-0.42", volume: "85.6k"),
        StockQuote(id: "688256", name: "寒武纪-U", code: "688256", price: "612.80", change: "+3.18%", isPositive: true, changeAmount: "+18.90", volume: "5.2k"),
        StockQuote(id: "000001", name: "平安银行", code: "000001", price: "11.86", change: "+0.42%", isPositive: true, changeAmount: "+0.05", volume: "428.6k"),
        StockQuote(id: "000333", name: "美的集团", code: "000333", price: "75.42", change: "-0.67%", isPositive: false, changeAmount: "-0.51", volume: "96.8k"),
        StockQuote(id: "000858", name: "五粮液", code: "000858", price: "132.68", change: "+1.14%", isPositive: true, changeAmount: "+1.50", volume: "154.2k"),
        StockQuote(id: "300750", name: "宁德时代", code: "300750", price: "286.40", change: "+2.08%", isPositive: true, changeAmount: "+5.84", volume: "211.7k"),
        StockQuote(id: "300059", name: "东方财富", code: "300059", price: "24.73", change: "-1.12%", isPositive: false, changeAmount: "-0.28", volume: "1.3m"),
        StockQuote(id: "600036", name: "招商银行", code: "600036", price: "46.72", change: "+0.84%", isPositive: true, changeAmount: "+0.39", volume: "307.5k"),
        StockQuote(id: "601318", name: "中国平安", code: "601318", price: "59.16", change: "-0.54%", isPositive: false, changeAmount: "-0.32", volume: "265.9k"),
        StockQuote(id: "600900", name: "长江电力", code: "600900", price: "28.64", change: "+0.28%", isPositive: true, changeAmount: "+0.08", volume: "183.4k"),
        StockQuote(id: "601899", name: "紫金矿业", code: "601899", price: "25.31", change: "+1.69%", isPositive: true, changeAmount: "+0.42", volume: "742.1k"),
        StockQuote(id: "688981", name: "中芯国际", code: "688981", price: "105.20", change: "-0.94%", isPositive: false, changeAmount: "-1.00", volume: "198.6k")
    ]

    @Published private var liveQuotesByID: [String: StockQuote] = [:]
    @Published private var seriesByQuoteID: [String: StockMarketSeries]
    @Published private(set) var loadingQuoteIDs: Set<String> = []
    @Published private(set) var liveQuoteIDs: Set<String> = []
    @Published private(set) var marketDataErrors: [String: String] = [:]

    @Published private(set) var selectedIndex = 0
    private var rotationTask: Task<Void, Never>?
    private var settingsCancellable: AnyCancellable?
    private var isActive = false

    init(
        settings: StockSettings,
        marketDataProvider: any StockMarketDataProviding = TencentStockMarketService()
    ) {
        self.settings = settings
        self.marketDataProvider = marketDataProvider
        seriesByQuoteID = Dictionary(
            uniqueKeysWithValues: Self.allQuotes.map { quote in
                (quote.id, StockMarketSeries.sample(for: quote))
            }
        )
        settingsCancellable = settings.$isPersistent
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.syncRotation()
            }
    }

    var quotes: [StockQuote] {
        let orderedQuotes = settings.orderedIDs.compactMap { id in
            liveQuotesByID[id] ?? Self.allQuotes.first { $0.id == id }
        }
        let remainingQuotes = Self.allQuotes
            .filter { !settings.orderedIDs.contains($0.id) }
            .map { liveQuotesByID[$0.id] ?? $0 }
        return orderedQuotes + remainingQuotes
    }

    var selectedQuote: StockQuote { quotes[min(selectedIndex, max(quotes.count - 1, 0))] }

    func marketSeries(for quote: StockQuote) -> StockMarketSeries {
        seriesByQuoteID[quote.id] ?? .sample(for: quote)
    }

    func isMarketDataLoading(for quoteID: String) -> Bool {
        loadingQuoteIDs.contains(quoteID)
    }

    func isMarketDataLive(for quoteID: String) -> Bool {
        liveQuoteIDs.contains(quoteID)
    }

    func marketDataError(for quoteID: String) -> String? {
        marketDataErrors[quoteID]
    }

    func observeMarketData(for quoteID: String) async {
        while !Task.isCancelled {
            await refreshMarketData(for: quoteID)
            guard !Task.isCancelled else { return }
            do {
                try await Task.sleep(for: .seconds(Self.refreshInterval()))
            } catch {
                return
            }
        }
    }

    func refreshMarketData(for quoteID: String) async {
        guard let fallbackQuote = Self.allQuotes.first(where: { $0.id == quoteID }) else { return }
        loadingQuoteIDs.insert(quoteID)
        defer { loadingQuoteIDs.remove(quoteID) }

        do {
            let snapshot = try await marketDataProvider.fetchIntraday(for: fallbackQuote.code)
            guard !Task.isCancelled else { return }
            let liveQuote = Self.quote(from: snapshot, fallback: fallbackQuote)
            let fallbackSeries = StockMarketSeries.sample(for: liveQuote)
            liveQuotesByID[quoteID] = liveQuote
            seriesByQuoteID[quoteID] = StockMarketSeries(
                openPrice: snapshot.openPrice,
                previousClose: snapshot.previousClose,
                intraday: snapshot.points,
                candles: fallbackSeries.candles,
                buyLevels: snapshot.buyLevels,
                sellLevels: snapshot.sellLevels,
                trades: snapshot.trades
            )
            liveQuoteIDs.insert(quoteID)
            marketDataErrors.removeValue(forKey: quoteID)
        } catch {
            guard !Task.isCancelled else { return }
            liveQuoteIDs.remove(quoteID)
            marketDataErrors[quoteID] = error.localizedDescription
        }
    }

    func start() {
        isActive = true
        syncRotation()
    }

    func stop() {
        isActive = false
        syncRotation()
    }

    private func syncRotation() {
        if isActive, settings.isPersistent {
            startRotation()
        } else {
            stopRotation()
        }
    }

    private func startRotation() {
        guard rotationTask == nil else { return }
        rotationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                let count = self?.quotes.count ?? 0
                guard count > 0 else { return }
                self?.selectedIndex = ((self?.selectedIndex ?? 0) + 1) % count
            }
        }
    }

    private func stopRotation() {
        rotationTask?.cancel()
        rotationTask = nil
    }

    private static func quote(
        from snapshot: StockIntradaySnapshot,
        fallback: StockQuote
    ) -> StockQuote {
        guard let latestPrice = snapshot.latestPrice, snapshot.previousClose > 0 else {
            return fallback
        }
        let changePercent = (latestPrice / snapshot.previousClose - 1) * 100
        let changeAmount = latestPrice - snapshot.previousClose
        let sign = changePercent > 0 ? "+" : ""
        let amountSign = changeAmount > 0 ? "+" : ""
        let totalVolume = snapshot.points.reduce(0) { $0 + $1.volume }
        let volumeText: String
        if totalVolume >= 100_000 {
            volumeText = String(format: "%.1fk", Double(totalVolume) / 1_000)
        } else if totalVolume >= 1_000 {
            volumeText = String(format: "%.1fk", Double(totalVolume) / 1_000)
        } else {
            volumeText = "\(totalVolume)"
        }
        return StockQuote(
            id: fallback.id,
            name: snapshot.name.isEmpty ? fallback.name : snapshot.name,
            code: snapshot.code.isEmpty ? fallback.code : snapshot.code,
            price: String(format: "%.*f", snapshot.decimalPlaces, latestPrice),
            change: String(format: "%@%.2f%%", sign, changePercent),
            isPositive: changePercent >= 0,
            changeAmount: String(format: "%@%.*f", amountSign, snapshot.decimalPlaces, abs(changeAmount)),
            volume: volumeText
        )
    }

    private static func refreshInterval(now: Date = Date()) -> TimeInterval {
        isTradingTime(now: now) ? 3 : 300
    }

    static func isTradingTime(now: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        guard let weekday = components.weekday,
              let hour = components.hour,
              let minute = components.minute,
              (2...6).contains(weekday) else {
            return false
        }
        let minuteOfDay = hour * 60 + minute
        return (9 * 60 + 30)...(11 * 60 + 30) ~= minuteOfDay
            || (13 * 60)...(15 * 60) ~= minuteOfDay
    }
}
