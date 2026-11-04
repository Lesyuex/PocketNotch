import AppKit
import SwiftUI

/// 液态玻璃与仿液态背板的设计参数。两者都替换展开态底板的材质——
/// 底板不再是纯黑，而是整片玻璃材质；白色内容靠一层可读性深洗保证对比。
public enum IslandLiquidGlassDesign {
    /// 真实 Liquid Glass 的白染与白描边——与锁屏组件
    /// （`NowPlayingLockScreenView` 的 `LiquidGlassBackdrop`）保持一致。
    public static let glassTintOpacity: CGFloat = 0.08
    public static let glassBorderOpacity: Double = 0.24
    /// 真实玻璃的强度（宿主层 opacity）：0 = 全透明无折射，1 = 满磨砂。
    public static let glassOpacity: Double = 1
    /// 底板上叠的可读性黑色薄洗（与毛玻璃同档，保证白字有底）。
    public static let readabilityWash: CGFloat = 0.12
    /// 玻璃 rim 描边不透明度与线宽。仿液态靠它给出玻璃轮廓。
    public static let rimOpacity: CGFloat = 0.14
    public static let rimLineWidth: CGFloat = 1
    /// 仿液态顶部高光不透明度，及其占岛身高度的比例（模拟光打在玻璃上沿的亮带）。
    public static let topSheenOpacity: CGFloat = 0.16
    public static let topSheenRegion: CGFloat = 0.38
    /// 仿液态底部内反光不透明度，及其占岛身高度的比例。
    public static let bottomReflectionOpacity: CGFloat = 0.08
    public static let bottomReflectionRegion: CGFloat = 0.30
    /// 仿液态底色微冷白着色，模拟玻璃对身后内容的轻微着色。
    public static let baseTintOpacity: CGFloat = 0.06
}

/// 让 `NotchShape` 满足 `InsettableShape`，供 `strokeBorder` 使用
/// （`NotchShape` 自身只实现 `Shape`）。
private struct NotchGlassShape: InsettableShape {
    var notch: NotchShape

    func path(in rect: CGRect) -> Path {
        notch.path(in: rect)
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        self
    }
}

/// 展开态「液态玻璃」底板：macOS 26+ 用真正的 Liquid Glass——私有
/// `NSGlassEffectView`（`windowServerAware` 直接采样 WindowServer 合成后的
/// 背后像素），旧系统回退到仿液态（与展开态低版本观感一致，不掉档）。
/// 可用性判断走 `LiquidGlassSupport`（内部读 `SystemVersionService`），设置中心
/// 可模拟旧版本强制走仿液态回退；覆盖值变化时会实时重求值。
/// 形状由调用方给定（复用刘海圆角规则），裁剪放在玻璃之后作为最终权威。
///
/// 材质与锁屏组件一致：Regular 玻璃 + 8% 白染 + 24% 白描边（见
/// `NowPlayingLockScreenView` 的 `LiquidGlassBackdrop` 参数）。
///
/// 与毛玻璃一样叠一层 `BlackOverlay`：顶部黑色区域占比由 `frostedRegion`
/// 控制（0 = 整岛纯黑、1 = 整岛玻璃），让玻璃只覆盖岛的下半段。
public struct IslandLiquidGlassBackdrop: View {
    public let shape: NotchShape
    public let material: LiquidGlassMaterial
    public let frostedRegion: CGFloat
    /// 玻璃是否被黑色背板完全盖住（收起态）。盖住期间隐藏并暂停系统玻璃采样。
    public let covered: Bool
    private let insetShape: NotchGlassShape
    @State private var materialRevision = 0

    public init(
        shape: NotchShape,
        material: LiquidGlassMaterial = .bubbles,
        frostedRegion: CGFloat = 1,
        covered: Bool = false
    ) {
        self.shape = shape
        self.material = material
        self.frostedRegion = frostedRegion
        self.covered = covered
        self.insetShape = NotchGlassShape(notch: shape)
    }

    public var body: some View {
        Group {
            if LiquidGlassSupport.isAvailable {
                GeometryReader { geo in
                    ZStack(alignment: .top) {
                        LiquidGlassBackdrop(
                            material: material,
                            cornerRadius: NotchShapeSpec.expandedBottomCornerRadius,
                            tintColor: NSColor.white.withAlphaComponent(IslandLiquidGlassDesign.glassTintOpacity),
                            opacity: IslandLiquidGlassDesign.glassOpacity,
                            covered: covered
                        )
                        BlackOverlay(
                            frostedRegion: frostedRegion,
                            containerHeight: geo.size.height,
                            cornerRadius: NotchShapeSpec.cornerRadius(
                                forHeight: geo.size.height,
                                expansionProgress: shape.expansionProgress
                            )
                        )
                        .animation(.easeInOut(duration: 0.25), value: frostedRegion)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
                .clipShape(shape)
            } else {
                IslandSimulatedLiquidBackdrop(shape: shape, frostedRegion: frostedRegion)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: SystemVersionService.overrideDidChange)) { _ in
            materialRevision += 1
        }
    }
}

/// 展开态「仿液态」底板：纯 SwiftUI 模拟的液态玻璃观感，全系统可用。
///
/// 与「毛玻璃」不同：这里**不磨砂**（磨砂归 `.frosted` 样式用），直接在透明岛
/// 面板上透出背后内容（`NotchWindow` 已是 `isOpaque = false`、`backgroundColor =
/// .clear`），模拟无折射的清澈玻璃——背后是清晰的桌面/窗口，只带轻微着色。
///
/// 结构（从底到顶）：
/// 1. 无基底——透明面板直接透出背后内容，不做任何模糊。
/// 2. 一层微冷白底色渐变，模拟玻璃对身后内容的轻微着色。
/// 3. 顶部高光亮带——光打在玻璃上沿，向下平滑渐隐。
/// 4. 底部内反光——液面下方的微弱白色反射。
/// 5. 可读性黑色薄洗，白字有底。
/// 6. 顶部 `BlackOverlay` 黑色区域，占比由 `frostedRegion` 控制（与毛玻璃同义）。
public struct IslandSimulatedLiquidBackdrop: View {
    public let shape: NotchShape
    public let frostedRegion: CGFloat
    private let insetShape: NotchGlassShape

    public init(shape: NotchShape, frostedRegion: CGFloat = 1) {
        self.shape = shape
        self.frostedRegion = frostedRegion
        self.insetShape = NotchGlassShape(notch: shape)
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(IslandLiquidGlassDesign.baseTintOpacity),
                                .clear,
                                .clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                LinearGradient(
                    colors: [
                        Color.white.opacity(IslandLiquidGlassDesign.topSheenOpacity),
                        .clear,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: geo.size.height * IslandLiquidGlassDesign.topSheenRegion)
                .mask(shape)
                .frame(maxWidth: .infinity, alignment: .top)

                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(IslandLiquidGlassDesign.bottomReflectionOpacity),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: geo.size.height * IslandLiquidGlassDesign.bottomReflectionRegion)
                .mask(shape)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                shape.fill(Color.black.opacity(IslandLiquidGlassDesign.readabilityWash))

                BlackOverlay(
                    frostedRegion: frostedRegion,
                    containerHeight: geo.size.height,
                    cornerRadius: NotchShapeSpec.cornerRadius(
                        forHeight: geo.size.height,
                        expansionProgress: shape.expansionProgress
                    )
                )
                .animation(.easeInOut(duration: 0.25), value: frostedRegion)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .clipShape(shape)
    }
}

/// 玻璃 rim 描边的顶边遮罩：顶部 `topEdgeEffectFadeHeight` 内把描边平滑隐去，
/// 避免贴顶的岛在屏幕最上沿露出一条白色顶线；侧壁与底边完整保留。
private struct GlassRimTopFade: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .white],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: IslandLayoutToken.topEdgeEffectFadeHeight)

            Color.white
        }
    }
}