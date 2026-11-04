import AppKit
import SwiftUI

public enum PocketNotchTheme {
    public static let background = Color.black
    public static let backgroundNSColor = NSColor.black
    public static let islandHoverGlow = Color(red: 0.34, green: 0.78, blue: 1)
    /// 岛体投影颜色。真实岛、预览岛共用同一真源。
    public static let islandShadowColor = Color.black
    public static let islandHoverGlowRadius: CGFloat = 5
    public static let islandHoverExpansion = IslandLayoutToken.hoverExpansion
    public static let islandHoverContentScale = IslandLayoutToken.hoverContentScale
    /// Hover 时 compact 两侧内容只随背板向下沉，始终保持 1:1 尺寸，避免封面、图标和频谱被压扁。
    public static let islandHoverSideVerticalOffset = IslandLayoutToken.hoverSideVerticalOffset
    /// 需要覆盖最外层 11pt 高斯模糊约 3σ 的完整衰减尾部，并为 hover 横向膨胀留余量。
    /// 画布过小时，非零透明度会在 NSPanel 边界被裁成一条平直亮边。
    public static let islandHoverOutset = IslandLayoutToken.hoverOutset
    public static let islandHoverAnimation = IslandAnimationToken.hover
    public static let islandCompactFontSize: CGFloat = 10.5
    public static let islandCompactMorphAnimation = IslandAnimationToken.compactMorph
    public static let islandCompactTierResizeAnimation = IslandAnimationToken.compactTierResize
    public static let islandExpandedPageResizeAnimation = IslandAnimationToken.expandedPageResize
    public static let islandCompactTierContentAnimation = IslandAnimationToken.compactTierContent
    public static let islandCompactResidentModuleExitAnimation =
        IslandAnimationToken.compactResidentModuleExit
    public static let islandCompactResidentModuleEnterAnimation =
        IslandAnimationToken.compactResidentModuleEnter
    public static let islandHoverExitAnimation = IslandAnimationToken.hoverExit
    public static let islandHoverMaterialAnimation = IslandAnimationToken.hoverMaterial
    public static let islandHoverGlowAnimation = IslandAnimationToken.hoverGlow
    public static let islandHoverColorAnimation = IslandAnimationToken.hoverColor

    /// 展开时背板膨胀与页面入场交叠进行，内容不参与宽高拉伸。
    /// 背板使用克制 Spring：先快、减速、轻微回弹、停止；顶部锚点始终固定。
    public static let islandExpandBackgroundAnimation = IslandAnimationToken.expandBackground
    public static let islandCollapseBackgroundAnimation = IslandAnimationToken.collapseBackground
    public static let islandCompactBounceAnimation = IslandAnimationToken.compactBounce
    public static let islandCompactBounceAnticipationAnimation =
        IslandAnimationToken.compactBounceAnticipation
    public static let islandCompactTierShrinkAnticipationAnimation =
        IslandAnimationToken.compactTierShrinkAnticipation
    public static let islandCompactTierShrinkBounceAnimation =
        IslandAnimationToken.compactTierShrinkBounce
    public static let islandCompactSquashWidthRatio = IslandAnimationToken.compactSquashWidthRatio
    public static let islandCompactBounceStretchGain = IslandAnimationToken.compactBounceStretchGain
    public static let islandCompactSquashHeightRatio = IslandAnimationToken.compactSquashHeightRatio
    public static let islandCompactBounceHeightStretchGain =
        IslandAnimationToken.compactBounceHeightStretchGain
    public static let islandCompactContentRetreatScale =
        IslandAnimationToken.compactContentRetreatScale
    public static let islandInteractiveSettleAnimation = IslandAnimationToken.interactiveSettle
    public static let islandCollapseMaterialAnimation = IslandAnimationToken.collapseMaterial
    public static let islandCompactContentExitAnimation = IslandAnimationToken.compactContentExit
    public static let islandCompactContentEnterAnimation = IslandAnimationToken.compactContentEnter
    public static let islandCompactModuleEnterAnimation = IslandAnimationToken.compactModuleEnter
    public static let islandCompactModuleExitAnimation = IslandAnimationToken.compactModuleExit
    public static let islandExpandedContentEnterAnimation = IslandAnimationToken.expandedContentEnter
    public static let islandScreenLockAnimation = IslandAnimationToken.screenLock
    public static let islandScreenLockPresentationAnimation =
        IslandAnimationToken.screenLockPresentation
    public static let islandScreenLockReboundAnimation =
        IslandAnimationToken.screenLockRebound
    public static let islandScreenLockOvershootScaleX =
        IslandAnimationToken.screenLockOvershootScaleX
    public static let islandReducedMotionAnimation = IslandAnimationToken.reducedMotion
    public static let islandCompactActivationDelayNanoseconds =
        IslandAnimationToken.compactActivationDelayNanoseconds

    public static let islandExpandedContentEnterProgressThreshold =
        IslandAnimationToken.expandedContentEnterProgressThreshold
    public static let islandExpandedContentEnterDeadline =
        IslandAnimationToken.expandedContentEnterDeadline
    public static let islandCompactContentRecoveryDelayNanoseconds =
        IslandAnimationToken.compactContentRecoveryDelayNanoseconds
    public static let islandCompactBounceStartDelayNanoseconds =
        IslandAnimationToken.compactBounceStartDelayNanoseconds
    public static let islandCompactBounceAnticipationDurationNanoseconds =
        IslandAnimationToken.compactBounceAnticipationDurationNanoseconds
    public static let islandCompactContentReboundRideDelayNanoseconds =
        IslandAnimationToken.compactContentReboundRideDelayNanoseconds
    public static let islandCompactContentRecoveryDurationNanoseconds =
        IslandAnimationToken.compactContentRecoveryDurationNanoseconds
    public static let islandReducedMotionDurationNanoseconds =
        IslandAnimationToken.reducedMotionDurationNanoseconds
    public static let islandCompactResidentModuleExitDurationNanoseconds =
        IslandAnimationToken.compactResidentModuleExitDurationNanoseconds

    public static let islandBackgroundMetrics = IslandBackgroundMetrics.default
    public static let collapsedSize = islandBackgroundMetrics.collapsedSize
    public static let expandedSize = islandBackgroundMetrics.expandedSize

    public static func islandCompactModuleAnimation(
        isVisible: Bool,
        reduceMotion: Bool
    ) -> Animation {
        if reduceMotion { return islandReducedMotionAnimation }
        return isVisible
            ? islandCompactModuleEnterAnimation
            : islandCompactModuleExitAnimation
    }
}

public extension View {
    /// 岛屿玻璃背板：macOS 26+ 用 Liquid Glass（`glassEffect`）实时折射身后内容，
    /// 旧系统回退到纯黑 + 细描边（与隐藏态观感一致，避免低版本掉档）。
    /// 形状由调用方给（复用刘海圆角规则），玻璃裁剪到该形状。
    @ViewBuilder
    func islandGlassBackground<S: InsettableShape>(in shape: S) -> some View {
        if #available(macOS 26.0, *), SystemVersionService.shared.isMacOS26OrLater {
            glassEffect(.regular, in: shape)
        } else {
            background(shape.fill(PocketNotchTheme.background))
                .overlay(shape.strokeBorder(.white.opacity(0.06)))
        }
    }
}
