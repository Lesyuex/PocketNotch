import XCTest
import PocketNotchCore
@testable import SystemStatsModule

@MainActor
final class SystemStatsViewModelTests: XCTestCase {
    func testActivateReadsBatteryWithoutPresentingWhenOnBatteryPower() {
        let service = StubBatteryProvider(snapshot: battery(level: 0.64, connected: false))
        let viewModel = SystemStatsViewModel(batteryService: service)

        viewModel.activate()

        XCTAssertEqual(viewModel.battery?.percentage, 64)
        XCTAssertNil(viewModel.powerPresentation)
        XCTAssertTrue(service.isObserving)
    }

    func testCompactPresentationIdentityChangesFromNoneToPowerAndBack() async {
        let settings = IslandNotificationSettings(defaults: nil)
        let service = StubBatteryProvider(snapshot: battery(level: 0.64, connected: false))
        let viewModel = SystemStatsViewModel(
            batteryService: service,
            notificationSettings: settings
        )
        viewModel.activate()
        XCTAssertEqual(viewModel.compactPresentationIdentity, .none)

        service.snapshot = battery(level: 0.65, charging: true, connected: true)
        service.triggerChange()
        await Task.yield()
        guard case .power = viewModel.compactPresentationIdentity else {
            return XCTFail("Expected a power presentation identity")
        }

        settings.isPowerStatusEnabled = false
        XCTAssertEqual(viewModel.compactPresentationIdentity, .none)
    }

    func testActivateSuppressesChargingPresentationWhenPowerIsAlreadyConnected() {
        let service = StubBatteryProvider(
            snapshot: battery(level: 0.72, charging: true, connected: true)
        )
        let viewModel = SystemStatsViewModel(batteryService: service)

        viewModel.activate()

        XCTAssertEqual(viewModel.battery?.percentage, 72)
        XCTAssertNil(viewModel.powerPresentation)
    }

    func testFirstObservedBatterySnapshotDoesNotPresentChargingState() async {
        let service = StubBatteryProvider(snapshot: nil)
        let viewModel = SystemStatsViewModel(batteryService: service)
        viewModel.activate()

        service.snapshot = battery(level: 0.72, charging: true, connected: true)
        service.triggerChange()
        await Task.yield()

        XCTAssertEqual(viewModel.battery?.percentage, 72)
        XCTAssertNil(viewModel.powerPresentation)
    }

    func testConnectingAndDisconnectingPowerProducePresentations() async {
        let service = StubBatteryProvider(snapshot: battery(level: 0.60, connected: false))
        let viewModel = SystemStatsViewModel(batteryService: service)
        viewModel.activate()

        service.snapshot = battery(level: 0.61, charging: true, connected: true)
        service.triggerChange()
        await Task.yield()

        XCTAssertEqual(viewModel.powerPresentation?.kind, .charging)
        XCTAssertEqual(viewModel.battery?.percentage, 61)
        let connectedIdentity = viewModel.compactPresentationIdentity

        service.snapshot = battery(level: 0.62, connected: false)
        service.triggerChange()
        await Task.yield()

        XCTAssertEqual(viewModel.powerPresentation?.kind, .disconnected)
        XCTAssertNotEqual(viewModel.compactPresentationIdentity, connectedIdentity)
    }

    func testExpandedIslandSuppressesPowerPresentationButKeepsBatteryCurrent() async {
        let notchViewModel = makeNotchViewModel()
        notchViewModel.click()
        let service = StubBatteryProvider(snapshot: battery(level: 0.60, connected: false))
        let viewModel = SystemStatsViewModel(
            batteryService: service,
            notchViewModel: notchViewModel
        )
        viewModel.activate()

        service.snapshot = battery(level: 0.61, charging: true, connected: true)
        service.triggerChange()
        await Task.yield()

        XCTAssertEqual(viewModel.battery?.percentage, 61)
        XCTAssertNil(viewModel.powerPresentation)

        notchViewModel.click()
        service.snapshot = battery(level: 0.62, connected: false)
        service.triggerChange()
        await Task.yield()

        XCTAssertEqual(viewModel.powerPresentation?.kind, .disconnected)
    }

    func testExpandingIslandImmediatelyClearsPowerPresentation() async {
        let notchViewModel = makeNotchViewModel()
        let service = StubBatteryProvider(
            snapshot: battery(level: 0.72, charging: true, connected: true)
        )
        let viewModel = SystemStatsViewModel(
            batteryService: service,
            notchViewModel: notchViewModel
        )
        viewModel.activate()
        service.snapshot = battery(level: 0.73, connected: false)
        service.triggerChange()
        await Task.yield()
        XCTAssertNotNil(viewModel.powerPresentation)

        notchViewModel.click()

        XCTAssertNil(viewModel.powerPresentation)
    }

    func testPowerFeedbackHasHigherPriorityThanMedia() {
        XCTAssertLessThan(SystemStatsModule().priority, 10)
    }

    func testChangingConnectedAdapterDoesNotRepeatChargingPresentation() async {
        let service = StubBatteryProvider(
            snapshot: BatterySnapshot(
                level: 0.50,
                isCharging: false,
                isCharged: false,
                isPowerConnected: false
            )
        )
        let viewModel = SystemStatsViewModel(batteryService: service)
        viewModel.activate()

        service.snapshot = battery(level: 0.50, charging: true, connected: true)
        service.triggerChange()
        await Task.yield()
        XCTAssertEqual(viewModel.powerPresentation?.kind, .charging)
        let initialPresentationID = viewModel.powerPresentation?.id

        service.snapshot = battery(level: 0.51, charging: true, connected: true)
        service.triggerChange()
        await Task.yield()

        XCTAssertEqual(viewModel.powerPresentation?.kind, .charging)
        XCTAssertEqual(viewModel.powerPresentation?.id, initialPresentationID)
    }

    func testChargingResumeInSamePowerConnectionDoesNotRepeatChargingPresentation() async {
        let service = StubBatteryProvider(snapshot: battery(level: 0.82, connected: false))
        let viewModel = SystemStatsViewModel(batteryService: service)
        viewModel.activate()

        service.snapshot = battery(level: 0.82, charging: true, connected: true)
        service.triggerChange()
        await Task.yield()
        XCTAssertEqual(viewModel.powerPresentation?.kind, .charging)

        service.snapshot = battery(level: 0.83, connected: true)
        service.triggerChange()
        await Task.yield()
        XCTAssertEqual(viewModel.powerPresentation?.kind, .charging)

        service.triggerChange()
        await Task.yield()

        XCTAssertEqual(viewModel.powerPresentation?.kind, .charged)
        let chargedPresentationID = viewModel.powerPresentation?.id

        service.snapshot = battery(level: 0.84, charging: true, connected: true)
        service.triggerChange()
        await Task.yield()

        XCTAssertEqual(viewModel.powerPresentation?.kind, .charged)
        XCTAssertEqual(viewModel.powerPresentation?.id, chargedPresentationID)
    }

    func testImmediateReconnectPresentsChargingAgain() async {
        let service = StubBatteryProvider(snapshot: battery(level: 0.82, connected: false))
        let viewModel = SystemStatsViewModel(batteryService: service)
        viewModel.activate()

        service.snapshot = battery(level: 0.82, charging: true, connected: true)
        service.triggerChange()
        await Task.yield()
        XCTAssertEqual(viewModel.powerPresentation?.kind, .charging)
        let firstChargingPresentationID = viewModel.powerPresentation?.id

        service.snapshot = battery(level: 0.83, connected: false)
        service.triggerChange()
        await Task.yield()
        XCTAssertEqual(viewModel.powerPresentation?.kind, .disconnected)

        service.snapshot = battery(level: 0.84, charging: true, connected: true)
        service.triggerChange()
        await Task.yield()

        XCTAssertEqual(viewModel.powerPresentation?.kind, .charging)
        XCTAssertNotEqual(viewModel.powerPresentation?.id, firstChargingPresentationID)
    }

    func testPowerNotificationSwitchSuppressesAndClearsPresentations() async {
        let settings = IslandNotificationSettings(defaults: nil)
        settings.isPowerStatusEnabled = false
        let service = StubBatteryProvider(snapshot: battery(level: 0.60, connected: false))
        let viewModel = SystemStatsViewModel(
            batteryService: service,
            notificationSettings: settings
        )
        viewModel.activate()

        service.snapshot = battery(level: 0.61, charging: true, connected: true)
        service.triggerChange()
        await Task.yield()
        XCTAssertNil(viewModel.powerPresentation)

        settings.isPowerStatusEnabled = true
        service.snapshot = battery(level: 0.62, connected: false)
        service.triggerChange()
        await Task.yield()
        XCTAssertEqual(viewModel.powerPresentation?.kind, .disconnected)

        settings.isPowerStatusEnabled = false
        XCTAssertNil(viewModel.powerPresentation)
    }

    func testPercentageOnlyChangeDoesNotCreatePresentation() async {
        let service = StubBatteryProvider(snapshot: battery(level: 0.60, connected: false))
        let viewModel = SystemStatsViewModel(batteryService: service)
        viewModel.activate()

        service.snapshot = battery(level: 0.61, connected: false)
        service.triggerChange()
        await Task.yield()

        XCTAssertEqual(viewModel.battery?.percentage, 61)
        XCTAssertNil(viewModel.powerPresentation)
    }

    func testDisconnectedBatteryCrossingLevelBandsCreatesNewPresentations() async {
        let service = StubBatteryProvider(snapshot: battery(level: 0.60, connected: false))
        let viewModel = SystemStatsViewModel(batteryService: service)
        viewModel.activate()

        service.snapshot = battery(level: 0.50, connected: false)
        service.triggerChange()
        await Task.yield()

        XCTAssertEqual(viewModel.powerPresentation?.kind, .disconnected)
        XCTAssertEqual(viewModel.powerPresentation?.battery.levelBand, .warning)
        let warningPresentationID = viewModel.powerPresentation?.id

        service.snapshot = battery(level: 0.49, connected: false)
        service.triggerChange()
        await Task.yield()

        XCTAssertEqual(viewModel.powerPresentation?.id, warningPresentationID)

        service.snapshot = battery(level: 0.20, connected: false)
        service.triggerChange()
        await Task.yield()

        XCTAssertEqual(viewModel.powerPresentation?.kind, .disconnected)
        XCTAssertEqual(viewModel.powerPresentation?.battery.levelBand, .critical)
        XCTAssertNotEqual(viewModel.powerPresentation?.id, warningPresentationID)
    }

    func testChargedFlagPresentsActualCompletionPercentage() async {
        let service = StubBatteryProvider(
            snapshot: battery(level: 0.94, charging: true, connected: true)
        )
        let viewModel = SystemStatsViewModel(batteryService: service)
        viewModel.activate()
        XCTAssertNil(viewModel.powerPresentation)
        let chargingPresentationID = viewModel.powerPresentation?.id

        service.snapshot = battery(level: 0.96, charged: true, connected: true)
        service.triggerChange()
        await Task.yield()

        XCTAssertEqual(viewModel.powerPresentation?.kind, .charged)
        XCTAssertEqual(viewModel.powerPresentation?.battery.percentage, 96)
        XCTAssertNotEqual(viewModel.powerPresentation?.id, chargingPresentationID)
    }

    func testFullBatteryPercentagePresentsCompletionWhenChargedFlagIsMissing() async {
        let service = StubBatteryProvider(
            snapshot: battery(level: 0.94, charging: true, connected: true)
        )
        let viewModel = SystemStatsViewModel(batteryService: service)
        viewModel.activate()
        XCTAssertNil(viewModel.powerPresentation)

        service.snapshot = battery(level: 1, connected: true)
        service.triggerChange()
        await Task.yield()

        XCTAssertEqual(viewModel.powerPresentation?.kind, .charged)
        XCTAssertEqual(viewModel.powerPresentation?.battery.percentage, 100)
    }

    func testStoppingChargeAtConfiguredLimitPresentsCompletion() async {
        let service = StubBatteryProvider(
            snapshot: battery(level: 0.80, charging: true, connected: true)
        )
        let viewModel = SystemStatsViewModel(batteryService: service)
        viewModel.activate()
        XCTAssertNil(viewModel.powerPresentation)

        service.snapshot = battery(level: 0.80, connected: true)
        service.triggerChange()
        await Task.yield()

        XCTAssertNil(viewModel.powerPresentation)

        service.triggerChange()
        await Task.yield()

        XCTAssertEqual(viewModel.powerPresentation?.kind, .charged)
        XCTAssertEqual(viewModel.powerPresentation?.battery.percentage, 80)
    }

    func testTransientChargingPauseDoesNotPresentCompletionBeforeConfirmation() async {
        let service = StubBatteryProvider(
            snapshot: battery(level: 0.82, charging: true, connected: true)
        )
        let viewModel = SystemStatsViewModel(batteryService: service)
        viewModel.activate()
        XCTAssertNil(viewModel.powerPresentation)

        service.snapshot = battery(level: 0.83, connected: true)
        service.triggerChange()
        await Task.yield()

        XCTAssertNil(viewModel.powerPresentation)

        service.snapshot = battery(level: 0.84, charging: true, connected: true)
        service.triggerChange()
        await Task.yield()

        XCTAssertNil(viewModel.powerPresentation)
    }

    func testConnectedRefreshDetectsConfiguredLimitWithoutPowerNotification() async throws {
        let service = StubBatteryProvider(
            snapshot: battery(level: 0.84, charging: true, connected: true)
        )
        let viewModel = SystemStatsViewModel(
            batteryService: service,
            connectedRefreshInterval: .milliseconds(10)
        )
        viewModel.activate()
        XCTAssertNil(viewModel.powerPresentation)
        let chargingPresentationID = viewModel.powerPresentation?.id

        service.snapshot = battery(level: 0.85, connected: true)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(viewModel.powerPresentation?.kind, .charged)
        XCTAssertEqual(viewModel.powerPresentation?.battery.percentage, 85)
        XCTAssertNotEqual(viewModel.powerPresentation?.id, chargingPresentationID)
    }

    func testBatteryLevelBandsUseNormalWarningAndCriticalThresholds() {
        XCTAssertEqual(battery(level: 0.51, connected: false).levelBand, .normal)
        XCTAssertEqual(battery(level: 0.50, connected: false).levelBand, .warning)
        XCTAssertEqual(battery(level: 0.21, connected: false).levelBand, .warning)
        XCTAssertEqual(battery(level: 0.20, connected: false).levelBand, .critical)
    }

    func testPresentationDismissesAutomatically() async throws {
        let service = StubBatteryProvider(
            snapshot: battery(level: 0.80, connected: false)
        )
        let viewModel = SystemStatsViewModel(
            batteryService: service,
            presentationDuration: .milliseconds(20)
        )

        viewModel.activate()
        service.snapshot = battery(level: 0.80, charging: true, connected: true)
        service.triggerChange()
        await Task.yield()
        XCTAssertNotNil(viewModel.powerPresentation)

        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(viewModel.powerPresentation)
    }

    func testDeactivateStopsObservationAndClearsPresentation() {
        let service = StubBatteryProvider(
            snapshot: battery(level: 1, charged: true, connected: true)
        )
        let viewModel = SystemStatsViewModel(batteryService: service)
        viewModel.activate()

        viewModel.deactivate()

        XCTAssertFalse(service.isObserving)
        XCTAssertNil(viewModel.powerPresentation)
    }

    private func makeNotchViewModel() -> NotchViewModel {
        NotchViewModel(
            interactionSettings: NotchInteractionSettings(defaults: nil, startsHidden: true)
        )
    }

    private func battery(
        level: Double,
        charging: Bool = false,
        charged: Bool = false,
        connected: Bool
    ) -> BatterySnapshot {
        BatterySnapshot(
            level: level,
            isCharging: charging,
            isCharged: charged,
            isPowerConnected: connected
        )
    }
}

private final class StubBatteryProvider: BatteryProviding {
    var snapshot: BatterySnapshot?
    private(set) var isObserving = false
    private var handler: (() -> Void)?

    init(snapshot: BatterySnapshot?) {
        self.snapshot = snapshot
    }

    func currentSnapshot() -> BatterySnapshot? {
        snapshot
    }

    func startObserving(_ handler: @escaping () -> Void) {
        isObserving = true
        self.handler = handler
    }

    func stopObserving() {
        isObserving = false
        handler = nil
    }

    func triggerChange() {
        handler?()
    }
}
