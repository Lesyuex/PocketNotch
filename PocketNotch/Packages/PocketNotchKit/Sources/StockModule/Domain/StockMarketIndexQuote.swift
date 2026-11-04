import Foundation

struct StockMarketIndexQuote: Identifiable, Equatable, Sendable {
    let code: String
    let name: String
    let value: Double
    let changeAmount: Double
    let changePercent: Double

    var id: String { code }
}
