import XCTest
@testable import BrightnessModule

@MainActor
final class BrightnessKeyInterceptorServiceTests: XCTestCase {
    func testStartPromptsAccessibilityOnceWhenUntrusted() {
        var promptCount = 0
        let service = BrightnessKeyInterceptorService(
            brightnessController: StubBrightnessProvider(),
            onPerformed: {},
            accessibilityTrustChecker: { false },
            accessibilityPrompt: { promptCount += 1 }
        )

        service.start()

        XCTAssertEqual(promptCount, 1)
        service.stop()
    }

    func testStartDoesNotPromptWhenTrusted() {
        var promptCount = 0
        let service = BrightnessKeyInterceptorService(
            brightnessController: StubBrightnessProvider(),
            onPerformed: {},
            accessibilityTrustChecker: { true },
            accessibilityPrompt: { promptCount += 1 }
        )

        service.start()

        XCTAssertEqual(promptCount, 0)
        service.stop()
    }
}

private final class StubBrightnessProvider: BrightnessProviding {
    func currentBrightness() -> Double? { nil }
    func perform(_ command: BrightnessCommand) -> Bool { false }
}
