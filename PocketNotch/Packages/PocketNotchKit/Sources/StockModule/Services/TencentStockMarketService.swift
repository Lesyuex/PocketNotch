import Foundation

protocol StockMarketDataProviding: Sendable {
    func fetchIntraday(for code: String) async throws -> StockIntradaySnapshot
}

enum StockMarketDataError: LocalizedError, Equatable {
    case invalidCode(String)
    case invalidResponse
    case providerFailure(Int)
    case missingData
    case emptySeries

    var errorDescription: String? {
        switch self {
        case let .invalidCode(code):
            return "不支持的股票代码：\(code)"
        case .invalidResponse:
            return "行情服务响应异常"
        case let .providerFailure(code):
            return "行情服务返回错误：\(code)"
        case .missingData:
            return "行情服务未返回数据"
        case .emptySeries:
            return "暂无分时数据"
        }
    }
}

final class TencentStockMarketService: StockMarketDataProviding, @unchecked Sendable {
    private struct AssignmentPayload: Decodable {
        let page: Int
        let content: String

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            page = try container.decode(Int.self)
            content = try container.decode(String.self)
        }
    }

    private struct Response: Decodable {
        let code: Int
        let data: [String: SecurityPayload]?
    }

    private struct SecurityPayload: Decodable {
        let data: MinutePayload
        let qt: [String: [String]]
    }

    private struct MinutePayload: Decodable {
        let data: [String]
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchIntraday(for code: String) async throws -> StockIntradaySnapshot {
        let symbol = try Self.marketSymbol(for: code)
        async let trades = fetchRecentTrades(for: symbol)
        var components = URLComponents(
            string: "https://web.ifzq.gtimg.cn/appstock/app/minute/query"
        )
        components?.queryItems = [URLQueryItem(name: "code", value: symbol)]
        guard let url = components?.url else {
            throw StockMarketDataError.invalidCode(code)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://gu.qq.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw StockMarketDataError.invalidResponse
        }
        let snapshot = try Self.decodeSnapshot(from: data, symbol: symbol)
        return StockIntradaySnapshot(
            code: snapshot.code,
            name: snapshot.name,
            decimalPlaces: snapshot.decimalPlaces,
            openPrice: snapshot.openPrice,
            previousClose: snapshot.previousClose,
            points: snapshot.points,
            buyLevels: snapshot.buyLevels,
            sellLevels: snapshot.sellLevels,
            trades: (try? await trades) ?? []
        )
    }

    static func marketSymbol(for code: String) throws -> String {
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            throw StockMarketDataError.invalidCode(code)
        }
        let market = code.hasPrefix("5") || code.hasPrefix("6") || code.hasPrefix("9")
            ? "sh"
            : "sz"
        return "\(market)\(code)"
    }

    static func decodeSnapshot(from data: Data, symbol: String) throws -> StockIntradaySnapshot {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.code == 0 else {
            throw StockMarketDataError.providerFailure(response.code)
        }
        guard let payload = response.data?[symbol],
              let quote = payload.qt[symbol],
              quote.count > 5,
              let previousClose = Double(quote[4]) else {
            throw StockMarketDataError.missingData
        }

        var points: [StockIntradayPoint] = []
        var previousCumulativeVolume = 0
        for row in payload.data.data {
            let fields = row.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 4,
                  let minute = tradingMinute(from: String(fields[0])),
                  let price = Double(fields[1]),
                  let cumulativeVolume = Int(fields[2]),
                  let cumulativeAmount = Double(fields[3]) else {
                continue
            }

            let minuteVolume = max(cumulativeVolume - previousCumulativeVolume, 0)
            previousCumulativeVolume = cumulativeVolume
            guard points.last?.minute != minute else { continue }
            points.append(
                StockIntradayPoint(
                    minute: minute,
                    price: price,
                    averagePrice: cumulativeVolume > 0
                        ? cumulativeAmount / (Double(cumulativeVolume) * 100)
                        : nil,
                    volume: minuteVolume
                )
            )
        }

        guard !points.isEmpty else {
            throw StockMarketDataError.emptySeries
        }
        let stockCode = quote[2].isEmpty ? String(symbol.dropFirst(2)) : quote[2]
        return StockIntradaySnapshot(
            code: stockCode,
            name: quote[1],
            decimalPlaces: decimalPlaces(in: quote[3]),
            openPrice: Double(quote[5]) ?? points.first?.price ?? previousClose,
            previousClose: previousClose,
            points: points,
            buyLevels: orderBookLevels(in: quote, priceIndices: [9, 11, 13, 15, 17]),
            sellLevels: orderBookLevels(in: quote, priceIndices: [19, 21, 23, 25, 27])
        )
    }

    static func decodeLatestTradePage(from data: Data) throws -> Int {
        let payload = try decodeAssignment(from: data)
        guard !payload.content.isEmpty else { return 0 }
        return max(payload.content.split(separator: "|").count - 1, 0)
    }

    static func decodeTrades(from data: Data) throws -> [StockTrade] {
        let payload = try decodeAssignment(from: data)
        return payload.content.split(separator: "|").compactMap { record in
            let fields = record.split(separator: "/", omittingEmptySubsequences: false)
            guard fields.count >= 7,
                  let id = Int(fields[0]),
                  let price = Double(fields[2]),
                  let priceChange = Double(fields[3]),
                  let volume = Int(fields[4]),
                  let amount = Double(fields[5]),
                  let side = StockTradeSide(rawValue: String(fields[6])) else {
                return nil
            }
            return StockTrade(
                id: id,
                time: String(fields[1]),
                price: price,
                priceChange: priceChange,
                volume: volume,
                amount: amount,
                side: side
            )
        }
    }

    private func fetchRecentTrades(for symbol: String) async throws -> [StockTrade] {
        let timelineURL = try detailURL(action: "timeline", symbol: symbol)
        let timelineData = try await fetchData(from: timelineURL)
        let latestPage = try Self.decodeLatestTradePage(from: timelineData)
        let detailURL = try detailURL(action: "data", symbol: symbol, page: latestPage)
        let detailData = try await fetchData(from: detailURL)
        return try Self.decodeTrades(from: detailData)
    }

    private func detailURL(action: String, symbol: String, page: Int? = nil) throws -> URL {
        var components = URLComponents(string: "https://stock.gtimg.cn/data/index.php")
        components?.queryItems = [
            URLQueryItem(name: "appn", value: "detail"),
            URLQueryItem(name: "action", value: action),
            URLQueryItem(name: "c", value: symbol)
        ]
        if let page {
            components?.queryItems?.append(URLQueryItem(name: "p", value: String(page)))
        }
        guard let url = components?.url else {
            throw StockMarketDataError.invalidResponse
        }
        return url
    }

    private func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://gu.qq.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw StockMarketDataError.invalidResponse
        }
        return data
    }

    private static func decodeAssignment(from data: Data) throws -> AssignmentPayload {
        guard let raw = String(data: data, encoding: .utf8),
              let start = raw.firstIndex(of: "["),
              let end = raw.lastIndex(of: "]"),
              start <= end else {
            throw StockMarketDataError.invalidResponse
        }
        return try JSONDecoder().decode(
            AssignmentPayload.self,
            from: Data(raw[start...end].utf8)
        )
    }

    private static func orderBookLevels(
        in quote: [String],
        priceIndices: [Int]
    ) -> [StockOrderBookLevel] {
        priceIndices.enumerated().compactMap { offset, priceIndex in
            let volumeIndex = priceIndex + 1
            guard quote.indices.contains(volumeIndex),
                  let price = Double(quote[priceIndex]),
                  price > 0,
                  let volume = numericVolume(quote[volumeIndex]),
                  volume >= 0 else {
                return nil
            }
            return StockOrderBookLevel(level: offset + 1, price: price, volume: volume)
        }
    }

    private static func numericVolume(_ value: String) -> Int? {
        Int(value) ?? Double(value).map(Int.init)
    }

    private static func tradingMinute(from value: String) -> Double? {
        guard value.count == 4,
              let hour = Int(value.prefix(2)),
              let minute = Int(value.suffix(2)) else {
            return nil
        }

        let minuteOfDay = hour * 60 + minute
        if (9 * 60 + 30)...(11 * 60 + 30) ~= minuteOfDay {
            return Double(minuteOfDay - (9 * 60 + 30))
        }
        if (13 * 60)...(15 * 60) ~= minuteOfDay {
            return Double(120 + minuteOfDay - 13 * 60)
        }
        return nil
    }

    private static func decimalPlaces(in value: String) -> Int {
        guard let separator = value.firstIndex(of: ".") else { return 0 }
        return value.distance(from: value.index(after: separator), to: value.endIndex)
    }
}
