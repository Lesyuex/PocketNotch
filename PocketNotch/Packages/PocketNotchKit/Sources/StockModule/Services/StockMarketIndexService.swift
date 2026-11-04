import Foundation

protocol StockMarketIndexProviding: Sendable {
    func fetchIndices() async throws -> [StockMarketIndexQuote]
}

enum StockMarketIndexError: LocalizedError, Equatable {
    case invalidResponse
    case providerFailure(Int)
    case missingData

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "指数行情服务响应异常"
        case let .providerFailure(code):
            return "指数行情服务返回错误：\(code)"
        case .missingData:
            return "指数行情服务未返回数据"
        }
    }
}

final class StockMarketIndexService: StockMarketIndexProviding, @unchecked Sendable {
    private struct Response: Decodable {
        let rc: Int
        let data: Payload?
    }

    private struct Payload: Decodable {
        let diff: [QuotePayload]
    }

    private struct QuotePayload: Decodable {
        let code: String
        let name: String
        let value: Double?
        let changePercent: Double?
        let changeAmount: Double?

        private enum CodingKeys: String, CodingKey {
            case code = "f12"
            case name = "f14"
            case value = "f2"
            case changePercent = "f3"
            case changeAmount = "f4"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = (try? container.decode(String.self, forKey: .code)) ?? ""
            name = (try? container.decode(String.self, forKey: .name)) ?? ""
            value = Self.decodeNumber(for: .value, from: container)
            changePercent = Self.decodeNumber(for: .changePercent, from: container)
            changeAmount = Self.decodeNumber(for: .changeAmount, from: container)
        }

        private static func decodeNumber(
            for key: CodingKeys,
            from container: KeyedDecodingContainer<CodingKeys>
        ) -> Double? {
            if let number = try? container.decode(Double.self, forKey: key) {
                return number
            }
            guard let text = try? container.decode(String.self, forKey: key) else {
                return nil
            }
            return Double(text)
        }
    }

    private static let indexOrder = ["000001", "399006"]
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchIndices() async throws -> [StockMarketIndexQuote] {
        var components = URLComponents(
            string: "https://push2.eastmoney.com/api/qt/ulist.np/get"
        )
        components?.queryItems = [
            URLQueryItem(name: "fltt", value: "2"),
            URLQueryItem(name: "fields", value: "f12,f14,f2,f3,f4"),
            URLQueryItem(name: "secids", value: "1.000001,0.399006"),
        ]
        guard let url = components?.url else {
            throw StockMarketIndexError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw StockMarketIndexError.invalidResponse
        }
        return try Self.decodeQuotes(from: data)
    }

    static func decodeQuotes(from data: Data) throws -> [StockMarketIndexQuote] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.rc == 0 else {
            throw StockMarketIndexError.providerFailure(response.rc)
        }
        guard let payload = response.data else {
            throw StockMarketIndexError.missingData
        }

        let quotes = payload.diff.compactMap { payload -> StockMarketIndexQuote? in
            guard Self.indexOrder.contains(payload.code),
                  let value = payload.value,
                  let changeAmount = payload.changeAmount,
                  let changePercent = payload.changePercent else {
                return nil
            }
            return StockMarketIndexQuote(
                code: payload.code,
                name: payload.name,
                value: value,
                changeAmount: changeAmount,
                changePercent: changePercent
            )
        }
        guard !quotes.isEmpty else {
            throw StockMarketIndexError.missingData
        }
        return quotes.sorted {
            let lhs = Self.indexOrder.firstIndex(of: $0.code) ?? .max
            let rhs = Self.indexOrder.firstIndex(of: $1.code) ?? .max
            return lhs < rhs
        }
    }
}
