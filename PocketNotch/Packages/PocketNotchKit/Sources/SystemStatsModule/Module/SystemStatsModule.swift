import PocketNotchCore
import SwiftUI

/// 电源事件模块。作为短暂系统反馈覆盖媒体和天气，结束后自动恢复原内容。
public struct SystemStatsModule: PocketNotchModule {
    public let id = "systemStats"
    public let title: LocalizedStringKey = "module.systemStats.title"
    public let priority = 5

    /// 参与完整展开页的模块收集链（nowPage* 附件注入点从该链取附件）；
    /// 无独立分栏内容——挂在「此刻」页，该页走专用布局不会把本模块渲染成分栏列。
    public var showsInExpandedPage: Bool { true }
    public var expandedIslandTab: ExpandedIslandTab { .now }

    @MainActor private let viewModel: SystemStatsViewModel
    @MainActor private let systemStatusViewModel: NowPageSystemStatusViewModel
    @MainActor private let notchViewModel: NotchViewModel?

    @MainActor
    public init() {
        viewModel = SystemStatsViewModel()
        systemStatusViewModel = NowPageSystemStatusViewModel()
        notchViewModel = nil
    }

    @MainActor
    public init(
        notificationSettings: IslandNotificationSettings,
        notchViewModel: NotchViewModel? = nil
    ) {
        viewModel = SystemStatsViewModel(
            notificationSettings: notificationSettings,
            notchViewModel: notchViewModel
        )
        self.notchViewModel = notchViewModel
        // 采样跟随岛展开态（收起即停），module activate 不再启动常驻轮询。
        systemStatusViewModel = NowPageSystemStatusViewModel(
            notchViewModel: notchViewModel
        )
    }

    public func compactNotificationLeadingView() -> AnyView {
        AnyView(PowerHiddenLeadingView(viewModel: viewModel))
    }

    public func compactNotificationTrailingView() -> AnyView {
        AnyView(PowerHiddenTrailingView(viewModel: viewModel))
    }

    /// 临时优先级：电源/电量等系统反馈为 15（介于切歌 20 与 Agent 运行 10 之间）。
    @MainActor public func transientVisualPriority() -> Int? {
        viewModel.powerPresentation != nil ? 15 : nil
    }

    /// 「此刻」页系统状态卡（最右）：CPU 利用率 + 温度 + 风险分 + 底部三指标总览。
    @MainActor public func nowPageRightmostAccessoryView() -> AnyView? {
        AnyView(NowPageSystemStatusCardView(viewModel: systemStatusViewModel))
    }

    public func activate() {
        Task { @MainActor in
            viewModel.activate()
            // 无展开门控（未注入 notchViewModel）的场景由 activate 兜底启动轮询；
            // 常规路径采样已由「展开→采、收起→停」驱动。
            if notchViewModel == nil {
                systemStatusViewModel.startPolling()
            }
        }
    }

    public func deactivate() {
        Task { @MainActor in
            viewModel.deactivate()
            if notchViewModel == nil {
                systemStatusViewModel.stopPolling()
            }
        }
    }
}
