import XCTest
@testable import MediaModule

@MainActor
final class SystemVolumeKeyInterceptorServiceTests: XCTestCase {
    func testStartPromptsAccessibilityOnceWhenUntrusted() {
        var trustCheckCount = 0
        var promptCount = 0
        let service = SystemVolumeKeyInterceptorService(
            volumeController: StubAudioOutputVolumeProvider(),
            accessibilityTrustChecker: {
                trustCheckCount += 1
                return false
            },
            accessibilityPrompt: { promptCount += 1 }
        )

        service.start()

        XCTAssertEqual(trustCheckCount, 1)
        XCTAssertEqual(promptCount, 1)
        service.stop()
    }
}

private final class StubAudioOutputVolumeProvider: AudioOutputVolumeProviding {
    func startObserving(
        onVolumeChange: @Sendable @escaping (AudioOutputVolumeSnapshot) -> Void,
        onOutputDeviceChange: @Sendable @escaping (AudioOutputDeviceSnapshot) -> Void
    ) {}

    func stopObserving() {}

    func perform(_ command: AudioOutputVolumeCommand) -> Bool { false }
}
