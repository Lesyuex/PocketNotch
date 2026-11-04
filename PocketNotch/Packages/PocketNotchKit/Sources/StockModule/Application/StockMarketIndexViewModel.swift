import Foundation
import Combine

@MainActor
final class StockMarketIndexViewModel: ObservableObject {
    @Published private(set) var quotes: [StockMarketIndexQuote] = []

    private let provider: any StockMarketIndexProviding
    private var isRefreshing = false

    init(provider: any StockMarketIndexProviding = StockMarketIndexService()) {
        self.provider = provider
    }

    func quote(for code: String) -> StockMarketIndexQuote? {
        quotes.first { $0.code == code }
    }

    func observe() async {
        while !Task.isCancelled {
            await refresh()
            guard !Task.isCancelled else { return }
            do {
                try await Task.sleep(for: .seconds(Self.refreshInterval()))
            } catch {
                return
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let incomingQuotes = try await provider.fetchIndices()
            guard !Task.isCancelled else { return }
            var merged = Dictionary(uniqueKeysWithValues: quotes.map { ($0.code, $0) })
            for quote in incomingQuotes {
                merged[quote.code] = quote
            }
            quotes = Self.indexOrder.compactMap { merged[$0] }
        } catch {
            // 指数是页头辅助信息；请求失败时保留最近一次成功结果，不影响股票列表。
        }
    }

    private static let indexOrder = ["000001", "399006"]

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
