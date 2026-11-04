import SwiftUI

/// Island 与通知面板共用的三层外发光。
/// 将完整形状放在实体背板后方，让实体自然遮住内侧光线，避免使用遮罩裁断模糊尾部。
public struct IslandGlowLayer<GlowShape: Shape>: View {
    private let shape: GlowShape
    private let color: Color

    public init(shape: GlowShape, color: Color) {
        self.shape = shape
        self.color = color
    }

    public var body: some View {
        ZStack {
            shape
                .fill(color.opacity(0.95))
                .blur(radius: PocketNotchTheme.islandHoverGlowRadius * 0.55)

            shape
                .fill(color.opacity(0.68))
                .blur(radius: PocketNotchTheme.islandHoverGlowRadius * 1.4)

            shape
                .fill(color.opacity(0.24))
                .blur(radius: PocketNotchTheme.islandHoverGlowRadius * 2.2)
        }
        .allowsHitTesting(false)
    }
}
