import SwiftUI

/// 「此刻」系统卡片共享视觉样式：文字多级不透明度 + 分类点缀色。
/// 卡片间距/字号各自归档在自己的 Design 中，此处只统一「色彩与文字」这类跨卡一致项。
enum NowCardStyle {
    static let fg = Color.white.opacity(0.9)
    static let muted = Color.white.opacity(0.55)
    static let meta = Color.white.opacity(0.45)

    static let cpuColor = Color.yellow.opacity(0.9)
    static let gpuColor = Color.purple.opacity(0.85)
    static let memoryColor = Color.cyan.opacity(0.85)
    static let diskColor = Color.green.opacity(0.85)
    static let tempColor = Color.orange.opacity(0.85)
}

/// 系统卡片第一行（卡 1 网格卡与卡 2 纵向卡共用）：
/// gauge 运行图标 + 「机型 █ 尺寸 █ 芯片简写」渐变分割，无多余状态字样。
struct NowSystemStatusHeader: View {
    let viewModel: NowPageSystemStatusViewModel
    /// 是否把芯片简写并入本行；false 时仅「机型 █ 尺寸」，芯片由卡片另行成行。
    var showChip: Bool = true

    private var segments: [String] {
        let identity = viewModel.macIdentity
        var result = [
            identity.modelName ?? "Mac",
            identity.screenSize,
        ].compactMap { $0 }
        if showChip, let chipModel = identity.chipModel {
            result.append(chipModel)
        }
        return result
    }

    /// gauge 图标档位：0% 正常、50% 有压力、100% 负载；无数据时取 0%。
    private var statusSymbolName: String {
        guard viewModel.snapshot != nil else { return "gauge.with.dots.needle.bottom.0percent" }
        switch viewModel.healthScore {
        case 85...: return "gauge.with.dots.needle.bottom.0percent"
        case ..<55: return "gauge.with.dots.needle.bottom.100percent"
        default: return "gauge.with.dots.needle.bottom.50percent"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 5) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        SystemCardDivider()
                    }

                    Text(segment)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NowCardStyle.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: statusSymbolName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NowCardStyle.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 16)
    }
}

/// 按按时间序数值（0...1）绘制的平滑曲线：midpoint quad 连接，天然无拐点抖动；
/// 用于内存使用率趋势。
struct UsageSparkline: Shape {
    /// 归一化采样点（0...1，最多 30）；不足 2 点时绘制为空。
    let points: [Double]

    func path(in rect: CGRect) -> Path {
        guard points.count > 1 else { return Path() }
        var path = Path()
        let stepX = rect.width / CGFloat(points.count - 1)
        func y(_ value: Double) -> CGFloat {
            rect.maxY - min(max(CGFloat(value), 0), 1) * rect.height
        }
        path.move(to: CGPoint(x: 0, y: y(points[0])))
        for index in 1..<points.count {
            let previous = CGPoint(x: stepX * CGFloat(index - 1), y: y(points[index - 1]))
            let current = CGPoint(x: stepX * CGFloat(index), y: y(points[index]))
            path.addQuadCurve(
                to: CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2),
                control: previous
            )
        }
        path.addLine(to: CGPoint(x: rect.width, y: y(points.last ?? 0)))
        return path
    }
}

/// 段间渐变分割线：上下渐隐、中间实体，高与所在行文字一致。
struct SystemCardDivider: View {
    var height: CGFloat = 8
    /// 渐变最亮段的不透明度：默认与共享 muted 一致；高版分割线可传入更低值避免中部过亮。
    var peakOpacity: Double = 0.55

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [.clear, .white.opacity(peakOpacity), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1, height: height)
    }
}

/// 自绘 GPU 图标：外框 + 引脚线 + 内芯 + 圆点，描边风格贴合参考稿 SVG。
struct GpuGlyphIcon: View {
    var color: Color = Color.white.opacity(0.45)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                GpuGlyphOutline()
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 1.55, lineCap: .round, lineJoin: .round)
                    )
                GpuGlyphDot()
                    .fill(color)
            }
        }
    }
}

struct GpuGlyphOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        var path = Path()

        // 外框 rect(x:4, y:6, width:16, height:12, rx:2)
        path.addRoundedRect(
            in: CGRect(x: 4 * scale, y: 6 * scale, width: 16 * scale, height: 12 * scale),
            cornerSize: CGSize(width: 2 * scale, height: 2 * scale),
            style: .continuous
        )

        // 顶部横线 M8 10h3
        path.move(to: CGPoint(x: 8 * scale, y: 10 * scale))
        path.addLine(to: CGPoint(x: 11 * scale, y: 10 * scale))

        // 内芯 rect(x:8, y:12, width:8, height:6, rx:1)
        path.addRoundedRect(
            in: CGRect(x: 8 * scale, y: 12 * scale, width: 8 * scale, height: 6 * scale),
            cornerSize: CGSize(width: 1 * scale, height: 1 * scale),
            style: .continuous
        )

        return path
    }
}

struct GpuGlyphDot: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        return Path(
            ellipseIn: CGRect(
                x: (12 - 1.4) * scale,
                y: (15 - 1.4) * scale,
                width: 2.8 * scale,
                height: 2.8 * scale
            )
        )
    }
}