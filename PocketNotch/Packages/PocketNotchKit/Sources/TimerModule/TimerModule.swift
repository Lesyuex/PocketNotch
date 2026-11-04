import PocketNotchCore
import SwiftUI

/// 计时器模块：只向「此刻」页提供计时器卡片（倒计时 + 正计时），不占独立标签页。
/// 卡片位于剪贴板卡与系统状态卡之间，运行状态由模块内的 `TimerStore` 持有，
/// 与岛展开/收起无关——收起岛后计时仍继续。
public struct TimerModule: PocketNotchModule {
    public let id = "timer"
    public let title: LocalizedStringKey = "module.timer.title"
    public let priority = 48

    @MainActor private let store = TimerStore()

    public init() {}

    public var showsInExpandedPage: Bool { true }

    public var expandedIslandTab: ExpandedIslandTab { .now }

    public func expandedView() -> AnyView {
        AnyView(Color.clear)
    }

    @MainActor
    public func nowPageTimerAccessoryView() -> AnyView? {
        AnyView(NowTimerCardView(store: store))
    }

    public func compactNotificationLeadingView() -> AnyView {
        AnyView(TimerCompletionLeadingView(store: store))
    }

    public func compactNotificationTrailingView() -> AnyView {
        AnyView(TimerCompletionTrailingView(store: store))
    }

    /// 倒计时完成临时通知优先级 25：高于音量/耳机（20）与 Agent（10），
    /// 让完成事件能抢占同区临时层。
    @MainActor public func transientVisualPriority() -> Int? {
        store.completionPresentation != nil ? 25 : nil
    }

    public func activate() {}

    public func deactivate() {
        Task { @MainActor in store.stop() }
    }
}
