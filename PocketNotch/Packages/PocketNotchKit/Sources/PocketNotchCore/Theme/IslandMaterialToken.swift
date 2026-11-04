import CoreGraphics

/// Island 阴影参数。材质层随状态连续变化，View 层只负责应用。
public struct IslandShadowStyle: Equatable, Sendable {
    public let opacity: CGFloat
    public let radius: CGFloat
    public let offsetY: CGFloat

    public init(opacity: CGFloat, radius: CGFloat, offsetY: CGFloat) {
        self.opacity = opacity
        self.radius = radius
        self.offsetY = offsetY
    }
}

/// Island 材质参数的唯一入口。
public enum IslandMaterialToken {
    public static func glowOpacity(for phase: IslandPresentationPhase) -> CGFloat {
        switch phase {
        case .hidden, .idle:
            return 0
        case .hover:
            return 0.2
        case .expanding, .expanded, .interactive, .collapsing:
            return 0
        }
    }

    /// 环境层阴影：叠加在主层之下，用更大半径、更低透明度的第二层高斯
    /// 平滑单层大半径阴影在 8-bit 帧缓冲上的色带与「一刀切」轮廓。
    /// 所有相位的 radius+offsetY 必须留在 `IslandLayoutToken.hoverOutset`
    /// 画布预算内，否则会在 NSPanel 边界被裁成平直亮边。
    ///
    /// 岛体只在展开态投影：收起 / 灵动态紧贴屏幕顶边或刘海，投影既不可见也
    /// 无分层意义，故一律归零；只有展开成悬浮大面板时才需要阴影与壁纸分层。
    /// 相位切换时的淡入淡出由调用方的 `.animation(_:value: phase)` 负责。
    public static func ambientShadowStyle(
        for phase: IslandPresentationPhase,
        compactMorphProgress: CGFloat,
        isFloatingIsland: Bool = false
    ) -> IslandShadowStyle {
        switch phase {
        case .hidden, .idle, .hover, .collapsing:
            return IslandShadowStyle(opacity: 0, radius: 0, offsetY: 0)
        case .expanding:
            return IslandShadowStyle(opacity: 0.19, radius: 30, offsetY: 6)
        case .expanded:
            return IslandShadowStyle(opacity: 0.17, radius: 28, offsetY: 6)
        case .interactive:
            return IslandShadowStyle(opacity: 0.15, radius: 26, offsetY: 6)
        }
    }

    public static func shadowStyle(
        for phase: IslandPresentationPhase,
        compactMorphProgress: CGFloat,
        isFloatingIsland: Bool = false
    ) -> IslandShadowStyle {
        switch phase {
        case .hidden, .idle, .hover, .collapsing:
            return IslandShadowStyle(opacity: 0, radius: 0, offsetY: 0)
        case .expanding:
            return IslandShadowStyle(opacity: 0.46, radius: 25, offsetY: 8)
        case .expanded:
            return IslandShadowStyle(opacity: 0.42, radius: 22, offsetY: 8)
        case .interactive:
            return IslandShadowStyle(opacity: 0.38, radius: 20, offsetY: 8)
        }
    }
}
