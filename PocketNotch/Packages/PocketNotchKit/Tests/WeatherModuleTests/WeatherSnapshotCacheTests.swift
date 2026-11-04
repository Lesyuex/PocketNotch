import Foundation
import XCTest
@testable import WeatherModule

final class WeatherSnapshotCacheTests: XCTestCase {
    func testLoadsFreshSnapshotAndRejectsExpiredSnapshot() throws {
        let suiteName = "WeatherSnapshotCacheTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let updatedAt = Date(timeIntervalSince1970: 1_000)
        let snapshot = WeatherSnapshot(
            temperature: 28,
            apparentTemperature: 32,
            humidity: 75,
            weatherCode: 2,
            isDay: true,
            forecast: [
                WeatherForecastDay(
                    date: "2026-07-21",
                    highTemperature: 30,
                    lowTemperature: 27,
                    weatherCode: 2,
                    precipitationProbability: 40,
                    maximumWindSpeed: 12,
                    sunriseTime: "05:30",
                    sunsetTime: "19:10"
                )
            ],
            updatedAt: updatedAt
        )
        let cache = WeatherSnapshotCache(defaults: defaults, maximumAge: 3_600)

        cache.save(snapshot)

        XCTAssertEqual(cache.load(now: updatedAt.addingTimeInterval(3_599)), snapshot)
        XCTAssertNil(cache.load(now: updatedAt.addingTimeInterval(3_601)))
    }
}
