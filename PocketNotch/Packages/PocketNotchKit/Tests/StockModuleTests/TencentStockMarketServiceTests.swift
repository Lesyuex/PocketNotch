@testable import StockModule
import Foundation
import XCTest

final class TencentStockMarketServiceTests: XCTestCase {
    func testMarketSymbolMapsShanghaiAndShenzhenCodes() throws {
        XCTAssertEqual(try TencentStockMarketService.marketSymbol(for: "600519"), "sh600519")
        XCTAssertEqual(try TencentStockMarketService.marketSymbol(for: "688256"), "sh688256")
        XCTAssertEqual(try TencentStockMarketService.marketSymbol(for: "002036"), "sz002036")
    }

    func testDecodeSnapshotParsesMinutesAndCalculatesAveragePrice() throws {
        let json = """
        {
          "code": 0,
          "msg": "",
          "data": {
            "sh600519": {
              "data": {
                "data": [
                  "0930 100.00 10 100000.00",
                  "1130 102.00 30 304000.00",
                  "1300 102.00 30 304000.00",
                  "1301 103.00 40 407000.00",
                  "1500 104.00 50 511000.00"
                ],
                "date": "20260731"
              },
              "qt": {
                "v_ff_sh600519": [],
                "sh600519": [
                  "1", "贵州茅台", "600519", "104.00", "99.50", "100.00",
                  "50", "25", "25",
                  "103.90", "11", "103.80", "22", "103.70", "33",
                  "103.60", "44", "103.50", "55",
                  "104.10", "12", "104.20", "23", "104.30", "34",
                  "104.40", "45", "104.50", "56"
                ],
                "market": []
              }
            }
          }
        }
        """

        let snapshot = try TencentStockMarketService.decodeSnapshot(
            from: Data(json.utf8),
            symbol: "sh600519"
        )

        XCTAssertEqual(snapshot.code, "600519")
        XCTAssertEqual(snapshot.name, "贵州茅台")
        XCTAssertEqual(snapshot.openPrice, 100.00, accuracy: 0.001)
        XCTAssertEqual(snapshot.previousClose, 99.50, accuracy: 0.001)
        XCTAssertEqual(snapshot.points.map(\.minute), [0, 120, 121, 240])
        XCTAssertEqual(snapshot.points.map(\.volume), [10, 20, 10, 10])
        XCTAssertEqual(snapshot.points.first?.averagePrice, 100.00)
        XCTAssertEqual(snapshot.points[2].averagePrice ?? 0, 101.75, accuracy: 0.001)
        XCTAssertEqual(snapshot.latestPrice, 104.00)
        XCTAssertEqual(snapshot.buyLevels.map(\.level), [1, 2, 3, 4, 5])
        XCTAssertEqual(snapshot.buyLevels.map(\.price), [103.90, 103.80, 103.70, 103.60, 103.50])
        XCTAssertEqual(snapshot.buyLevels.map(\.volume), [11, 22, 33, 44, 55])
        XCTAssertEqual(snapshot.sellLevels.map(\.level), [1, 2, 3, 4, 5])
        XCTAssertEqual(snapshot.sellLevels.map(\.price), [104.10, 104.20, 104.30, 104.40, 104.50])
        XCTAssertEqual(snapshot.sellLevels.map(\.volume), [12, 23, 34, 45, 56])
    }

    func testDecodeSnapshotRejectsProviderFailure() {
        let json = #"{"code":102,"msg":"failed","data":{}}"#

        XCTAssertThrowsError(
            try TencentStockMarketService.decodeSnapshot(
                from: Data(json.utf8),
                symbol: "sh600519"
            )
        ) { error in
            XCTAssertEqual(error as? StockMarketDataError, .providerFailure(102))
        }
    }

    func testDecodeLatestTradePageUsesLastTimelineRange() throws {
        let payload = #"v_detail_time_sh600519=[20260731,"09:25:02~09:33:26|09:33:29~09:36:56|09:36:59~09:40:26"]"#

        XCTAssertEqual(
            try TencentStockMarketService.decodeLatestTradePage(from: Data(payload.utf8)),
            2
        )
    }

    func testDecodeTradesParsesDirectionAndFields() throws {
        let payload = #"v_detail_data_sh600519=[54,"3780/14:30:38/1349.86/0.80/2/269907/M|3781/14:30:41/1349.10/-0.76/5/674550/S|3782/14:30:44/1349.90/0.80/3/404970/B"]"#

        let trades = try TencentStockMarketService.decodeTrades(from: Data(payload.utf8))

        XCTAssertEqual(trades.count, 3)
        XCTAssertEqual(trades.map(\.id), [3780, 3781, 3782])
        XCTAssertEqual(trades.map(\.side), [.neutral, .sell, .buy])
        XCTAssertEqual(trades[1].time, "14:30:41")
        XCTAssertEqual(trades[1].price, 1349.10)
        XCTAssertEqual(trades[1].priceChange, -0.76)
        XCTAssertEqual(trades[1].volume, 5)
        XCTAssertEqual(trades[1].amount, 674550)
    }
}
