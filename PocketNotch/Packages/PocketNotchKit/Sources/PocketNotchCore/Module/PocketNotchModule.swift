import SwiftUI
import PocketNotchShared

public enum ExpandedIslandTab: String, Hashable, Sendable, CaseIterable {
    case home
    case applications
    case ai
    case stocks
    case transfer
    case folders
    case agentSessions
    case clipboard

    /// 「此刻」首页快照预览标签，暂未纳入默认顺序与设置管理。
    case now

    // 临时假标签：仅用于预览多标签布局，确认后删除。
    case demoWeather
    case demoCalendar
    case demoMusic
    case demoNotes
    case demoGallery
    case demoMail
    case demoMessages
    case demoTimer
    case demoTV
    case demoWallet

    /// 展开页标签栏支持独立入口的标签，按默认顺序排列。
    /// 标签栏固定左侧为「此刻」，其后跟随本序列；当前保留
    /// 应用程序 / 隔空传输 / Agent 会话 / 剪贴板 / 股票 五个入口。
    public static let defaultOrder: [ExpandedIslandTab] = [
        .applications, .transfer, .agentSessions, .clipboard, .stocks,
    ]

    public var displayName: String {
        switch self {
        case .home: L10n.tr("tab.home")
        case .applications: L10n.tr("tab.applications")
        case .ai: L10n.tr("tab.ai")
        case .stocks: L10n.tr("tab.stocks")
        case .transfer: L10n.tr("tab.transfer")
        case .folders: L10n.tr("tab.folders")
        case .agentSessions: L10n.tr("tab.agentSessions")
        case .clipboard: L10n.tr("tab.clipboard")
        case .now: L10n.tr("tab.now")

        // 临时假标签，确认后删除。
        case .demoWeather: L10n.tr("tab.demoWeather")
        case .demoCalendar: L10n.tr("tab.demoCalendar")
        case .demoMusic: L10n.tr("tab.demoMusic")
        case .demoNotes: L10n.tr("tab.demoNotes")
        case .demoGallery: L10n.tr("tab.demoGallery")
        case .demoMail: L10n.tr("tab.demoMail")
        case .demoMessages: L10n.tr("tab.demoMessages")
        case .demoTimer: L10n.tr("tab.demoTimer")
        case .demoTV: L10n.tr("tab.demoTV")
        case .demoWallet: L10n.tr("tab.demoWallet")
        }
    }
}

/// 所有功能模块的统一契约。Core 只认此协议，不认任何具体模块（依赖倒置）。
public protocol PocketNotchModule: Identifiable {
    /// 唯一标识，如 "media"、"shelf"、"systemStats"。
    var id: String { get }
    var title: LocalizedStringKey { get }
    /// 岛内排列顺序，数值越小越靠前。
    var priority: Int { get }
    /// 是否参与收起态常驻内容竞争；关闭后仍可保留临时通知。
    @MainActor var isCompactModuleEnabled: Bool { get }

    /// resting 状态下贴合刘海的小展示内容。
    func minimalView() -> AnyView
    /// compact 状态的前导内容（外缘对齐）。默认无。
    func hiddenLeadingView() -> AnyView
    /// compact 状态的尾随内容（外缘对齐）。默认无。
    func hiddenTrailingView() -> AnyView
    /// 是否在设置中心的灵动预览轮播中出现。
    @MainActor var showsInCompactSettingsPreview: Bool { get }
    /// 设置中心开关是否允许该模块进入预览轮播。
    @MainActor var isCompactSettingsPreviewEnabled: Bool { get }
    /// 模块预览需要的最小 Island 主体宽度；`nil` 表示沿用外观设置。
    @MainActor var compactSettingsPreviewPreferredWidth: CGFloat? { get }
    /// 设置预览使用样例数据，但必须复用模块正式态的无状态视觉组件。
    @MainActor func compactSettingsPreviewLeadingView() -> AnyView
    @MainActor func compactSettingsPreviewTrailingView() -> AnyView
    /// 短暂 compact 通知的前导内容。始终覆盖在当前常驻模块之上，默认无。
    func compactNotificationLeadingView() -> AnyView
    /// 短暂 compact 通知的尾随内容。始终覆盖在当前常驻模块之上，默认无。
    func compactNotificationTrailingView() -> AnyView
    /// 当前是否有可见的临时内容，以及其优先级（数值越大越优先抢先显示）。
    /// 返回 `nil` 表示此刻没有临时内容；非 `nil` 时，同区临时层只显示优先级最高的那个，
    /// 避免 Agent、切歌、音量等临时内容在右耳同区重叠。默认无临时。
    @MainActor func transientVisualPriority() -> Int?
    /// 刘海下方的通知背板（如切歌弹窗）。默认无——非空时容器会撑高窗口容纳它。
    func notificationView() -> AnyView

    /// 是否在完整展开页面中展示。仅提供独立展开页面的模块设为 true。
    var showsInExpandedPage: Bool { get }
    /// 模块在完整展开态中所属的标签页。
    var expandedIslandTab: ExpandedIslandTab { get }
    /// 展开页内的相对布局权重。多个模块按权重比例分配宽度——
    /// 例如权重 6.8 和 3.2 产生 68/32 分栏。默认 1（等宽）。
    var expandedPageWeight: CGFloat { get }
    /// 模块希望获得的展开内容高度。Core 会按当前标签页取最大值并限制在安全范围内。
    var expandedPagePreferredContentHeight: CGFloat? { get }
    var expandedPagePreferredContentWidth: CGFloat? { get }
    /// 覆盖完整展开分栏（包含顶部菜单栏衔接区）的背景。默认透明。
    func expandedBackgroundView() -> AnyView
    /// 展开页顶部栏右侧的模块附件。返回 nil 时沿用全局设置按钮。
    @MainActor func expandedHeaderAccessoryView() -> AnyView?
/// 「此刻」首页左侧的模块附件（如主页音乐组件副本）。Core 只在 `.now` 标签页渲染；
    /// 返回 nil 表示不提供。默认无。
    @MainActor func nowPageLeadingAccessoryView() -> AnyView?
    /// 「此刻」页左侧附件与中央栏之间的模块附件（如等比例放大的封面卡）。
    /// Core 把它渲染在左侧附件之后、中央栏之前；返回 nil 表示不提供。默认无。
    @MainActor func nowPageMidAccessoryView() -> AnyView?
    /// 「此刻」页居中的模块附件（如待办卡片）。Core 把它渲染在用户信息与
    /// 右侧附件之间的中央栏，与下部内容同层可交互；返回 nil 表示不提供。默认无。
    @MainActor func nowPageCenterAccessoryView() -> AnyView?
    /// 「此刻」页中心附件之后、剪贴板卡左侧的模块附件（如常用文件夹卡）。
    /// Core 把它渲染在中心栏之后、剪贴板卡之前；返回 nil 表示不提供。默认无。
    @MainActor func nowPageFolderAccessoryView() -> AnyView?
    /// 「此刻」页中心附件之后、最右卡片左侧的模块附件（如剪贴板卡）。
    /// Core 把它渲染在中心栏之后、右侧附件之前；返回 nil 表示不提供。默认无。
    @MainActor func nowPageTrailingAccessoryView() -> AnyView?
    /// 「此刻」页剪贴板卡之后、右区系统信息卡之前的模块附件（如计时器卡）。
    /// Core 把它渲染在剪贴板卡之后、右区附件之前；返回 nil 表示不提供。默认无。
    @MainActor func nowPageTimerAccessoryView() -> AnyView?
    /// 「此刻」页右区最右侧的模块附件，贴右边框垂直居中（如系统信息卡）。
    /// 返回 nil 表示不提供。默认无。
    @MainActor func nowPageRightAccessoryView() -> AnyView?
    /// 「此刻」页右区系统信息卡之后的模块附件，与系统信息卡同尺寸（如 CPU 环形概览卡）。
    /// 返回 nil 表示不提供。默认无。
    @MainActor func nowPageRightmostAccessoryView() -> AnyView?
    /// compact 常驻内容与「此刻」页之间的元素接力描述（如媒体封面）。
    /// Core 在展开/收起过渡中用它把 compact 耳内的元素无缝搬进「此刻」页。
    /// 返回 nil 表示不参与接力。默认无。
    @MainActor var contentHandoffDescriptor: IslandContentHandoffDescriptor? { get }

    /// 完整展开态专属页面；不得复用 resting / compact 视图。
    func expandedView() -> AnyView

    /// 是否提供简约模式下的展开内容。开启简约模式时，Core 只展示
    /// 声明了简约视图的模块，并调用 `expandedMinimalView()`。
    var supportsMinimalExpandedView: Bool { get }
    /// 简约模式下展开内容的宽高比（宽度 / 高度）。Core 用展开高度乘以该比例
    /// 计算展开宽度，避免默认的固定大画布留白过多；`nil` 表示沿用默认展开尺寸。
    var expandedMinimalContentAspectRatio: CGFloat? { get }
    /// 简约内容自身已经包含的顶部 inset。Core 会从外层目标间距中扣除该值，
    /// 让首个可见元素与当前刘海保持准确距离。
    var expandedMinimalContentInternalTopInset: CGFloat { get }
    /// 简约模式的完整展开页。默认回退到 `expandedView()`。
    func expandedMinimalView() -> AnyView

    /// 处理从 Island 根拖放会话提交的文件。location 使用 Island 展开画布的归一化坐标。
    @MainActor
    func handleFileDrop(_ urls: [URL], at location: CGPoint) -> Bool

    /// 模块被启用（开始订阅/轮询）。
    func activate()
    /// 模块被关闭（务必停止所有定时器/轮询/动画，耗电铁律）。
    func deactivate()
}

public extension PocketNotchModule {
    var isCompactModuleEnabled: Bool { true }
    func minimalView() -> AnyView {
        AnyView(EmptyView())
    }

    func hiddenLeadingView() -> AnyView {
        AnyView(EmptyView())
    }

    func hiddenTrailingView() -> AnyView {
        AnyView(EmptyView())
    }

    var showsInCompactSettingsPreview: Bool { false }

    var isCompactSettingsPreviewEnabled: Bool { false }

    var compactSettingsPreviewPreferredWidth: CGFloat? { nil }

    func compactSettingsPreviewLeadingView() -> AnyView {
        AnyView(EmptyView())
    }

    func compactSettingsPreviewTrailingView() -> AnyView {
        AnyView(EmptyView())
    }

    func compactNotificationLeadingView() -> AnyView {
        AnyView(EmptyView())
    }

    func compactNotificationTrailingView() -> AnyView {
        AnyView(EmptyView())
    }

    @MainActor func transientVisualPriority() -> Int? {
        nil
    }

    func notificationView() -> AnyView {
        AnyView(EmptyView())
    }

    var showsInExpandedPage: Bool { false }

    var expandedIslandTab: ExpandedIslandTab { .home }

    var expandedPageWeight: CGFloat { 1 }

    var expandedPagePreferredContentHeight: CGFloat? { nil }
    var expandedPagePreferredContentWidth: CGFloat? { nil }

    func expandedBackgroundView() -> AnyView {
        AnyView(Color.clear)
    }

    @MainActor
    func expandedHeaderAccessoryView() -> AnyView? {
        nil
    }

    @MainActor
    func nowPageLeadingAccessoryView() -> AnyView? {
        nil
    }

    @MainActor
    func nowPageMidAccessoryView() -> AnyView? {
        nil
    }

    @MainActor
    func nowPageCenterAccessoryView() -> AnyView? {
        nil
    }

    @MainActor
    func nowPageFolderAccessoryView() -> AnyView? {
        nil
    }

    @MainActor
    func nowPageTrailingAccessoryView() -> AnyView? {
        nil
    }

    @MainActor
    func nowPageTimerAccessoryView() -> AnyView? {
        nil
    }

    @MainActor
    func nowPageRightAccessoryView() -> AnyView? {
        nil
    }

    @MainActor
    func nowPageRightmostAccessoryView() -> AnyView? {
        nil
    }

    @MainActor var contentHandoffDescriptor: IslandContentHandoffDescriptor? { nil }

    func expandedView() -> AnyView {
        AnyView(EmptyView())
    }

    var supportsMinimalExpandedView: Bool { false }

    var expandedMinimalContentAspectRatio: CGFloat? { nil }

    var expandedMinimalContentInternalTopInset: CGFloat { 0 }

    func expandedMinimalView() -> AnyView {
        expandedView()
    }

    @MainActor
    func handleFileDrop(_ urls: [URL], at location: CGPoint) -> Bool {
        false
    }
}
