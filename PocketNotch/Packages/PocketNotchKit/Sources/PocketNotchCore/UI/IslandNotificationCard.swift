import SwiftUI

/// 岛下通知的共享视觉铁律：8pt 网格、统一尺寸和克制的玻璃层级。
/// 这里只承载视觉外壳；通知内容、生命周期与业务状态由各模块独立管理。
public enum IslandNotificationDesign {
    public static let grid: CGFloat = 8
    public static let cardHeight: CGFloat = 52
    public static let minCardWidth: CGFloat = 240
    public static let maxCardWidth: CGFloat = 360
    public static let outerTopInset: CGFloat = -6
    public static let outerBottomInset: CGFloat = PocketNotchTheme.islandHoverOutset
    public static let contentLeadingInset: CGFloat = 6
    public static let contentTrailingInset: CGFloat = 12
    public static let leadingVisualSize: CGFloat = 40
    public static let contentGap: CGFloat = 12
    public static let textLineGap: CGFloat = 3
    public static let cardCorner: CGFloat = 16
    public static let leadingVisualCorner: CGFloat = 9
    /// 通知面板只保留轻量外发光，避免抢过 Island 主体和通知内容。
    public static let glowOpacity: Double = 0.30

    public static let insertionAnimation = Animation.spring(response: 0.34, dampingFraction: 1)
    public static let removalAnimation = Animation.spring(response: 0.28, dampingFraction: 1)

    public static func snappedWidth(_ value: CGFloat) -> CGFloat {
        let snapped = floor(value / grid) * grid
        return clamp(snapped, minCardWidth, maxCardWidth)
    }

    public static func bannerWidth(hiddenIslandSize: CGSize, notchPhysicalWidth: CGFloat) -> CGFloat {
        let metrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: hiddenIslandSize,
            notchPhysicalWidth: notchPhysicalWidth,
            expandedModuleCount: 1
        )
        let wallInset = NotchShapeSpec.shoulderWidth(forOuterWidth: metrics.hiddenWidth)
        return snappedWidth(metrics.hiddenWidth - wallInset * 2 - grid * 2)
    }
}

private enum ParticleDissolveBackdropMotion {
    static let glowEndProgress = 0.28
    static let strokeStartProgress = 0.032
    static let strokeDurationProgress = 0.426
    static let strokeLeadProgress = 0.065
}

/// 所有模块通知共用的玻璃卡片外壳，确保音乐、专注等通知拥有一致的视觉语法。
public struct IslandNotificationCard<Content: View>: View {
    private let width: CGFloat
    private let height: CGFloat
    private let accentColor: Color
    private let glowColor: Color
    private let glowOpacity: Double
    private let tintColors: [Color]
    private let dismissalEffect: IslandNotificationDismissalEffect
    private let isDismissing: Bool
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        width: CGFloat,
        height: CGFloat = IslandNotificationDesign.cardHeight,
        accentColor: Color,
        glowColor: Color? = nil,
        glowOpacity: Double = IslandNotificationDesign.glowOpacity,
        tintColors: [Color] = [],
        dismissalEffect: IslandNotificationDismissalEffect = .standard,
        isDismissing: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.width = width
        self.height = height
        self.accentColor = accentColor
        self.glowColor = glowColor ?? accentColor
        self.glowOpacity = min(max(glowOpacity, 0), 1)
        self.tintColors = tintColors
        self.dismissalEffect = dismissalEffect
        self.isDismissing = isDismissing
        self.content = content()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: IslandNotificationDesign.cardCorner, style: .continuous)
    }

    private var resolvedTintColors: [Color] {
        tintColors.isEmpty ? [accentColor.opacity(0.12), .clear] : tintColors
    }

    public var body: some View {
        Group {
            if dismissalEffect == .particleDissolve, !reduceMotion {
                particleDissolveCard
            } else {
                standardCard
                    .islandNotificationDismissalEffect(
                        dismissalEffect,
                        isDismissing: isDismissing
                    )
            }
        }
        .frame(width: width, height: height)
    }

    private var standardCard: some View {
        ZStack {
            IslandGlowLayer(shape: shape, color: glowColor)
                .opacity(glowOpacity)

            cardSurface
            notificationContent
        }
        .frame(width: width, height: height)
    }

    private var particleDissolveCard: some View {
        IslandNotificationEffectTimeline(
            isDismissing: isDismissing,
            duration: ParticleDissolveMotion.duration
        ) { progress in
            if let progress {
                particleDissolveFrame(progress: progress)
            } else {
                standardCard
            }
        }
        .frame(width: width, height: height)
    }

    private func particleDissolveFrame(progress: Double) -> some View {
        ZStack {
            let glowOpacity = particleGlowOpacity(progress: progress)
            if glowOpacity > 0.01 {
                IslandGlowLayer(shape: shape, color: glowColor)
                    .opacity(self.glowOpacity * glowOpacity)
            }

            cardSurfaceBase
                .modifier(
                    IslandNotificationParticleDissolveModifier(
                        progress: progress,
                        style: .backdrop
                    )
                )

            if IslandNotificationParticleDustStyle.backdrop.isActive(at: progress) {
                IslandNotificationParticleDust(
                    progress: progress,
                    style: .backdrop,
                    color: accentColor
                )
            }

            let strokeOpacity = particleStrokeOpacity(progress: progress)
            if strokeOpacity > 0.01 {
                cardStroke
                    .opacity(strokeOpacity)
                    .modifier(
                        IslandNotificationParticleDissolveModifier(
                            progress: min(
                                progress + ParticleDissolveBackdropMotion.strokeLeadProgress,
                                1
                            ),
                            style: .backdrop
                        )
                    )
            }

            IslandNotificationParticleDissolveFrame(
                content: notificationContent,
                progress: progress,
                dustColor: accentColor
            )
        }
    }

    private func particleGlowOpacity(progress: Double) -> Double {
        1 - particleSmoothStep(
            min(
                max(progress / ParticleDissolveBackdropMotion.glowEndProgress, 0),
                1
            )
        )
    }

    private func particleStrokeOpacity(progress: Double) -> Double {
        1 - particleSmoothStep(
            min(
                max(
                    (progress - ParticleDissolveBackdropMotion.strokeStartProgress)
                        / ParticleDissolveBackdropMotion.strokeDurationProgress,
                    0
                ),
                1
            )
        )
    }

    private var notificationContent: some View {
        content
            .frame(width: width, height: height)
    }

    private var cardSurface: some View {
        cardSurfaceBase
            .overlay {
                cardStroke
            }
    }

    private var cardSurfaceBase: some View {
        ZStack {
            Color.clear
                .frame(width: width, height: height)
                .islandGlassBackground(in: shape)

            cardSurfaceColorLayers
        }
        .frame(width: width, height: height)
        .compositingGroup()
    }

    private var cardSurfaceColorLayers: some View {
        ZStack {
            shape.fill(.black.opacity(0.14))

            shape.fill(
                RadialGradient(
                    colors: [accentColor.opacity(0.18), .clear],
                    center: UnitPoint(x: 0.12, y: 0.5),
                    startRadius: 0,
                    endRadius: width * 0.58
                )
            )

            shape.fill(
                LinearGradient(
                    colors: resolvedTintColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            shape.fill(
                LinearGradient(
                    colors: [.white.opacity(0.055), .clear, .black.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

        }
        .frame(width: width, height: height)
    }

    private var cardStroke: some View {
        shape.strokeBorder(
            LinearGradient(
                colors: [.white.opacity(0.19), .white.opacity(0.07), .white.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 0.5
        )
    }
}

private func particleSmoothStep(_ value: Double) -> Double {
    value * value * (3 - 2 * value)
}
