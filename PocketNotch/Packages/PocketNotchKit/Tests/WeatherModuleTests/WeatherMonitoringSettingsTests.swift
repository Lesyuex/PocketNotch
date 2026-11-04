import Foundation
import XCTest
@testable import WeatherModule

final class WeatherMonitoringSettingsTests: XCTestCase {
    @MainActor
    func testDefaultsToTemperatureAndCondition() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = WeatherMonitoringSettings(defaults: defaults)

        XCTAssertEqual(settings.compactMetrics, [.temperature, .condition])
        XCTAssertTrue(settings.isAutomaticLocationEnabled)
    }

    @MainActor
    func testMetricSelectionPersistsInSelectedOrder() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = WeatherMonitoringSettings(defaults: defaults)
        settings.setMetric(.humidity, isEnabled: true)
        settings.setMetric(.temperature, isEnabled: false)

        let reloaded = WeatherMonitoringSettings(defaults: defaults)
        XCTAssertEqual(reloaded.compactMetrics, [.condition, .humidity])
    }

    @MainActor
    func testCannotDisableLastMetric() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = WeatherMonitoringSettings(defaults: defaults)
        settings.setMetric(.condition, isEnabled: false)
        settings.setMetric(.temperature, isEnabled: false)

        XCTAssertEqual(settings.compactMetrics, [.temperature])
    }

    @MainActor
    func testMetricOrderPersists() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = WeatherMonitoringSettings(defaults: defaults)
        settings.setMetric(.humidity, isEnabled: true)
        // 全量顺序里把 humidity 前移两位。
        settings.moveMetric(.humidity, by: -1)
        settings.moveMetric(.humidity, by: -1)

        let reloaded = WeatherMonitoringSettings(defaults: defaults)
        XCTAssertEqual(reloaded.compactMetrics, [.temperature, .humidity, .condition])
    }

    @MainActor
    func testCannotMoveMetricOutsideBounds() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = WeatherMonitoringSettings(defaults: defaults)
        // 已在首位，不能再上移。
        settings.moveMetric(.temperature, by: -1)
        XCTAssertEqual(settings.compactMetrics, [.temperature, .condition])
        // 已在末位（禁用项在末尾），不能再下移。
        settings.moveMetric(.windSpeed, by: 1)
        XCTAssertEqual(
            settings.metricOrder,
            [.temperature, .condition, .apparentTemperature, .humidity, .windSpeed]
        )
    }

    @MainActor
    func testDisabledMetricCanBeReorderedInFullOrder() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = WeatherMonitoringSettings(defaults: defaults)
        XCTAssertEqual(
            settings.metricOrder,
            [.temperature, .condition, .apparentTemperature, .humidity, .windSpeed]
        )
        // 未启用的 windSpeed 移到首位。
        settings.moveMetric(.windSpeed, before: .temperature)
        XCTAssertEqual(settings.metricOrder[0], .windSpeed)
        // 启用子集顺序不受未启用项影响。
        XCTAssertEqual(settings.compactMetrics, [.temperature, .condition])
    }

    @MainActor
    func testOrderChangeKeepsEnabledSubsetInSync() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = WeatherMonitoringSettings(defaults: defaults)
        settings.setMetric(.humidity, isEnabled: true)
        XCTAssertEqual(settings.compactMetrics, [.temperature, .condition, .humidity])

        // 在 condition 前插入 humidity，启用子集顺序随之更新。
        settings.moveMetric(.humidity, before: .condition)
        XCTAssertEqual(settings.compactMetrics, [.temperature, .humidity, .condition])
    }

    @MainActor
    func testAutomaticLocationIsAlwaysEnabledAndSavedCoordinatePersists() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = WeatherMonitoringSettings(defaults: defaults)
        settings.isAutomaticLocationEnabled = false
        settings.saveCoordinate(latitude: 22.5431, longitude: 114.0579)

        let reloaded = WeatherMonitoringSettings(defaults: defaults)
        XCTAssertTrue(reloaded.isAutomaticLocationEnabled)
        XCTAssertEqual(
            reloaded.savedCoordinate,
            WeatherSavedCoordinate(latitude: 22.5431, longitude: 114.0579)
        )
    }

    @MainActor
    func testMoveMetricBefore() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = WeatherMonitoringSettings(defaults: defaults)
        settings.setMetric(.humidity, isEnabled: true)
        XCTAssertEqual(settings.compactMetrics, [.temperature, .condition, .humidity])

        // 把 humidity 移到 condition 正前方。
        settings.moveMetric(.humidity, before: .condition)
        XCTAssertEqual(settings.compactMetrics, [.temperature, .humidity, .condition])

        // 目标与自身相同：不移动。
        settings.moveMetric(.temperature, before: .temperature)
        XCTAssertEqual(settings.compactMetrics, [.temperature, .humidity, .condition])

        // 把已在自己前方的 temperature 移到 condition 正前方。
        settings.moveMetric(.temperature, before: .condition)
        XCTAssertEqual(settings.compactMetrics, [.humidity, .temperature, .condition])
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "WeatherMonitoringSettingsTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }
}
