@testable import ApplicationsModule
import XCTest

final class ApplicationSearchFilterTests: XCTestCase {
    private let apps = [
        ApplicationItem(url: URL(fileURLWithPath: "/Applications/Safari.app"), name: "Safari"),
        ApplicationItem(url: URL(fileURLWithPath: "/Applications/Xcode.app"), name: "Xcode"),
        ApplicationItem(url: URL(fileURLWithPath: "/Applications/WeChat.app"), name: "微信"),
    ]

    func testEmptyQueryReturnsAll() {
        XCTAssertEqual(ApplicationSearchFilter.filter(apps, query: ""), apps)
        XCTAssertEqual(ApplicationSearchFilter.filter(apps, query: "   "), apps)
    }

    func testFiltersByNameCaseInsensitively() {
        let result = ApplicationSearchFilter.filter(apps, query: "safa")
        XCTAssertEqual(result.map(\.name), ["Safari"])
    }

    func testMatchesChineseName() {
        let result = ApplicationSearchFilter.filter(apps, query: "微信")
        XCTAssertEqual(result.map(\.name), ["微信"])
    }

    func testTrimsWhitespace() {
        let result = ApplicationSearchFilter.filter(apps, query: " xcode ")
        XCTAssertEqual(result.map(\.name), ["Xcode"])
    }

    func testNoMatchReturnsEmpty() {
        XCTAssertTrue(ApplicationSearchFilter.filter(apps, query: "Finder").isEmpty)
    }
}