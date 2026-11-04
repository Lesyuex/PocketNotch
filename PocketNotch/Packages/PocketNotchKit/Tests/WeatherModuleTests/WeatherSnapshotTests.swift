import XCTest
@testable import WeatherModule

final class WeatherSnapshotTests: XCTestCase {
    func testClearDayPresentation() {
        let snapshot = WeatherSnapshot(
            temperature: 25.6,
            apparentTemperature: 27,
            weatherCode: 0,
            isDay: true
        )

        XCTAssertEqual(snapshot.roundedTemperatureText, "26°")
        XCTAssertEqual(snapshot.conditionText, "晴")
        XCTAssertEqual(snapshot.symbolName, "sun.max.fill")
    }

    func testClearNightUsesMoonSymbol() {
        let snapshot = WeatherSnapshot(
            temperature: 18,
            apparentTemperature: 17,
            weatherCode: 0,
            isDay: false
        )

        XCTAssertEqual(snapshot.symbolName, "moon.stars.fill")
    }

    func testRainCodePresentation() {
        let snapshot = WeatherSnapshot(
            temperature: 12.4,
            apparentTemperature: 10,
            weatherCode: 63,
            isDay: true
        )

        XCTAssertEqual(snapshot.roundedTemperatureText, "12°")
        XCTAssertEqual(snapshot.conditionText, "有雨")
        XCTAssertEqual(snapshot.symbolName, "cloud.rain.fill")
    }

    func testStrongGustDoesNotRewriteWeatherCondition() {
        let snapshot = WeatherSnapshot(
            temperature: 31,
            apparentTemperature: 37,
            weatherCode: 95,
            isDay: true,
            windSpeed: 18,
            windGust: 40
        )

        XCTAssertEqual(snapshot.conditionText, "雷雨")
        XCTAssertEqual(snapshot.symbolName, "cloud.bolt.rain.fill")
    }

    func testCompactMetricPresentation() {
        let snapshot = WeatherSnapshot(
            temperature: 25.6,
            apparentTemperature: 28.4,
            humidity: 73,
            weatherCode: 2,
            isDay: true,
            windSpeed: 12.6
        )

        XCTAssertEqual(WeatherCompactMetric.temperature.valueText(for: snapshot), "26°")
        XCTAssertEqual(WeatherCompactMetric.condition.valueText(for: snapshot), "多云")
        XCTAssertEqual(WeatherCompactMetric.apparentTemperature.valueText(for: snapshot), "28°")
        XCTAssertEqual(WeatherCompactMetric.humidity.valueText(for: snapshot), "73%")
        XCTAssertEqual(WeatherCompactMetric.windSpeed.valueText(for: snapshot), "13km/h")
        XCTAssertEqual(
            WeatherCompactMetric.condition.symbolName(for: snapshot),
            "cloud.sun.fill"
        )
    }

    func testForecastPresentationRoundsRangeAndUsesDaytimeSymbol() {
        let day = WeatherForecastDay(
            date: "2026-07-18",
            highTemperature: 30.6,
            lowTemperature: 24.4,
            weatherCode: 2,
            precipitationProbability: 65,
            maximumWindSpeed: 18.7,
            sunriseTime: "05:12",
            sunsetTime: "19:03"
        )

        XCTAssertEqual(day.temperatureRangeText, "31° / 24°")
        XCTAssertEqual(day.shortDateText, "7月18日")
        XCTAssertEqual(day.weekdayText, "星期六")
        XCTAssertEqual(day.highTemperatureText, "31°")
        XCTAssertEqual(day.lowTemperatureText, "24°")
        XCTAssertEqual(day.precipitationProbabilityText, "65%")
        XCTAssertEqual(day.maximumWindSpeedText, "19")
        XCTAssertEqual(day.sunriseTime, "05:12")
        XCTAssertEqual(day.sunsetTime, "19:03")
        XCTAssertEqual(day.conditionText, "多云")
        XCTAssertEqual(day.symbolName, "cloud.sun.fill")
    }
}
