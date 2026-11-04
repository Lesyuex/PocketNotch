import PocketNotchCore
import SwiftUI

/// 「此刻」页 CPU + 内存 双栏卡（dual）：左右两列相同构型，由竖向渐变分割线衔接。
/// CPU 列为顶部标签 + 温度大字（左）+ 使用率大字（右）；内存列为标签 + 已用/总量大字。
/// 参考设计稿：eyebrow 小字标签 + hero 级大读值，紧凑布局。
struct NowPageCPUAndMemoryCardView: View {
    let viewModel: NowPageSystemStatusViewModel

    var body: some View {
        HStack(spacing: 0) {
            cpuColumn
                .frame(maxWidth: .infinity)

            Design.columnDivider

            memoryColumn
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Design.horizontalPadding)
        .frame(width: Design.cardWidth, height: Design.cardHeight)
        .background(cardBackground)
        .clipShape(cardShape)
    }

    // MARK: - CPU 列

    private var cpuColumn: some View {
        VStack(alignment: .leading, spacing: Design.columnSpacing) {
            eyebrow(label: "CPU", systemImage: "cpu")

            HStack(alignment: .firstTextBaseline, spacing: Design.columnGap) {
                tempHero
                Spacer(minLength: Design.columnGap)
                usageHero
            }
        }
    }

    /// CPU 温度大字：数值随温度着色（白/黄/红），单位紧跟弱化。
    private var tempHero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(cpuTempNumber)
                .font(.system(size: Design.valueSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(cpuTempColor)

            Text("°C")
                .font(.system(size: Design.unitSize, weight: .medium, design: .rounded))
                .foregroundStyle(cpuTempColor.opacity(0.45))
        }
    }

    /// CPU 使用率大字（右侧），百分号紧跟弱化。
    private var usageHero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(cpuUsagePercentText)
                .font(.system(size: Design.valueSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.95))

            Text("%")
                .font(.system(size: Design.unitSize, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    // MARK: - 内存列

    private var memoryColumn: some View {
        VStack(alignment: .leading, spacing: Design.columnSpacing) {
            eyebrow(label: "RAM", systemImage: "memorychip")

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(usedMemoryText)
                    .font(.system(size: Design.heroSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.cyan.opacity(0.85))

                Text("/\(totalMemoryText)GB")
                    .font(.system(size: Design.metaSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 公共子视图

    /// 标签行：小图标 + 文字（与磁盘等身份行同构，不套用设计稿字体）。
    private func eyebrow(label: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: Design.eyebrowIconSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))

            Text(label)
                .font(.system(size: Design.eyebrowSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
            .fill(.white.opacity(Design.fillOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
    }

    private var cardShape: some Shape {
        RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
    }

    // MARK: - 数据

    /// CPU 温度整数（如 "80"）；无数据或不合法时 "--"。
    private var cpuTempNumber: String {
        guard let temperature = viewModel.snapshot?.cpuTemperature, temperature.isFinite else { return "--" }
        return "\(Int(temperature.rounded()))"
    }

    /// CPU 温度着色：未达 60 白、60 起警告黄、80 起危险红。
    private var cpuTempColor: Color {
        color(forPercent: viewModel.snapshot?.cpuTemperature)
    }

    /// CPU 使用率百分比纯数字（如 "15"）。
    private var cpuUsagePercentText: String {
        guard let usage = viewModel.snapshot?.cpuUsage, usage.isFinite else { return "--" }
        return "\(Int((usage * 100).rounded()))"
    }

    /// 内存已用 GB（如 "5.32"）；无数据时 "--"。
    private var usedMemoryText: String {
        guard let usage = viewModel.snapshot?.memoryUsage, usage.isFinite else { return "--" }
        return String(format: "%.2f", usage * Self.totalGB)
    }

    /// 内存总量 GB（如 "32"）。
    private var totalMemoryText: String {
        String(format: "%.0f", Self.totalGB)
    }

    private static let totalGB: Double = Double(ProcessInfo.processInfo.physicalMemory) / 1_000_000_000

    /// 按区间取状态色：<60 白、60...<80 警告黄、≥80 危险红。
    private func color(forPercent value: Double?) -> Color {
        guard let value, value.isFinite else { return .white.opacity(0.95) }
        switch value {
        case ..<60: return .white.opacity(0.95)
        case ..<80: return .yellow
        default: return .red
        }
    }

    // MARK: - Design

    private enum Design {
        static let cardWidth: CGFloat = 180
        static let cardHeight: CGFloat = IslandLayoutToken.expandedNowPageCardHeight
        static let cardCornerRadius: CGFloat = 10
        static let fillOpacity: Double = 0.08
        static let horizontalPadding: CGFloat = 10
        static let columnGap: CGFloat = 7
        static let columnSpacing: CGFloat = 5
        static let heroSize: CGFloat = 13
        static let valueSize: CGFloat = 12
        static let unitSize: CGFloat = 9
        static let metaSize: CGFloat = 9
        static let eyebrowIconSize: CGFloat = 9
        static let eyebrowSize: CGFloat = 8
        static let columnDivider: some View = Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(0),
                        .white.opacity(0.3),
                        .white.opacity(0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1, height: 38)
            .padding(.horizontal, 4)
    }
}