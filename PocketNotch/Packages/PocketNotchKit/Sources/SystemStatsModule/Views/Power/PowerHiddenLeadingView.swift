import PocketNotchCore
import SwiftUI

struct PowerHiddenLeadingView: View {
    let viewModel: SystemStatsViewModel
    @Environment(\.notchHiddenIslandSize) private var hiddenIslandSize
    @Environment(\.islandCompactContentSize) private var islandCompactContentSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var iconHeight: CGFloat {
        islandCompactContentSize?.height
            ?? CompactIslandContentSpec.resolvedContentHeight(for: hiddenIslandSize.height)
    }

    private var contentWidth: CGFloat {
        islandCompactContentSize?.width
            ?? CompactIslandContentSpec.leadingContentWidth(forHeight: hiddenIslandSize.height)
    }

    private var presentation: PowerPresentation? {
        viewModel.powerPresentation
    }

    var body: some View {
        Group {
            if let presentation {
                PowerLeadingIndicator(
                    presentation: presentation,
                    width: contentWidth,
                    height: iconHeight
                )
                .frame(width: contentWidth, height: iconHeight, alignment: .leading)
            } else {
                Color.clear
            }
        }
        .frame(width: contentWidth, height: iconHeight, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .compactIslandContentVisible(presentation != nil)
        .islandGlowColor(presentation.map(glowColor))
        .animation(
            PocketNotchTheme.islandCompactModuleAnimation(
                isVisible: presentation != nil,
                reduceMotion: reduceMotion
            ),
            value: viewModel.compactPresentationIdentity
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func glowColor(for presentation: PowerPresentation) -> Color {
        switch presentation.kind {
        case .connected, .charging, .charged: .green
        case .disconnected: presentation.battery.levelBand.compactColor
        }
    }

    private var accessibilityText: String {
        guard let presentation else { return "" }
        return "\(presentation.compactStatusText)，电量 \(presentation.battery.percentage)%"
    }
}

private struct PowerLeadingIndicator: View {
    let presentation: PowerPresentation
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Text(presentation.compactStatusText)
            .font(.system(
                size: PocketNotchTheme.islandCompactFontSize,
                weight: .semibold,
                design: .rounded
            ))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: width, height: height, alignment: .leading)
    }
}

private extension PowerPresentation {
    var compactStatusText: String {
        switch kind {
        case .connected, .charging: "正在充电"
        case .charged: "充电完成"
        case .disconnected: "充电断开"
        }
    }
}

private extension BatteryLevelBand {
    var compactColor: Color {
        switch self {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }
}

struct BatteryGauge: View {
    let level: Double
    let width: CGFloat
    let height: CGFloat
    let fillColor: Color
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: terminalGap) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(batteryBackgroundColor)

                if fillWidth > 0 {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fillColor)
                        .frame(width: fillWidth, height: fillHeight)
                }
            }
            .frame(width: bodyWidth, height: height)

            RoundedRectangle(cornerRadius: terminalWidth / 2, style: .continuous)
                .fill(batteryBackgroundColor)
                .frame(width: terminalWidth, height: terminalHeight)
        }
        .frame(width: width, height: height)
    }

    private var bodyWidth: CGFloat {
        max(width - terminalGap - terminalWidth, 1)
    }

    private var terminalWidth: CGFloat {
        pixelAligned(width * 0.065)
    }

    private var terminalHeight: CGFloat {
        pixelAligned(height * 0.4)
    }

    private var terminalGap: CGFloat {
        1 / resolvedDisplayScale
    }

    private var batteryBackgroundColor: Color {
        fillColor.opacity(0.25)
    }

    private var cornerRadius: CGFloat {
        pixelAligned(height * 0.3)
    }

    private var fillWidth: CGFloat {
        bodyWidth * CGFloat(min(max(level, 0), 1))
    }

    private var fillHeight: CGFloat {
        height
    }

    private var resolvedDisplayScale: CGFloat {
        max(displayScale, 1)
    }

    private func pixelAligned(_ value: CGFloat) -> CGFloat {
        (value * resolvedDisplayScale).rounded() / resolvedDisplayScale
    }
}
