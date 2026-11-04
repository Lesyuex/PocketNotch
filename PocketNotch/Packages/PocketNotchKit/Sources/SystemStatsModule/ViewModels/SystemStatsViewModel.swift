import Combine
import Foundation
import PocketNotchCore
import Observation

public enum PowerPresentationKind: Equatable, Sendable {
    case connected
    case disconnected
    case charging
    case charged
}

enum CompactPowerPresentationIdentity: Equatable {
    case none
    case power(UUID)
}

public struct PowerPresentation: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: PowerPresentationKind
    public let battery: BatterySnapshot

    public init(id: UUID = UUID(), kind: PowerPresentationKind, battery: BatterySnapshot) {
        self.id = id
        self.kind = kind
        self.battery = battery
    }

    public var title: String {
        switch kind {
        case .connected: "已接通电源"
        case .disconnected: "充电断开"
        case .charging: "正在充电"
        case .charged: "充电完成"
        }
    }
}

@Observable
@MainActor
public final class SystemStatsViewModel {
    public private(set) var battery: BatterySnapshot?
    public private(set) var powerPresentation: PowerPresentation?

    var compactPresentationIdentity: CompactPowerPresentationIdentity {
        guard let powerPresentation else { return .none }
        return .power(powerPresentation.id)
    }

    private let batteryService: any BatteryProviding
    private let notificationSettings: IslandNotificationSettings
    private let notchViewModel: NotchViewModel?
    private let presentationDuration: Duration
    private let connectedRefreshInterval: Duration
    private var dismissTask: Task<Void, Never>?
    private var connectedRefreshTask: Task<Void, Never>?
    private var isActive = false
    private var hasHandledPowerForCurrentConnection = false
    private var hasSeenBatterySnapshot = false
    private var pendingChargeCompletion: BatterySnapshot?
    private var notificationSettingsCancellable: AnyCancellable?
    private var expansionStateCancellable: AnyCancellable?

    private var areNotificationsSuppressed: Bool {
        notchViewModel?.isExpanded == true
    }

    public convenience init() {
        self.init(
            batteryService: SystemBatteryService(),
            notificationSettings: IslandNotificationSettings()
        )
    }

    public convenience init(
        notificationSettings: IslandNotificationSettings,
        notchViewModel: NotchViewModel? = nil
    ) {
        self.init(
            batteryService: SystemBatteryService(),
            notificationSettings: notificationSettings,
            notchViewModel: notchViewModel
        )
    }

    init(
        batteryService: any BatteryProviding,
        presentationDuration: Duration = .seconds(3),
        connectedRefreshInterval: Duration = .seconds(5),
        notificationSettings: IslandNotificationSettings? = nil,
        notchViewModel: NotchViewModel? = nil
    ) {
        let notificationSettings = notificationSettings ?? IslandNotificationSettings(defaults: nil)
        self.batteryService = batteryService
        self.notificationSettings = notificationSettings
        self.notchViewModel = notchViewModel
        self.presentationDuration = presentationDuration
        self.connectedRefreshInterval = connectedRefreshInterval
        observeNotificationSettings(notificationSettings)
        observeExpansionState()
    }

    public func activate() {
        guard !isActive else { return }
        isActive = true

        let initialBattery = batteryService.currentSnapshot()
        battery = initialBattery
        hasSeenBatterySnapshot = initialBattery != nil
        recordHandledConnectionState(for: initialBattery)
        updateConnectedRefresh(for: initialBattery)

        batteryService.startObserving { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshFromPowerSourceChange()
            }
        }
    }

    public func deactivate() {
        isActive = false
        batteryService.stopObserving()
        stopConnectedRefresh()
        hasHandledPowerForCurrentConnection = false
        hasSeenBatterySnapshot = false
        pendingChargeCompletion = nil
        dismissTask?.cancel()
        dismissTask = nil
        powerPresentation = nil
    }

    /// 保留显式刷新入口，便于系统事件之外的诊断与测试。
    public func refresh() {
        battery = batteryService.currentSnapshot()
    }

    private func refreshFromPowerSourceChange() {
        guard isActive else { return }
        guard let newBattery = batteryService.currentSnapshot() else {
            battery = nil
            stopConnectedRefresh()
            pendingChargeCompletion = nil
            return
        }
        let previousBattery = battery
        battery = newBattery
        if !hasSeenBatterySnapshot {
            hasSeenBatterySnapshot = true
            recordHandledConnectionState(for: newBattery)
            updateConnectedRefresh(for: newBattery)
            return
        }
        updateConnectedRefresh(for: newBattery)

        guard let kind = presentationKind(from: previousBattery, to: newBattery) else { return }
        recordHandledConnectionEvent(kind)
        present(kind: kind, battery: newBattery)
    }

    private func initialKind(for battery: BatterySnapshot) -> PowerPresentationKind {
        if battery.isFullyCharged { return .charged }
        if battery.isCharging { return .charging }
        return .connected
    }

    private func presentationKind(
        from previous: BatterySnapshot?,
        to current: BatterySnapshot
    ) -> PowerPresentationKind? {
        guard let previous else {
            return current.isPowerConnected ? initialKind(for: current) : nil
        }

        if !previous.isFullyCharged, current.isFullyCharged {
            pendingChargeCompletion = nil
            return .charged
        }
        if previous.isPowerConnected != current.isPowerConnected {
            pendingChargeCompletion = nil
            if !current.isPowerConnected { return .disconnected }
            guard !hasHandledPowerForCurrentConnection else { return nil }
            return initialKind(for: current)
        }
        if previous.isPowerConnected,
           current.isPowerConnected,
           previous.isCharging,
           !current.isCharging {
            return confirmedChargeCompletionKind(for: current)
        }
        if previous.isPowerConnected,
           current.isPowerConnected,
           !previous.isCharging,
           !current.isCharging,
           pendingChargeCompletion != nil {
            return confirmedChargeCompletionKind(for: current)
        }
        if !previous.isCharging, current.isCharging {
            pendingChargeCompletion = nil
            guard !hasHandledPowerForCurrentConnection else { return nil }
            return .charging
        }
        if !current.isPowerConnected, previous.levelBand != current.levelBand {
            pendingChargeCompletion = nil
            return .disconnected
        }
        return nil
    }

    private func confirmedChargeCompletionKind(for battery: BatterySnapshot) -> PowerPresentationKind? {
        guard battery.isPowerConnected, !battery.isCharging else {
            pendingChargeCompletion = nil
            return nil
        }
        guard let pendingChargeCompletion else {
            self.pendingChargeCompletion = battery
            return nil
        }
        guard battery.percentage >= pendingChargeCompletion.percentage else {
            self.pendingChargeCompletion = battery
            return nil
        }
        self.pendingChargeCompletion = nil
        return .charged
    }

    private func recordHandledConnectionState(for battery: BatterySnapshot?) {
        hasHandledPowerForCurrentConnection = battery?.isPowerConnected == true
    }

    private func recordHandledConnectionEvent(_ kind: PowerPresentationKind) {
        switch kind {
        case .connected, .charging, .charged:
            hasHandledPowerForCurrentConnection = true
        case .disconnected:
            hasHandledPowerForCurrentConnection = false
        }
    }

    private func present(kind: PowerPresentationKind, battery: BatterySnapshot) {
        guard notificationSettings.isPowerStatusEnabled, !areNotificationsSuppressed else {
            clearPowerPresentation()
            return
        }
        dismissTask?.cancel()
        powerPresentation = PowerPresentation(kind: kind, battery: battery)

        dismissTask = Task { [weak self, presentationDuration] in
            do {
                try await Task.sleep(for: presentationDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.powerPresentation = nil
        }
    }

    private func observeExpansionState() {
        expansionStateCancellable = notchViewModel?.isExpandedPublisher
            .removeDuplicates()
            .sink { [weak self] isExpanded in
                if isExpanded { self?.clearPowerPresentation() }
            }
    }

    private func observeNotificationSettings(_ settings: IslandNotificationSettings) {
        notificationSettingsCancellable = settings.$isPowerStatusEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                if !enabled { self?.clearPowerPresentation() }
            }
    }

    private func clearPowerPresentation() {
        dismissTask?.cancel()
        dismissTask = nil
        powerPresentation = nil
    }

    private func updateConnectedRefresh(for battery: BatterySnapshot?) {
        if isActive, battery?.isPowerConnected == true {
            startConnectedRefreshIfNeeded()
        } else {
            stopConnectedRefresh()
        }
    }

    private func startConnectedRefreshIfNeeded() {
        guard connectedRefreshTask == nil else { return }
        connectedRefreshTask = Task { [weak self, connectedRefreshInterval] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: connectedRefreshInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.refreshFromPowerSourceChange()
            }
        }
    }

    private func stopConnectedRefresh() {
        connectedRefreshTask?.cancel()
        connectedRefreshTask = nil
    }

}
