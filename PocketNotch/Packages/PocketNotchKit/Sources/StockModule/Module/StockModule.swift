import Combine
import SwiftUI
import PocketNotchCore

/// 股票行情模块。展开页使用腾讯实时分时、五档与逐笔成交数据。
public struct StockModule: PocketNotchModule {
    public let id = "stocks"
    public let title: LocalizedStringKey = "module.stock.title"
    /// 股票行情需要在通知槽中优先于媒体、天气等模块显示。
    public let priority = 0

    @MainActor private let viewModel: StockNotificationViewModel
    @MainActor private let indexViewModel: StockMarketIndexViewModel
    @MainActor private let settings: StockSettings
    @MainActor private let residentSettings: CompactResidentSettings
    @MainActor private let stockMonitoringObserver: AnyCancellable
    @MainActor private let priorityCoordinator: StockPriorityCoordinator

    @MainActor
    public init() {
        let settings = StockSettings()
        let residentSettings = CompactResidentSettings()
        self.settings = settings
        self.residentSettings = residentSettings
        viewModel = StockNotificationViewModel(settings: settings)
        indexViewModel = StockMarketIndexViewModel()
        stockMonitoringObserver = settings.$isPersistent
            .removeDuplicates()
            .sink { [weak residentSettings] isEnabled in
                residentSettings?.setStockMonitoringEnabled(isEnabled)
            }
        priorityCoordinator = StockPriorityCoordinator(
            settings: settings,
            residentSettings: residentSettings
        )
    }

    @MainActor
    public init(settings: StockSettings, residentSettings: CompactResidentSettings) {
        self.settings = settings
        self.residentSettings = residentSettings
        viewModel = StockNotificationViewModel(settings: settings)
        indexViewModel = StockMarketIndexViewModel()
        stockMonitoringObserver = settings.$isPersistent
            .removeDuplicates()
            .sink { [weak residentSettings] isEnabled in
                residentSettings?.setStockMonitoringEnabled(isEnabled)
            }
        priorityCoordinator = StockPriorityCoordinator(
            settings: settings,
            residentSettings: residentSettings
        )
    }

    public var isCompactModuleEnabled: Bool {
        residentSettings.activeModule == .stocks
    }

    public func notificationView() -> AnyView {
        AnyView(EmptyView())
    }

    public func hiddenLeadingView() -> AnyView {
        AnyView(StockHiddenLeadingView(viewModel: viewModel))
    }

    public func hiddenTrailingView() -> AnyView {
        AnyView(StockHiddenTrailingView(viewModel: viewModel))
    }

    public var showsInCompactSettingsPreview: Bool { true }

    public var isCompactSettingsPreviewEnabled: Bool { settings.isPersistent }

    public var compactSettingsPreviewPreferredWidth: CGFloat? {
        CompactIslandTier.secondTierMinimumWidth
    }

    public func compactSettingsPreviewLeadingView() -> AnyView {
        AnyView(StockHiddenLeadingView(viewModel: viewModel))
    }

    public func compactSettingsPreviewTrailingView() -> AnyView {
        AnyView(StockHiddenTrailingView(viewModel: viewModel))
    }

    public var showsInExpandedPage: Bool { true }

    public var expandedIslandTab: ExpandedIslandTab { .stocks }

    public var expandedPagePreferredContentHeight: CGFloat? { 240 }

    @MainActor
    public func expandedHeaderAccessoryView() -> AnyView? {
        AnyView(StockMarketIndexHeaderView(viewModel: indexViewModel))
    }

    public func expandedView() -> AnyView {
        AnyView(StockExpandedView(viewModel: viewModel))
    }

    public func activate() {
        Task { @MainActor in viewModel.start() }
    }

    public func deactivate() {
        Task { @MainActor in viewModel.stop() }
    }
}

@MainActor
private final class StockPriorityCoordinator {
    private let settings: StockSettings
    private weak var residentSettings: CompactResidentSettings?
    private var cancellables = Set<AnyCancellable>()
    private var boundaryRefreshTask: Task<Void, Never>?

    init(settings: StockSettings, residentSettings: CompactResidentSettings) {
        self.settings = settings
        self.residentSettings = residentSettings

        settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.refreshAndScheduleNextBoundary()
                }
            }
            .store(in: &cancellables)

        refreshAndScheduleNextBoundary()
    }

    deinit {
        boundaryRefreshTask?.cancel()
    }

    private func refreshAndScheduleNextBoundary() {
        boundaryRefreshTask?.cancel()
        residentSettings?.setStockPriorityActive(settings.isPriorityDisplayActive())
        boundaryRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.nanosecondsUntilNextMinute())
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.refreshAndScheduleNextBoundary()
            }
        }
    }

    private static func nanosecondsUntilNextMinute(
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> UInt64 {
        let components = calendar.dateComponents([.second, .nanosecond], from: date)
        let second = components.second ?? 0
        let nanosecond = components.nanosecond ?? 0
        let elapsedNanoseconds = UInt64(second) * 1_000_000_000
            + UInt64(max(nanosecond, 0))
        let minuteNanoseconds: UInt64 = 60 * 1_000_000_000
        let remaining = minuteNanoseconds > elapsedNanoseconds
            ? minuteNanoseconds - elapsedNanoseconds
            : 1_000_000
        return remaining + 50_000_000
    }
}
