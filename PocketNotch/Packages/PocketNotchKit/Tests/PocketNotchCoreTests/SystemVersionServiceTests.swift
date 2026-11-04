import XCTest
@testable import PocketNotchCore

final class SystemVersionServiceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let realVersion = SystemVersionInfo(major: 26, minor: 1, patch: 4)

    override func setUp() {
        super.setUp()
        suiteName = "SystemVersionServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func makeService() -> SystemVersionService {
        SystemVersionService(version: realVersion, defaults: defaults)
    }

    func testDefaultFollowsRealVersion() {
        let service = makeService()
        XCTAssertEqual(service.currentVersion(), realVersion)
        XCTAssertEqual(service.isMacOS26OrLater, true)
        XCTAssertNil(service.overriddenVersion)
    }

    func testOverrideRoutesVersionJudgments() {
        let service = makeService()
        service.overriddenVersion = SystemVersionInfo(major: 15, minor: 0, patch: 0)

        XCTAssertEqual(service.currentVersion(), SystemVersionInfo(major: 15, minor: 0, patch: 0))
        XCTAssertEqual(service.isMacOS26OrLater, false)
        XCTAssertEqual(service.realVersion, realVersion)
    }

    func testClearingOverrideRestoresRealVersion() {
        let service = makeService()
        service.overriddenVersion = SystemVersionInfo(major: 14, minor: 0, patch: 0)
        service.overriddenVersion = nil

        XCTAssertNil(service.overriddenVersion)
        XCTAssertEqual(service.currentVersion(), realVersion)
        XCTAssertEqual(service.isMacOS26OrLater, true)
    }

    func testOverridePersistsAcrossInstances() {
        let service = makeService()
        service.overriddenVersion = SystemVersionInfo(major: 26, minor: 0, patch: 0)

        let reloaded = makeService()
        XCTAssertEqual(reloaded.currentVersion(), SystemVersionInfo(major: 26, minor: 0, patch: 0))
        XCTAssertEqual(reloaded.isMacOS26OrLater, true)
    }

    func testMalformedStoredOverrideFallsBackToRealVersion() {
        defaults.set("not.a.version", forKey: "pocketnotch.macOSVersionOverride")
        let service = makeService()
        XCTAssertNil(service.overriddenVersion)
        XCTAssertEqual(service.currentVersion(), realVersion)
    }

    func testOldSystemFollowsVersionJudgment() {
        let service = SystemVersionService(version: SystemVersionInfo(major: 14, minor: 4, patch: 0), defaults: defaults)
        XCTAssertEqual(service.isMacOS26OrLater, false)
    }
}