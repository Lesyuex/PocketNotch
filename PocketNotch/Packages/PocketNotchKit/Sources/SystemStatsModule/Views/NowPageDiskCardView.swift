import PocketNotchCore
import SwiftUI

/// 「此刻」页磁盘小卡（tile）：图标 + 名称行、可用空间大字、已用/总量 meta 行。
/// 参考设计稿：大字主读值 + 下方「已用：xx / 总量GB」次级信息。
struct NowPageDiskCardView: View {
    let viewModel: NowPageSystemStatusViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Design.tileSpacing) {
            ident

            HStack(alignment: .firstTextBaseline, spacing: Design.unitGap) {
                Text(availableDiskText)
                    .font(.system(size: Design.heroSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Design.diskColor)

                Text("GB")
                    .font(.system(size: Design.unitSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }

            HStack(spacing: Design.metaGap) {
                Text("system.diskUsed")
                    .font(.system(size: Design.metaSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))

Text(usedDiskText)
                    .font(.system(size: Design.metaSize, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.white.opacity(0.85))

                Text("/\(totalDiskText)GB")
                    .font(.system(size: Design.metaSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, Design.horizontalPadding)
        .padding(.vertical, Design.verticalPadding)
        .frame(width: Design.cardWidth, height: Design.cardHeight, alignment: .leading)
        .background(cardBackground)
        .clipShape(cardShape)
    }

    // MARK: - 身份行

    private var ident: some View {
        HStack(spacing: 5) {
            Image(systemName: "internaldrive")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            Text("system.disk")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - 数据

    /// 可用空间 GB（如 "330"）；无数据时 "--"。
    private var availableDiskText: String {
        guard let total = viewModel.snapshot?.diskTotalBytes, total > 0,
              let used = viewModel.snapshot?.diskUsedBytes else { return "--" }
        return String(format: "%.0f", Double(max(total - used, 0)) / 1_000_000_000)
    }

    /// 已用 GB（如 "182"）；无数据时 "--"。
    private var usedDiskText: String {
        guard let used = viewModel.snapshot?.diskUsedBytes else { return "--" }
        return String(format: "%.0f", Double(used) / 1_000_000_000)
    }

    /// 总量 GB（如 "512"）。
    private var totalDiskText: String {
        guard let total = viewModel.snapshot?.diskTotalBytes, total > 0 else { return "--" }
        return String(format: "%.0f", Double(total) / 1_000_000_000)
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

    // MARK: - Design

    private enum Design {
        static let cardWidth: CGFloat = 180
        static let cardHeight: CGFloat = IslandLayoutToken.expandedNowPageCardHeight
        static let cardCornerRadius: CGFloat = 10
        static let fillOpacity: Double = 0.08
        static let horizontalPadding: CGFloat = 10
        static let verticalPadding: CGFloat = 2
        static let tileSpacing: CGFloat = 2
        static let unitGap: CGFloat = 2
        static let metaGap: CGFloat = 0
        static let heroSize: CGFloat = 13
        static let unitSize: CGFloat = 8
        static let metaSize: CGFloat = 8
        static let diskColor: Color = .green.opacity(0.85)
    }
}