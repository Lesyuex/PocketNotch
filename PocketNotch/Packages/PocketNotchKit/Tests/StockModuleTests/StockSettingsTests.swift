import XCTest
@testable import StockModule

final class StockPriorityTimeRangeTests: XCTestCase {
    func testContainsUsesEndExclusiveMinuteBoundary() {
        let range = StockPriorityTimeRange(startMinute: 9 * 60 + 30, endMinute: 11 * 60 + 30)

        XCTAssertFalse(range.contains(minuteOfDay: 9 * 60 + 29))
        XCTAssertTrue(range.contains(minuteOfDay: 9 * 60 + 30))
        XCTAssertTrue(range.contains(minuteOfDay: 11 * 60 + 29))
        XCTAssertFalse(range.contains(minuteOfDay: 11 * 60 + 30))
    }

    func testContainsSupportsRangesAcrossMidnight() {
        let range = StockPriorityTimeRange(startMinute: 23 * 60, endMinute: 60)

        XCTAssertTrue(range.contains(minuteOfDay: 23 * 60 + 30))
        XCTAssertTrue(range.contains(minuteOfDay: 30))
        XCTAssertFalse(range.contains(minuteOfDay: 12 * 60))
    }
}

@MainActor
final class StockSettingsTests: XCTestCase {
    func testPriorityDisplayRequiresRealtimeStockAndMatchingTimeRange() {
        let suiteName = "StockSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = StockSettings(defaults: defaults)
        settings.isPersistent = false
        let morningRange = settings.priorityTimeRanges[0]
        settings.updatePriorityTimeRange(
            id: morningRange.id,
            startMinute: 9 * 60 + 30,
            endMinute: 11 * 60 + 30
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let matchingDate = calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 23,
            hour: 10,
            minute: 15
        ))!

        XCTAssertFalse(settings.isPriorityDisplayActive(at: matchingDate, calendar: calendar))
        settings.isPersistent = true
        XCTAssertTrue(settings.isPriorityDisplayActive(at: matchingDate, calendar: calendar))

        settings.isPersistent = false
        XCTAssertFalse(settings.isPriorityDisplayActive(at: matchingDate, calendar: calendar))
    }

    func testPriorityTimeRangesPersistAfterDynamicChanges() {
        let suiteName = "StockSettingsPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = StockSettings(defaults: defaults)
        settings.addPriorityTimeRange()
        let addedRange = settings.priorityTimeRanges.last!
        settings.updatePriorityTimeRange(id: addedRange.id, startMinute: 8 * 60 + 5, endMinute: 9 * 60 + 45)

        let restored = StockSettings(defaults: defaults)
        XCTAssertEqual(restored.priorityTimeRanges.last?.startMinute, 8 * 60 + 5)
        XCTAssertEqual(restored.priorityTimeRanges.last?.endMinute, 9 * 60 + 45)
    }

    func testMoveStockBeforeTargetReordersList() {
        let suiteName = "StockSettingsMoveTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = StockSettings(defaults: defaults)
        let unchangedTail = Array(StockSettings.defaultOrder.dropFirst(3))
        XCTAssertEqual(settings.orderedIDs, StockSettings.defaultOrder)

        settings.move(id: "688256", before: "600519")
        XCTAssertEqual(Array(settings.orderedIDs.prefix(3)), ["688256", "600519", "002036"])
        XCTAssertEqual(Array(settings.orderedIDs.dropFirst(3)), unchangedTail)

        settings.move(id: "002036", before: "600519")
        XCTAssertEqual(Array(settings.orderedIDs.prefix(3)), ["688256", "002036", "600519"])
        XCTAssertEqual(Array(settings.orderedIDs.dropFirst(3)), unchangedTail)

        settings.move(id: "688256", before: "688256")
        XCTAssertEqual(Array(settings.orderedIDs.prefix(3)), ["688256", "002036", "600519"])
        XCTAssertEqual(Array(settings.orderedIDs.dropFirst(3)), unchangedTail)
    }

    func testPriorityDisplayExcludesWeekendsWhenEnabled() {
        let suiteName = "StockSettingsWeekendTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = StockSettings(defaults: defaults)
        settings.isPersistent = true
        settings.excludesWeekends = true

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let saturday = calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 25,
            hour: 10,
            minute: 15
        ))!
        let sunday = calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 26,
            hour: 10,
            minute: 15
        ))!
        let weekday = calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 23,
            hour: 10,
            minute: 15
        ))!

        XCTAssertFalse(settings.isPriorityDisplayActive(at: saturday, calendar: calendar))
        XCTAssertFalse(settings.isPriorityDisplayActive(at: sunday, calendar: calendar))
        XCTAssertTrue(settings.isPriorityDisplayActive(at: weekday, calendar: calendar))

        settings.excludesWeekends = false
        XCTAssertTrue(settings.isPriorityDisplayActive(at: saturday, calendar: calendar))
        XCTAssertTrue(settings.isPriorityDisplayActive(at: sunday, calendar: calendar))
    }
}
