import XCTest
@testable import PocketNotchCore

@MainActor
final class NotchDisplaySettingsTests: XCTestCase {
    func testDefaultsToAllDisplays() {
        let settings = NotchDisplaySettings(defaults: nil)

        XCTAssertEqual(settings.mode, .all)
        XCTAssertNil(settings.selectedDisplayIdentifier)
    }

    func testSelectionPersists() {
        let suiteName = "NotchDisplaySettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = NotchDisplaySettings(defaults: defaults)
        settings.showOnDisplay(identifier: "display-a")

        let restoredSingle = NotchDisplaySettings(defaults: defaults)
        XCTAssertEqual(restoredSingle.mode, .single)
        XCTAssertEqual(restoredSingle.selectedDisplayIdentifier, "display-a")

        restoredSingle.showOnAllDisplays()
        let restoredAll = NotchDisplaySettings(defaults: defaults)
        XCTAssertEqual(restoredAll.mode, .all)
        XCTAssertEqual(restoredAll.selectedDisplayIdentifier, "display-a")
    }

    func testResetRestoresAllDisplays() {
        let settings = NotchDisplaySettings(defaults: nil)
        settings.showOnDisplay(identifier: "display-a")
        settings.showOnAllDisplays()

        settings.resetToDefault()

        XCTAssertEqual(settings.mode, .all)
        XCTAssertNil(settings.selectedDisplayIdentifier)
    }
}
