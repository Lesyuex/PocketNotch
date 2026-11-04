import XCTest
@testable import AgentEventModule

@MainActor
final class AgentActivitySettingsTests: XCTestCase {
    func testPetBindingsPersistAndClear() throws {
        let suiteName = "AgentActivitySettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AgentActivitySettings(defaults: defaults)
        settings.setPetBinding("pocketnotchLibrary:test", for: "claude")

        let reloaded = AgentActivitySettings(defaults: defaults)
        XCTAssertEqual(reloaded.petBindings["claude"], "pocketnotchLibrary:test")

        reloaded.setPetBinding(nil, for: "claude")
        XCTAssertNil(reloaded.petBindings["claude"])
    }
}
