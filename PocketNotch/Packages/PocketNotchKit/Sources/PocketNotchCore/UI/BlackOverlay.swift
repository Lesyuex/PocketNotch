import Foundation
import SwiftUI

/// 黑色盖板：让刘海顶部保持接近纯黑，再经底部一段平滑 Alpha 渐隐自然融入
/// 下方系统毛玻璃。黑色本身保持纯黑、不参与颜色渐变——透明度完全由
/// `BlackOverlayMask` 控制；不加描边、分割线与阴影等任何 UI 边界，容器形状
/// 由外层 `clipShape` 与自身 `cornerRadius` 自裁共同约束。
///
/// 视觉结构（盖板总占位 = height + fadeLength）：
/// ```
/// 0
/// ┌──────────────┐
/// │  黑色实体区    │  height（纯黑，0.96）
/// ├──────────────┤
/// │  Alpha 渐隐    │  fadeLength（1.0 → 0.0）
/// └──────────────┘
///      毛玻璃
/// ```
public struct BlackOverlay: View {
    /// 黑色实体区高度（不含底部渐隐区）。
    public let height: CGFloat
    /// 底部渐隐区长度，跟随实体区底部移动。
    public let fadeLength: CGFloat
    /// 盖板黑色不透明度。
    public let opacity: CGFloat
    /// 自裁圆角；容器自身的 `clipShape` 仍是最终形状约束。
    public let cornerRadius: CGFloat

    /// 默认渐隐长度（18–28pt 区间上限：渐隐越短，玻璃越像「突然亮出来」，
    /// 短于此范围会读出一条水平边界）。
    public static let defaultFadeLength: CGFloat = 28
    /// 盖板默认不透明度（接近纯黑）。
    public static let defaultOpacity: CGFloat = 0.96

    public init(
        height: CGFloat,
        fadeLength: CGFloat = BlackOverlay.defaultFadeLength,
        opacity: CGFloat = BlackOverlay.defaultOpacity,
        cornerRadius: CGFloat
    ) {
        self.height = height
        self.fadeLength = fadeLength
        self.opacity = opacity
        self.cornerRadius = cornerRadius
    }

    /// 由「毛玻璃区域」比例构造盖板：0% = 整岛纯黑（无渐隐、全不透明），
    /// 100% = 整岛毛玻璃（无盖板）。盖板总占位等于黑区高度
    /// `(1 - region) * containerHeight`。
    ///
    /// 黑区整段用**单一连续曲线**渐隐（`height = 0`，无「实体区 + 渐隐区」的
    /// 内部接缝）。接缝是割裂感的根源：两块区域相接处哪怕 C1 连续，曲率仍会
    /// 跳变，人眼会把这条曲率突变读成一条硬边（Mach band）。整段一条 C2 曲线
    /// 后，顶部（刘海下）仍是纯黑、底部以零斜率并进玻璃，中间无任何接点。
    public init(frostedRegion: CGFloat, containerHeight: CGFloat, cornerRadius: CGFloat) {
        let region = min(max(frostedRegion, 0), 1)
        if region <= 0.001 {
            self.init(height: containerHeight, fadeLength: 0, opacity: 1, cornerRadius: cornerRadius)
        } else if region >= 0.999 {
            self.init(height: 0, fadeLength: 0, cornerRadius: cornerRadius)
        } else {
            let total = containerHeight * (1 - region)
            self.init(height: 0, fadeLength: total, cornerRadius: cornerRadius)
        }
    }

    public var body: some View {
        Color.black
            .opacity(opacity)
            .frame(height: height + fadeLength)
            .mask {
                BlackOverlayMask(height: height, fadeLength: fadeLength)
            }
            .clipShape(
                // 顶角必须留给容器的 NotchShape 裁切：刘海顶角是内凹肩部
                // （顶边全宽、向内收进侧壁），凸圆角矩形会在黑色顶角切出
                // 玻璃月牙与硬弧边。底部圆角只在盖板触底（毛玻璃区域 0%）
                // 时参与，方向安全——外层 clipShape 仍是最终约束。
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: cornerRadius,
                    bottomTrailingRadius: cornerRadius,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
    }
}

/// `BlackOverlay` 的垂直 Alpha 遮罩：整段用 **smootherstep**（`6t⁵−15t⁴+10t³`）
/// 的反相曲线——顶部 alpha=1、底部 alpha=0，两端一阶与二阶导都为 0，因此与
/// 上方刘海区、下方玻璃区的曲率完全连续，不产生 Mach band 硬边。曲线用高密度
/// 采样构造 `LinearGradient`，GPU 渲染，逐帧改高（展开动画）零逐像素开销。
///
/// 反相后对 smootherstep 再取 `curveSharpness` 次幂做陡化：指数 > 1 时黑区在
/// 顶部保持更久、玻璃更快收窄，小区域才读得出「小」；指数保持端点零导数，
/// 仍是单条连续曲线，不引入接缝。
public struct BlackOverlayMask: View {
    /// 黑色实体区高度（与 `BlackOverlay.height` 对应）。
    public let height: CGFloat
    /// 底部渐隐区长度。
    public let fadeLength: CGFloat

    public init(height: CGFloat, fadeLength: CGFloat) {
        self.height = height
        self.fadeLength = fadeLength
    }

    /// 渐隐曲线采样数：足够密以让 GPU 插值看不出折线。
    private static let sampleCount = 64
    /// 曲线陡度指数：黑区上部保持时长（1 = 原始 smootherstep，越大黑区越实）。
    private static let curveSharpness: CGFloat = 10

    public var body: some View {
        ZStack(alignment: .top) {
            if height > 0 {
                Color.white.frame(height: height)
            }
            if fadeLength > 0 {
                LinearGradient(
                    stops: Self.stops,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .offset(y: height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private static var stops: [Gradient.Stop] {
        (0...sampleCount).map { i in
            let t = CGFloat(i) / CGFloat(sampleCount)
            let smoother = t * t * t * (t * (t * 6 - 15) + 10)
            let shaped = pow(smoother, curveSharpness)
            return Gradient.Stop(color: Color.white.opacity(1 - shaped), location: t)
        }
    }
}
