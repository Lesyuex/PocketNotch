import AppKit
import SwiftUI

/// 纯 SwiftUI 背板渲染层。
///
/// 使用 `NotchShape.fill()` 替代原 `IslandBackgroundLayerView` 的 `CAShapeLayer`，
/// 消除 SwiftUI/AppKit 双渲染管线的帧同步问题。背板路径在每一帧按真实宽高重建，
/// 不使用 `scaleEffect` 拉伸，保持肩部圆弧为正圆。
///
/// 背板渲染层：紧凑态与展开态共用同一路径几何（展开进度 0 处与灵动态轮廓
/// 逐点一致，见 `IslandBackgroundPath.makePath`），材质因此连续。
/// 展开态可按 `backgroundStyle` 切换纯黑 / 毛玻璃；灵动态始终纯黑，
/// 与刘海、菜单栏衔接。
struct IslandShapeLayer: View {
    let state: IslandBackgroundState
    let metrics: IslandBackgroundMetrics
    let expansionProgress: CGFloat
    let compactMorphProgress: CGFloat
    var backgroundStyle: ExpandedBackgroundStyle = .standard
    /// 毛玻璃区域占岛面的比例（0 = 整岛纯黑，1 = 整岛毛玻璃）。
    var frostedRegion: CGFloat = 0.75
    /// 液态玻璃的材质变体，只对 `liquidGlass` 样式生效。
    var liquidGlassMaterial: LiquidGlassMaterial = .bubbles
    /// 液态玻璃是否被黑幕完全盖住（收起态）。盖住期间暂停系统玻璃采样。
    var glassCovered: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        switch backgroundStyle {
        case .standard:
            solidBackboard
        case .frosted:
            if reduceTransparency {
                solidBackboard
            } else {
                frostedBackboardLayer
            }
        case .liquidGlass, .simulatedLiquid:
            if reduceTransparency {
                solidBackboard
            } else {
                liquidBackboardLayer
            }
        }
    }

    private var solidBackboard: some View {
        notchShape
            .fill(PocketNotchTheme.background)
    }

    /// 毛玻璃材质**始终全不透明**，纯黑/毛玻璃的切换靠盖在其上的一层黑色遮罩
    /// 用透明度做遮挡——绝不改变材质自身的透明度。
    ///
    /// 关键：`behindWindow` 系统材质在其宿主层 opacity 处于 (0,1) 之间时，系统会
    /// 丢掉模糊、退化成一块平的深色合成，观感就是「闪成黑」。旧版直接把
    /// `frostedBackboard.opacity(reveal)` 做交叉淡化，于是每当 reveal 经过中间值
    /// （收起尾段、展开前段）就闪一下。现在材质 opacity 恒为 1，动画只作用在
    /// 顶层黑色遮罩上，模糊全程在线，不再闪。
    ///
    /// 同时不在状态边界切换视图分支：收起结束 `usesExpandedGeometry` 由真翻假那
    /// 一刻若整棵子树换成 `solidBackboard`，SwiftUI 会拆掉 `FrostedMaterialBackdrop`
    /// 触发重采样闪帧；材质视图常驻、边界只剩数值变化，取样启停交给
    /// `glassCovered`（`FrostedMaterialBackdrop(covered:)` 切 `NSVisualEffectView.state`），
    /// 纯黑收起态与紧凑胶囊档暂停背后取样，只有展开档才真正 `active` 采样。
    ///
    /// 遮罩透明度**不再读 `phaseController.observedExpansionProgress`**：那是
    /// `IslandExpansionProgressObserver` 在渲染完成后回写的**下一帧**值，比背板
    /// 形变慢一帧。改为把进度交给 `FrostedRevealOpacity`（`Animatable` 修饰器），
    /// 与 `NotchShape` 同吃一条弹簧、逐帧同相。否则 smootherstep 斜率最大的中段
    /// 每帧都差一档透明度，观感正是「背板收拢中段闪一下」。
    private var frostedBackboardLayer: some View {
        ZStack {
            frostedBackboard
            solidBackboard
                .modifier(FrostedRevealOpacity(progress: expansionProgress))
        }
    }

    /// 毛玻璃背板：底层系统材质原样保留（见 `FrostedMaterialBackdrop`，实时
    /// 背后窗口内容），其上叠 `BlackOverlay` 黑色盖板——顶部黑区整段一条平滑
    /// 曲线渐隐进玻璃；盖板高度由「毛玻璃区域」比例换算，比例变化时以
    /// easeInOut 0.25 平滑过渡。扩边让材质在岛形外多渲染一段，防止边界处糊不到
    /// 圆角外的像素。玻璃区不再叠可读性黑洗，透亮度交给系统材质本身。
    private var frostedBackboard: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                FrostedMaterialBackdrop(covered: glassCovered)
                    .padding(-IslandLayoutToken.hoverOutset)

                BlackOverlay(
                    frostedRegion: frostedRegion,
                    containerHeight: geo.size.height,
                    cornerRadius: NotchShapeSpec.cornerRadius(
                        forHeight: geo.size.height,
                        expansionProgress: expansionProgress
                    )
                )
                .animation(.easeInOut(duration: 0.25), value: frostedRegion)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .clipShape(notchShape)
    }

    /// 液态玻璃 / 仿液态背板：底层仍是「材质常驻 + 黑色底板用透明度遮挡」
    /// 的连续性策略（见 `frostedBackboardLayer` 注释）。黑色底板在收起段
    /// 重新盖回来，玻璃材质全程不透明，收起过程不闪黑。
    ///
    /// 与毛玻璃同构：顶部同样叠一层 `BlackOverlay`「毛玻璃区域」黑区，占比由
    /// `frostedRegion` 控制；区别只在材质来源（真实 Liquid Glass / 纯 SwiftUI 仿）。
    /// 紧凑段黑色由 `FrostedRevealOpacity` 负责过渡。
    private var liquidBackboardLayer: some View {
        ZStack {
            liquidBackboard
            solidBackboard
                .modifier(FrostedRevealOpacity(progress: expansionProgress))
        }
    }

    /// 液态玻璃背板材质本体：由样式选择真实 Liquid Glass 或 SwiftUI 仿液态。
    /// 两种玻璃自备可读性深洗与 rim，统一交给外层 `clipShape` 收边。
    @ViewBuilder
    private var liquidBackboard: some View {
        switch backgroundStyle {
        case .liquidGlass:
            IslandLiquidGlassBackdrop(
                shape: notchShape,
                material: liquidGlassMaterial,
                frostedRegion: frostedRegion,
                covered: glassCovered
            )
        case .simulatedLiquid:
            IslandSimulatedLiquidBackdrop(shape: notchShape, frostedRegion: frostedRegion)
        case .standard, .frosted:
            EmptyView()
        }
    }

    var notchShape: NotchShape {
        NotchShape(
            state: state,
            metrics: metrics,
            expansionProgress: expansionProgress,
            compactMorphProgress: compactMorphProgress,
            rendersInFullBounds: true
        )
    }
}

/// 黑色遮罩的遮挡强度：紧凑段（p→0）全遮——整岛纯黑、贴合刘海；展开段
/// （p→1）全露——露出毛玻璃。
///
/// 收起时黑色**跟随整段缩回进度**逐渐盖上来：`reveal = smootherstep(p)` 把
/// 过渡铺满整个 [0,1]，而不是挤在某一小段窗口里（窗口内的突变正是「割裂」感
/// 的来源）。两端一阶导为 0，所以起止都不硬切，越缩越黑、读起来像玻璃被
/// 逐渐收进刘海。
///
/// 进度直接吃背板原始进度、由 SwiftUI 逐帧插值（`animatableData`），与
/// `NotchShape` 的形变同吃一条弹簧、完全同相；不经过
/// `observedExpansionProgress` 的下一帧回写，避免中段相位差引起的闪烁。
private struct FrostedRevealOpacity: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = min(max(progress, 0), 1)
        let reveal = p * p * (3 - 2 * p)
        return content.opacity(1 - reveal)
    }
}

/// 展开进度的逐帧观察器。
///
/// `withAnimation` 中的状态只改变模型值（一次到位），视图 body 读不到插值；
/// 只有 `Animatable` 的 `animatableData` 会被逐帧插值。本观察器借助这一点
/// 把背板弹簧的真实插值进度（含过冲）逐帧回写给 `IslandPhaseController`，
/// 供回弹起跳时机与内容接力等「必须知道当前帧进度」的逻辑使用。
struct IslandExpansionProgressObserver: ViewModifier, Animatable {
    var progress: CGFloat
    let onFrame: (CGFloat) -> Void

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: progress) { _, newValue in
                onFrame(newValue)
            }
    }
}

/// 让阴影和辉光在画布边缘平滑归零，避免被硬遮罩或 NSPanel 边界裁成一条平直亮线。
/// 顶边 6pt 渐隐覆盖刘海区域；底部按 `hoverOutset` 全预算渐隐，
/// 恰好从常驻态背板底边开始，把阴影尾部线性衰减到画布底边精确归零。
/// hover 等背板下探进渐隐区的状态只会轻微减弱底部阴影，不会产生切口。
struct IslandTopEdgeEffectMask: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .white],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: IslandLayoutToken.topEdgeEffectFadeHeight)

            Color.white

            LinearGradient(
                colors: [.white, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: IslandLayoutToken.hoverOutset)
        }
    }
}

public struct CompactIslandSurface<Leading: View, Trailing: View>: View {
    public let layout: ResolvedCompactIslandLayout
    public let metrics: IslandBackgroundMetrics
    public let compactMorphProgress: CGFloat
    public let showsContent: Bool
    private let leading: Leading
    private let trailing: Trailing

    public init(
        layout: ResolvedCompactIslandLayout,
        metrics: IslandBackgroundMetrics,
        compactMorphProgress: CGFloat = 1,
        showsContent: Bool = true,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.layout = layout
        self.metrics = metrics
        self.compactMorphProgress = compactMorphProgress
        self.showsContent = showsContent
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        ZStack(alignment: .top) {
            shape
                .fill(PocketNotchTheme.background)
                .shadow(
                    color: PocketNotchTheme.islandShadowColor.opacity(shadowStyle.opacity),
                    radius: shadowStyle.radius,
                    y: shadowStyle.offsetY
                )
                .mask {
                    Rectangle()
                        .padding(.top, 1)
                }

            shape.fill(PocketNotchTheme.background)

            if showsContent {
                CompactIslandLayout(layout: layout) {
                    leading
                } right: {
                    trailing
                }
                .mask {
                    shape.fill(.white)
                }
            }
        }
        .frame(width: metrics.hiddenWidth, height: metrics.hiddenHeight, alignment: .top)
        .environment(
            \.notchHiddenIslandSize,
            CGSize(width: layout.bodyWidth, height: layout.islandHeight)
        )
        .environment(
            \.islandCompactContentSize,
            CGSize(width: layout.leadingContentWidth, height: layout.contentHeight)
        )
    }

    private var shape: NotchShape {
        NotchShape(
            state: .hidden,
            metrics: metrics,
            expansionProgress: 0,
            compactMorphProgress: compactMorphProgress,
            rendersInFullBounds: true
        )
    }

    private var shadowStyle: IslandShadowStyle {
        IslandMaterialToken.shadowStyle(
            for: .idle,
            compactMorphProgress: compactMorphProgress
        )
    }
}
