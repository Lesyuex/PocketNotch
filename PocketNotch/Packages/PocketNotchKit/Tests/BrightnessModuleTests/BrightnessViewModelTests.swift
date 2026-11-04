import XCTest
import PocketNotchCore
@testable import BrightnessModule

@MainActor
final class BrightnessViewModelTests: XCTestCase {
    func testSnapshotClampsToUnitRange() {
        XCTAssertEqual(BrightnessSnapshot(brightness: -0.2).brightness, 0)
        XCTAssertEqual(BrightnessSnapshot(brightness: 1.4).brightness, 1)
        XCTAssertEqual(BrightnessSnapshot(brightness: 0.5).brightness, 0.5)
    }

    func testSnapshotDisplayedPercentage() {
        XCTAssertEqual(BrightnessSnapshot(brightness: 0).displayedPercentage, 0)
        XCTAssertEqual(BrightnessSnapshot(brightness: 0.5).displayedPercentage, 50)
        XCTAssertEqual(BrightnessSnapshot(brightness: 1).displayedPercentage, 100)
    }

    func testBrightnessStepStandardAndFineDeltas() {
        XCTAssertEqual(BrightnessStep.delta(fineAdjustment: false), 1.0 / 16.0, accuracy: 1e-9)
        XCTAssertEqual(BrightnessStep.delta(fineAdjustment: true), 1.0 / 64.0, accuracy: 1e-9)
    }

    func testBrightnessStepTargetClampsAtBounds() {
        let raised = BrightnessStep.target(from: 0.99, command: .increase(fineAdjustment: false))
        XCTAssertEqual(raised, 1)
        let lowered = BrightnessStep.target(from: 0.01, command: .decrease(fineAdjustment: false))
        XCTAssertEqual(lowered, 0)
    }

    func testBrightnessStepTargetDirection() {
        let increased = BrightnessStep.target(from: 0.5, command: .increase(fineAdjustment: false))
        XCTAssertEqual(increased, 0.5 + 1.0 / 16.0, accuracy: 1e-9)

        let decreased = BrightnessStep.target(from: 0.5, command: .decrease(fineAdjustment: false))
        XCTAssertEqual(decreased, 0.5 - 1.0 / 16.0, accuracy: 1e-9)

        let fineIncreased = BrightnessStep.target(from: 0.5, command: .increase(fineAdjustment: true))
        XCTAssertEqual(fineIncreased, 0.5 + 1.0 / 64.0, accuracy: 1e-9)
    }

    func testServicePerformAdjustsStoredBrightnessAndReturnsTrue() {
        let service = StubBrightnessProvider(brightness: 0.5)
        let didPerform = service.perform(.increase(fineAdjustment: false))
        XCTAssertTrue(didPerform)
        XCTAssertEqual(service.brightness ?? 0, 0.5 + 1.0 / 16.0, accuracy: 1e-9)
    }

    func testServicePerformFailsWithoutCurrentBrightness() {
        let service = StubBrightnessProvider(brightness: nil)
        let didPerform = service.perform(.increase(fineAdjustment: false))
        XCTAssertFalse(didPerform)
    }

    func testAdjustmentPresentsBrightnessOnIsland() {
        let service = StubBrightnessProvider(brightness: 0.55)
        let viewModel = makeViewModel(service: service)
        XCTAssertNil(viewModel.brightnessPresentation)

        viewModel.handleBrightnessAdjustment()

        XCTAssertEqual(viewModel.brightnessPresentation?.displayedPercentage, 55)
        guard case .brightness = viewModel.compactPresentationIdentity else {
            return XCTFail("Expected a brightness presentation identity")
        }
    }

    func testAdjustmentWithNoBrightnessDoesNotPresent() {
        let service = StubBrightnessProvider(brightness: nil)
        let viewModel = makeViewModel(service: service)

        viewModel.handleBrightnessAdjustment()

        XCTAssertNil(viewModel.brightnessPresentation)
        XCTAssertEqual(viewModel.compactPresentationIdentity, .none)
    }

    func testConsecutiveAdjustmentsRefreshPresentation() {
        let service = StubBrightnessProvider(brightness: 0.5)
        let viewModel = makeViewModel(service: service)

        viewModel.handleBrightnessAdjustment()
        let firstID = viewModel.brightnessPresentation?.id

        service.brightness = 0.6
        viewModel.handleBrightnessAdjustment()

        XCTAssertEqual(viewModel.brightnessPresentation?.displayedPercentage, 60)
        XCTAssertNotEqual(viewModel.brightnessPresentation?.id, firstID)
    }

    func testDisabledToggleSuppressesAndClearsPresentation() async {
        let settings = IslandNotificationSettings(defaults: nil)
        settings.isBrightnessAdjustmentEnabled = false
        let service = StubBrightnessProvider(brightness: 0.6)
        let viewModel = makeViewModel(service: service, settings: settings)

        viewModel.handleBrightnessAdjustment()
        XCTAssertNil(viewModel.brightnessPresentation)

        settings.isBrightnessAdjustmentEnabled = true
        viewModel.handleBrightnessAdjustment()
        XCTAssertNotNil(viewModel.brightnessPresentation)

        settings.isBrightnessAdjustmentEnabled = false
        XCTAssertNil(viewModel.brightnessPresentation)
    }

    func testExpandedIslandSuppressesAndClearsPresentation() async {
        let notchViewModel = makeNotchViewModel()
        notchViewModel.click()
        let service = StubBrightnessProvider(brightness: 0.6)
        let viewModel = makeViewModel(service: service, notchViewModel: notchViewModel)

        viewModel.handleBrightnessAdjustment()
        XCTAssertNil(viewModel.brightnessPresentation)

        notchViewModel.click()
        viewModel.handleBrightnessAdjustment()
        XCTAssertNotNil(viewModel.brightnessPresentation)

        notchViewModel.click()
        XCTAssertNil(viewModel.brightnessPresentation)
    }

    func testPresentationDismissesAutomatically() async throws {
        let service = StubBrightnessProvider(brightness: 0.5)
        let viewModel = makeViewModel(service: service, displayDuration: .milliseconds(20))

        viewModel.handleBrightnessAdjustment()
        XCTAssertNotNil(viewModel.brightnessPresentation)

        try await Task.sleep(for: .milliseconds(60))
        XCTAssertNil(viewModel.brightnessPresentation)
        XCTAssertEqual(viewModel.compactPresentationIdentity, .none)
    }

    func testActivateStartsInterceptorAndDeactivateStopsIt() {
        let service = StubBrightnessProvider(brightness: 0.5)
        let interceptor = StubBrightnessInterceptor()
        let viewModel = makeViewModel(service: service, interceptor: interceptor)

        viewModel.activate()
        XCTAssertTrue(interceptor.isStarted)

        viewModel.handleBrightnessAdjustment()
        XCTAssertNotNil(viewModel.brightnessPresentation)

        viewModel.deactivate()
        XCTAssertTrue(interceptor.isStopped)
        XCTAssertNil(viewModel.brightnessPresentation)
    }

    func testBrightnessModuleDoesNotTakeResidentCompactSlot() {
        let module = BrightnessModule(notificationSettings: IslandNotificationSettings(defaults: nil))
        XCTAssertFalse(module.isCompactModuleEnabled)
    }

    private func makeViewModel(
        service: StubBrightnessProvider,
        settings: IslandNotificationSettings? = nil,
        notchViewModel: NotchViewModel? = nil,
        interceptor: StubBrightnessInterceptor? = nil,
        displayDuration: Duration = .milliseconds(100)
    ) -> BrightnessViewModel {
        BrightnessViewModel(
            brightnessService: service,
            notificationSettings: settings ?? IslandNotificationSettings(defaults: nil),
            notchViewModel: notchViewModel,
            keyInterceptor: interceptor,
            displayDuration: displayDuration
        )
    }

    private func makeNotchViewModel() -> NotchViewModel {
        NotchViewModel(
            interactionSettings: NotchInteractionSettings(defaults: nil, startsHidden: true)
        )
    }
}

@MainActor
private final class StubBrightnessInterceptor: BrightnessKeyIntercepting {
    private(set) var isStarted = false
    private(set) var isStopped = false

    func start() {
        isStarted = true
    }

    func stop() {
        isStopped = true
    }
}

private final class StubBrightnessProvider: BrightnessProviding {
    var brightness: Double?
    private(set) var lastCommand: BrightnessCommand?

    init(brightness: Double?) {
        self.brightness = brightness
    }

    func currentBrightness() -> Double? {
        brightness
    }

    func perform(_ command: BrightnessCommand) -> Bool {
        lastCommand = command
        guard let brightness else { return false }
        self.brightness = BrightnessStep.target(from: brightness, command: command)
        return true
    }
}