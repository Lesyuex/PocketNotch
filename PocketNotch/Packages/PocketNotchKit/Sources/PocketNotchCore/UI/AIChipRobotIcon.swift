import SwiftUI

/// AI 芯片图标，按 48×48 SVG 路径绘制。
///
/// 横向芯片：主体 + 左侧凸块 + 双眼 + 底部四引脚，全部用 stroke 渲染，
/// 与「Ai-Chip–Streamline-Micro」SVG 几何一致。
public struct AIChipRobotIcon: View {
    public init() {}

    public var body: some View {
        AIChipRobotIconOutline()
            .stroke(
                style: StrokeStyle(
                    lineWidth: 1.38,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .aspectRatio(1, contentMode: .fit)
    }
}

private struct AIChipRobotIconOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 10
        let offsetX = rect.midX - 5 * scale
        let offsetY = rect.midY - 5 * scale

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: offsetX + x * scale, y: offsetY + y * scale)
        }

        var path = Path()

        // Main body — wide rectangle with a left tab,
        // closed from (8.0865, 4.6922) back to start.
        path.move(to: point(8.0865, 4.6922))
        path.addLine(to: point(9.2845, 4.6922))
        path.addLine(to: point(9.2845, 5.6905))
        path.addLine(to: point(8.0865, 5.6905))
        path.addLine(to: point(8.0865, 6.4892))
        path.addLine(to: point(1.4975, 6.4892))
        path.addLine(to: point(1.4975, 5.6905))
        path.addLine(to: point(0.2995, 5.6905))
        path.addLine(to: point(0.2995, 4.6922))
        path.addLine(to: point(1.4975, 4.6922))
        path.addLine(to: point(1.4975, 2.2962))
        path.addLine(to: point(8.0865, 2.2962))
        path.closeSubpath()

        // Eyes — two short vertical strokes.
        path.move(to: point(2.8952, 3.4942))
        path.addLine(to: point(2.8952, 4.0932))
        path.move(to: point(6.6888, 3.4942))
        path.addLine(to: point(6.6888, 4.0932))

        // Bottom pins.
        for x in [2.2962, 3.4942, 6.0898, 7.2878] {
            path.move(to: point(x, 6.589))
            path.addLine(to: point(x, 7.6872))
        }

        return path
    }
}