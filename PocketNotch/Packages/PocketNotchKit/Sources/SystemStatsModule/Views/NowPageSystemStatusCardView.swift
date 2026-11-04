import PocketNotchCore
import PocketNotchShared
import SwiftUI

/// 「此刻」页系统状态卡（系统信息卡右侧，与此前同尺寸 180×136）：
///
/// 深色液态玻璃「综合风险分」卡片——标题 + 大号总分（N/100）+ 胶囊进度条 + 三段阈值图例。
/// 分数 = CPU / GPU / RAM / 磁盘 使用率的峰值；阈值：<35 中、35–70 高、>70 甚高。
/// 无环形、无图标、无多余指标；玻璃不透明、色彩克制，行文气质贴近 macOS 原生。
struct NowPageSystemStatusCardView: View {
    let viewModel: NowPageSystemStatusViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Design.cellGap) {
                Text("system.cpuStatus")
                    .font(.system(size: Design.titleSize, weight: .medium))
                    .tracking(Design.titleTracking)
                    .foregroundStyle(.white.opacity(Design.titleOpacity))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: Design.cellGap)

                Text(temperatureText)
                    .font(.system(size: Design.tempSize, weight: .medium))
                    .tracking(Design.tempTracking)
                    .foregroundStyle(temperatureColor)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.top, 2)

            Text(scoreAttributed)
                .monospacedDigit()
                .contentTransition(.numericText(value: scoreFraction))
                .animation(
                    reduceMotion ? nil : .easeOut(duration: Design.numberRollDuration),
                    value: scoreFraction
                )
            .padding(.top, Design.scoreTopGap)

            progressBar(fraction: scoreFraction)
                .padding(.horizontal, -Design.barLengthenInset)
                .padding(.top, Design.barTopGap)

            overview
                .padding(.top, Design.overviewTopGap)
        }
        .padding(.horizontal, Design.horizontalInset)
        .padding(.top, Design.topInset)
        .padding(.bottom, Design.bottomInset)
        .frame(width: Design.cardWidth, height: Design.cardHeight, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(screenReaderLabel)
    }

    // MARK: - 分数

    /// CPU 实测使用率 0...1（无数据 0）。
    private var scoreFraction: Double {
        guard let usage = cpuUsage, usage.isFinite else { return 0 }
        return usage
    }

    private var scoreText: String {
        "\(Int((scoreFraction * 100).rounded()))"
    }

    /// 分数行用单个 AttributedString 多 run 拼接：CoreText 在同一文本布局内
    /// 按基线对齐各 run，glyph 底部自然齐平，避免 HStack 把两个 Text 当独立 view
    /// 排列时 line-height 包裹框导致的底部/基线无法同时对齐问题。
    private var scoreAttributed: AttributedString {
        var score = AttributedString(scoreText)
        score.font = .system(size: Design.scoreSize, weight: .semibold)
        score.foregroundColor = .white.opacity(Design.heroOpacity)
        score.tracking = Design.scoreTracking

        var gap = AttributedString(" ")
        gap.font = .system(size: Design.scoreDenomSize, weight: .semibold)

        var slash = AttributedString("／")
        slash.font = .system(size: Design.scoreDenomSize, weight: .semibold)
        slash.foregroundColor = .white.opacity(Design.metaOpacity)
        slash.tracking = Design.scoreDenomTracking

        var denom = AttributedString("100%")
        denom.font = .system(size: Design.scoreDenomSize, weight: .semibold)
        denom.foregroundColor = .white.opacity(Design.metaOpacity)
        denom.tracking = Design.scoreDenomTracking

        return score + gap + slash + denom
    }

    // MARK: - 进度条

    /// 单胶囊进度条：一条高斯模糊玻璃滑轨 + 前方同色填充段（圆角随占比收窄），平滑伸缩。
    private func progressBar(fraction: Double) -> some View {
        GeometryReader { proxy in
            let full = proxy.size.width
            let used = max(0, min(1, fraction)) * full
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule().fill(.white.opacity(Design.barTrackOpacity))
                    }

                RoundedRectangle(
                    cornerRadius: min(Design.barHeight / 2, used / 2),
                    style: .continuous
                )
                .fill(barFillColor(fraction))
                .frame(width: used)
                .shadow(
                    color: barFillColor(fraction).opacity(Design.barGlowOpacity),
                    radius: Design.barGlowRadius
                )
                .animation(
                    reduceMotion ? nil : .easeOut(duration: Design.barAnimationDuration),
                    value: fraction
                )
            }
        }
        .frame(height: Design.barHeight)
        .padding(.horizontal, Design.barSideInset)
    }

    /// 进度条填充色：≥80 品红（当前色），60–<80 橙黄，<60 绿；仅颜色变化。
    private func barFillColor(_ fraction: Double) -> Color {
        let percent = fraction * 100
        if percent >= 80 { return Design.barFillHigh }
        if percent >= 60 { return Design.barFillMedium }
        return Design.barFillLow
    }

    // MARK: - 底部总览

    /// 底部三指标（GPU / RAM / Disk）：纯展示、无点击。
    private var overview: some View {
        HStack(spacing: 0) {
            overviewColumn(name: "GPU", usage: gpuUsageText, alignment: .leading)

            SystemCardDivider(
                height: Design.overviewDividerHeight,
                peakOpacity: Design.overviewDividerPeakOpacity
            )
            .padding(.horizontal, Design.overviewDividerGap)

            overviewColumn(name: "RAM", usage: memoryUsageText, alignment: .center)

            SystemCardDivider(
                height: Design.overviewDividerHeight,
                peakOpacity: Design.overviewDividerPeakOpacity
            )
            .padding(.horizontal, Design.overviewDividerGap)

            overviewColumn(name: "Disk", usage: diskUsageText, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private func overviewColumn(name: String, usage: String, alignment: Alignment) -> some View {
        VStack(spacing: Design.overviewColumnSpacing) {
            Text(name)
                .font(.system(size: Design.overviewNameSize, weight: .medium))
                .tracking(Design.overviewNameTracking)
                .foregroundStyle(.white.opacity(Design.overviewNameOpacity))

            Text(usage)
                .font(.system(size: Design.overviewValueSize, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(Design.overviewValueOpacity))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    private var gpuUsageText: String { percentText(gpuUsage) }
    private var memoryUsageText: String { percentText(memoryUsage) }
    private var diskUsageText: String { percentText(diskUsage) }

    private func percentText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return "\(Int((value * 100).rounded()))%"
    }

    // MARK: - 数据

    private var temperatureText: String {
        guard let temp = viewModel.snapshot?.cpuTemperature, temp.isFinite else { return "--" }
        return "\(Int(temp.rounded()))°C"
    }

    /// 温度颜色：≥80 用进度条品红，60–<80 用进度条橙黄，<60 保持白色。
    private var temperatureColor: Color {
        guard let temp = viewModel.snapshot?.cpuTemperature, temp.isFinite else {
            return .white.opacity(Design.primaryOpacity)
        }
        if temp >= 80 { return Design.barFillHigh }
        if temp >= 60 { return Design.barFillMedium }
        return .white.opacity(Design.primaryOpacity)
    }

    private var cpuUsage: Double? {
        guard let usage = viewModel.snapshot?.cpuUsage, usage.isFinite else { return nil }
        return usage
    }

    private var gpuUsage: Double? {
        guard let usage = viewModel.snapshot?.gpuUsage, usage.isFinite else { return nil }
        return usage
    }

    private var memoryUsage: Double? {
        guard let usage = viewModel.snapshot?.memoryUsage, usage.isFinite else { return nil }
        return usage
    }

    private var diskUsage: Double? {
        guard let total = viewModel.snapshot?.diskTotalBytes, total > 0,
              let used = viewModel.snapshot?.diskUsedBytes, used >= 0
        else { return nil }
        return Double(used) / Double(total)
    }

    // MARK: - 无障碍

    private var screenReaderLabel: String {
        let cpu = cpuUsage.map { "\(Int(($0 * 100).rounded()))%" } ?? "--"
        let gpu = gpuUsage.map { "\(Int(($0 * 100).rounded()))%" } ?? "--"
        let memory = memoryUsage.map { "\(Int(($0 * 100).rounded()))%" } ?? "--"
        let disk = diskUsage.map { "\(Int(($0 * 100).rounded()))%" } ?? "--"
        return String(format: L10n.tr("system.systemStatusAccessibility"), scoreText, temperatureText, gpu, memory, disk, gpuUsageText, memoryUsageText, diskUsageText)
    }

    // MARK: - Design

    private enum Design {
        // 卡片
        static let cardWidth: CGFloat = IslandLayoutToken.expandedNowPageSystemStatusCardWidth
        static let cardHeight: CGFloat = IslandLayoutToken.expandedNowPageCardHeight
        static let horizontalInset: CGFloat = 16
        static let topInset: CGFloat = 8
        static let bottomInset: CGFloat = 10

        // 字形层级
        static let titleSize: CGFloat = 10
        static let tempSize: CGFloat = 10
        static let scoreSize: CGFloat = 13
        static let scoreDenomSize: CGFloat = 9
        static let heroOpacity: Double = 0.95
        static let primaryOpacity: Double = 0.92
        static let titleOpacity: Double = 0.70
        static let metaOpacity: Double = 0.55

        // 字距追踪：小字微加间距提升可读性，大号数字收紧。
        static let titleTracking: CGFloat = 0.4
        static let tempTracking: CGFloat = 0.2
        static let scoreTracking: CGFloat = -0.3
        static let scoreDenomTracking: CGFloat = 0.3
        static let overviewNameTracking: CGFloat = 0.6

        // 间距
        static let cellGap: CGFloat = 4
        static let scoreSlashGap: CGFloat = 4
        static let scoreTopGap: CGFloat = 11
        static let barTopGap: CGFloat = 11

        // 进度条
        static let barHeight: CGFloat = 8
        static let barBackdropHeight: CGFloat = barHeight + barSideInset * 2
        static let barSideInset: CGFloat = 3
        static let barLengthenInset: CGFloat = 2
        static let barAnimationDuration: Double = 0.5
        static let barBackdropOpacity: Double = 0.28
        static let barBackdropBorderOpacity: Double = 0.08
        static let barTrackOpacity: Double = 0.13
        static let barFillLow = Color(hex: 0x4CD964)
        static let barFillMedium = Color(hex: 0xFFB020)
        static let barFillHigh = Color(hex: 0xFF2D7F)
        static let barGlowOpacity: Double = 0.40
        static let barGlowRadius: CGFloat = 6
        static let numberRollDuration: TimeInterval = 0.35

        // 底部总览
        static let overviewTopGap: CGFloat = 19
        static let overviewNameSize: CGFloat = 9
        static let overviewValueSize: CGFloat = 13
        static let overviewColumnSpacing: CGFloat = 4
        static let overviewNameOpacity: Double = 0.32
        static let overviewValueOpacity: Double = 0.82
        static let overviewDividerHeight: CGFloat = 30
        static let overviewDividerGap: CGFloat = 8
        static let overviewDividerPeakOpacity: Double = 0.3
    }
}

/// 十六进制整数转 Color（如 0xFF2D7F → #FF2D7F）。
private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}