import SwiftUI
import PocketNotchCore

private enum PowerTrailingDesign {
    static let minimumPercentageWidth: CGFloat = 27
    static let indicatorSpacing: CGFloat = 4
    static let batteryWidth: CGFloat = 22.5
    static let batteryHeight: CGFloat = 10
}

struct PowerHiddenTrailingView: View {
    let viewModel: SystemStatsViewModel
    @Environment(\.notchHiddenIslandSize) private var hiddenIslandSize
    @Environment(\.islandCompactContentSize) private var islandCompactContentSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var diameter: CGFloat {
        islandCompactContentSize?.height
            ?? CompactIslandContentSpec.resolvedContentHeight(for: hiddenIslandSize.height)
    }

    private var percentageWidth: CGFloat {
        max(diameter, PowerTrailingDesign.minimumPercentageWidth)
    }

    private var contentWidth: CGFloat {
        percentageWidth
            + PowerTrailingDesign.indicatorSpacing
            + PowerTrailingDesign.batteryWidth
    }

    private var presentation: PowerPresentation? {
        viewModel.powerPresentation
    }

    var body: some View {
        Group {
            if let presentation {
                PowerBatteryIndicator(
                    presentation: presentation,
                    percentageWidth: percentageWidth,
                    height: diameter
                )
                .frame(width: contentWidth, height: diameter, alignment: .trailing)
            } else {
                Color.clear
            }
        }
        .frame(width: contentWidth, height: diameter, alignment: .trailing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .animation(
            PocketNotchTheme.islandCompactModuleAnimation(
                isVisible: presentation != nil,
                reduceMotion: reduceMotion
            ),
            value: viewModel.compactPresentationIdentity
        )
        .compactIslandPreferredWidth(
            presentation != nil ? CompactIslandTier.secondTierMinimumWidth : nil
        )
        .compactIslandSuppressesResidentContent(presentation != nil)
        .accessibilityHidden(true)
    }
}

private struct PowerBatteryIndicator: View {
    let presentation: PowerPresentation
    let percentageWidth: CGFloat
    let height: CGFloat

    @ViewBuilder
    var body: some View {
        HStack(spacing: PowerTrailingDesign.indicatorSpacing) {
            CompactPercentageLabel(
                percentage: presentation.battery.percentage,
                width: percentageWidth,
                height: height,
                color: gaugeColor,
                accessibilityText: "电量 \(presentation.battery.percentage)%",
                percentSignOpacity: 1
            )

            BatteryGauge(
                level: presentation.battery.level,
                width: PowerTrailingDesign.batteryWidth,
                height: PowerTrailingDesign.batteryHeight,
                fillColor: gaugeColor
            )
            .accessibilityHidden(true)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: height)
    }

    private var gaugeColor: Color {
        presentation.kind == .disconnected ? .white : .green
    }
}
