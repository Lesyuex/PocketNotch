import AppKit
import CoreGraphics

/// Island 布局参数的唯一入口。
public enum IslandLayoutToken {
    public static let hoverExpansion = CGSize(width: 10, height: 2)
    public static let hoverSideVerticalOffset: CGFloat = 1
    public static let hoverContentScale: CGFloat = 1.006
    /// 展开态默认整窗总宽度（含两侧肩部）。窗口还需两侧 `hoverOutset` 出界预算，
    /// 超过屏幕可用宽度会被屏幕直接裁掉、内容左右溢出，因此钳制在主屏幕宽度减出界预算之内。
    public static var expandedDefaultWidth: CGFloat {
        let preferred: CGFloat = 999
        let screenMax = (NSScreen.main?.frame.width ?? preferred) - hoverOutset * 2
        return min(preferred, max(screenMax, 1))
    }
    /// 展开态默认主体宽度（不含两侧肩部）。
    public static var expandedDefaultBodyWidth: CGFloat {
        expandedDefaultWidth - NotchShapeSpec.expandedCornerRadius * 2
    }
    /// 「此刻」页侧区宽度（如左侧音乐组件续宽）：主此刻页主体宽度减去隐藏态刘海
    /// 默认长度后均分给两侧。
    public static var expandedNowPageSideWidth: CGFloat {
        (expandedNowPageTotalWidth - NotchShapeSpec.expandedCornerRadius * 2 - IslandAppearanceConstraints.defaultRestingWidth) / 2
    }
    public static let expandedContentHeight: CGFloat = 122
    /// 「此刻」页内容区高度：整窗总高（刘海 32 + 画布 + 内距 8×2）= 168。
    public static let expandedNowPageContentHeight: CGFloat = 120
    /// 「此刻」页整窗目标总高：以含顶部刘海的整窗高度为锚点倒推内容画布高度，
    /// 隐藏态高度变化时整窗仍严格保持该值（参考 NotchShape.resolved 的 total 分支）。
    public static let expandedNowPageTotalHeight: CGFloat = 168
    public static let maximumExpandedContentHeight: CGFloat = 512
    public static let expandedContentTopInset: CGFloat = 8
    public static let expandedContentVerticalInset: CGFloat = 8
    /// 「此刻」页整窗宽度（含两侧肩部）：内容自适应折叠为基准宽度，
    /// 其余标签页的展开宽度跟随该值，保证跨标签视觉一致。
    public static var expandedNowPageTotalWidth: CGFloat {
        expandedNowPageContentWidth + NotchShapeSpec.expandedCornerRadius * 2
    }
    /// 「此刻」页内容画布宽度：卡片宽度累加 + 卡片间距 + 贴边留白 8×2。
    /// 减一行卡片或调整卡宽时，窗口宽度自动跟随。
    public static var expandedNowPageContentWidth: CGFloat {
        expandedNowPageCardWidths.reduce(0, +)
            + expandedNowPageCardSpacing * CGFloat(max(expandedNowPageCardWidths.count - 1, 0))
            + expandedNowPageHorizontalInset * 2
    }
    /// 「此刻」页左侧首位信息卡（媒体卡）的固定宽度。单一真源，
    /// 卡渲染（MediaModule）与此刻页容器（PocketNotchCore）共用，避免多处写死漂移。
    public static let expandedNowPageLeadingCardWidth: CGFloat = 210
    /// 「此刻」页全部卡片的统一画布高度：媒体卡、时间卡、待办卡、系统卡共用，
    /// 保证整行等高；（此刻页整窗 168 = 标签栏 32 + 卡片画布 136）。
    public static let expandedNowPageCardHeight: CGFloat = 136
    /// 「此刻」页标准信息卡（待办/剪贴板）的固定宽度。
    public static let expandedNowPageStandardCardWidth: CGFloat = 180
    /// 「此刻」页系统信息卡（右区）的固定宽度。单一真源，
    /// 卡渲染（SystemStatsModule）与此刻页容器（PocketNotchCore）共用，避免多处写死漂移。
    public static let expandedNowPageSystemCardWidth: CGFloat = 180
    /// 「此刻」页系统状态卡（系统信息卡右侧，CPU 环形概览）的固定宽度，与系统信息卡同尺寸。
    /// 单一真源，卡渲染（SystemStatsModule）与此刻页容器（PocketNotchCore）共用，避免多处写死漂移。
    public static let expandedNowPageSystemStatusCardWidth: CGFloat = expandedNowPageSystemCardWidth
    /// 「此刻」页常用文件夹小卡盒（待办卡之后、剪贴板卡左侧，4 张 56×40 同尺寸小卡）的固定宽度。
    /// 单一真源，卡渲染（RecentFoldersModule）与此刻页容器（PocketNotchCore）共用，避免多处写死漂移。
    public static let expandedNowPageQuickStatsCardWidth: CGFloat = 128
    /// 「此刻」页剪贴板卡（右区最右卡片左侧）的固定宽度。单一真源，
    /// 卡渲染（ClipboardModule）与此刻页容器（PocketNotchCore）共用，避免多处写死漂移。
    public static let expandedNowPageClipboardCardWidth: CGFloat = 180
    /// 「此刻」页计时器卡（剪贴板卡之后、系统状态卡之前，倒计时/正计时）的固定宽度。
    /// 单一真源，卡渲染（TimerModule）与此刻页容器（PocketNotchCore）共用，避免多处写死漂移。
    public static let expandedNowPageTimerCardWidth: CGFloat = 150
    /// 「此刻」页信息卡之间的水平间距。
    public static let expandedNowPageCardSpacing: CGFloat = 8
    /// 「此刻」页最左/最右卡片相对画布边缘的留白。
    public static let expandedNowPageHorizontalInset: CGFloat = 8
    /// 「此刻」页当前默认信息卡宽度序列（从左到右）：媒体卡 + 标准卡 + 常用文件夹小卡盒 + 剪贴板卡 + 计时器卡 + 系统状态卡。
    /// 此时刻页整行 = 媒体卡 | 待办卡 | 常用文件夹小卡盒 | 剪贴板卡 | 计时器卡 | 系统状态卡。
    /// 增删信息块时需同步该数组与运行中的附件，宽度自适应。
    public static let expandedNowPageCardWidths: [CGFloat] = [
        expandedNowPageLeadingCardWidth,
        expandedNowPageStandardCardWidth,
        expandedNowPageQuickStatsCardWidth,
        expandedNowPageClipboardCardWidth,
        expandedNowPageTimerCardWidth,
        expandedNowPageSystemStatusCardWidth,
    ]
    /// 「此刻」页顶部浮层（如媒体卡片）相对内容区上缘的间距。内容区上缘与岛顶的
    /// 距离恒等于「刘海高度 + expandedContentTopInset」，浮层贴齐上缘即得同一距离；
    /// 需要额外下移或复用于其它页内浮层时，调整该值即可。
    public static let expandedNowPageAccessoryTopInset: CGFloat = 0
    /// 简约模式媒体内容的自然高度；Island 展开高度由「顶部间距 + 该高度 + 底部间距」动态构成。
    public static let expandedMinimalContentMediaHeight: CGFloat = 170
    /// 简约模式展开内容两侧的呼吸间距（同时决定 Island 展宽），避免内容被圆角裁切。
    public static let expandedMinimalContentHorizontalInset: CGFloat = 24
    /// 简约模式 Island 相对内容画布额外增加的总宽度，左右均分并保持内容居中。
    public static let expandedMinimalIslandWidthExpansion: CGFloat = 30
    /// 简约模式展开内容的底部呼吸间距（仅用于收紧高度，不随两侧间距变动）。
    public static let expandedMinimalContentBottomInset: CGFloat = 0
    /// 简约模式首个可见内容相对当前 Island 底部的顶部呼吸间距。
    public static let expandedMinimalContentTopInset: CGFloat = 2
    public static let topEdgeEffectFadeHeight: CGFloat = 6

    /// 需要覆盖最外层 11pt 高斯模糊约 3σ 的完整衰减尾部，并为 hover 横向膨胀留余量。
    public static let hoverOutset: CGFloat = 40
}
