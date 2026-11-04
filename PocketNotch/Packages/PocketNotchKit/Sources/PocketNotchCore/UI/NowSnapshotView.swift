import SwiftUI

/// 「此刻」首页快照：各信息块（音乐/天气时间/待办/CPU 等）在整行内平铺，
/// 每块独立成区、互不重叠，后续可由设置开关控制显隐。
///
/// 刘海位于屏幕顶部正中，是全屏最天然的「看时间」位置；页面保持安静、克制、
/// 无状态感，只服务「看一眼就懂」。附件由模块经 `nowPage*AccessoryView`
/// 注入，无附件时相应卡位自动空出。
struct NowSnapshotView: View {
    /// 左侧的模块附件（如媒体信息卡）。nil 时仅空出位置。
    var accessory: AnyView? = nil
    /// 左侧附件旁的模块附件。nil 时仅空出位置。
    var midAccessory: AnyView? = nil
    /// 左侧附件之后、剪贴板卡之前的模块附件（如待办卡）。nil 时仅空出位置。
    var centerAccessory: AnyView? = nil
    /// 计时器卡之后、右区系统信息卡之前的模块附件（如常用文件夹卡）。nil 时仅空出位置。
    var folderAccessory: AnyView? = nil
    /// 待办卡之后、计时器卡之前的模块附件（如剪贴板卡）。nil 时仅空出位置。
    var trailingAccessory: AnyView? = nil
    /// 剪贴板卡之后、常用文件夹卡之前的模块附件（如计时器卡）。nil 时仅空出位置。
    var timerAccessory: AnyView? = nil
    /// 右区最右侧的模块附件（如系统信息卡 2），固定宽度。nil 时仅空出位置。
    var rightAccessory: AnyView? = nil
    /// 右区系统信息卡之后的系统状态卡（如 CPU 环形概览），与系统信息卡同尺寸。nil 时仅空出位置。
    var rightmostAccessory: AnyView? = nil

    private static let cardSpacing: CGFloat = IslandLayoutToken.expandedNowPageCardSpacing
    private static let cardHeight: CGFloat = IslandLayoutToken.expandedNowPageCardHeight

    var body: some View {
        HStack(spacing: Self.cardSpacing) {
            if let accessory {
                accessory
                    .frame(
                        width: IslandLayoutToken.expandedNowPageLeadingCardWidth,
                        height: Self.cardHeight
                    )
            }
            if let centerAccessory {
                centerAccessory
                    .frame(width: 180, height: Self.cardHeight, alignment: .top)
            }
            if let trailingAccessory {
                trailingAccessory
                    .frame(
                        width: IslandLayoutToken.expandedNowPageClipboardCardWidth,
                        height: Self.cardHeight,
                        alignment: .top
                    )
            }
            if let folderAccessory {
                folderAccessory
                    .frame(
                        width: IslandLayoutToken.expandedNowPageQuickStatsCardWidth,
                        height: Self.cardHeight,
                        alignment: .top
                    )
            }
            if let timerAccessory {
                timerAccessory
                    .frame(
                        width: IslandLayoutToken.expandedNowPageTimerCardWidth,
                        height: Self.cardHeight,
                        alignment: .top
                    )
            }
            if let rightAccessory {
                rightAccessory
                    .frame(
                        width: IslandLayoutToken.expandedNowPageSystemCardWidth,
                        height: Self.cardHeight,
                        alignment: .top
                    )
            }
            if let rightmostAccessory {
                rightmostAccessory
                    .frame(
                        width: IslandLayoutToken.expandedNowPageSystemStatusCardWidth,
                        height: Self.cardHeight,
                        alignment: .top
                    )
            }
        }
        .padding(.horizontal, IslandLayoutToken.expandedNowPageHorizontalInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
