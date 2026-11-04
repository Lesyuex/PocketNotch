import SwiftUI

/// 200×70 的 Liquid Glass 标准卡片：作为「此刻」页及后续模块的通用占位容器。
/// 材质与时间卡片一致（ultraThinMaterial + 细描边），可注入任意内容，
/// 不提供内容时显示统一的占位样式。
public struct LiquidGlassStandardCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(
                width: LiquidGlassStandardCardDesign.cardWidth,
                height: LiquidGlassStandardCardDesign.cardHeight
            )
            .background(cardBackground)
            .clipShape(cardShape)
            .overlay {
                cardShape.strokeBorder(
                    .white.opacity(LiquidGlassStandardCardDesign.cardBorderOpacity),
                    lineWidth: 0.8
                )
            }
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    private var cardBackground: some View {
        ZStack {
            if #available(macOS 13.0, *) {
                RoundedRectangle(cornerRadius: LiquidGlassStandardCardDesign.cardCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(LiquidGlassStandardCardDesign.glassOpacity)
            } else {
                RoundedRectangle(cornerRadius: LiquidGlassStandardCardDesign.cardCornerRadius, style: .continuous)
                    .fill(.white.opacity(0.08))
            }
        }
        .allowsHitTesting(false)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LiquidGlassStandardCardDesign.cardCornerRadius, style: .continuous)
    }
}

/// 标准卡片的设计尺寸与样式参数（供内容对齐复用）。
public enum LiquidGlassStandardCardDesign {
    public static let cardWidth: CGFloat = 132
    public static let cardHeight: CGFloat = 152
    public static let cardCornerRadius: CGFloat = 16
    public static let cardBorderOpacity: CGFloat = 0.20
    public static let glassOpacity: Double = 0.72
}

/// 标准卡片的默认占位内容：预留位置提示。
public struct LiquidGlassStandardCardPlaceholder: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.30))

            Text("common.placeholderContent")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.34))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension LiquidGlassStandardCard where Content == LiquidGlassStandardCardPlaceholder {
    public init(_ placeholder: LiquidGlassStandardCardPlaceholder = LiquidGlassStandardCardPlaceholder()) {
        self.content = placeholder
    }
}