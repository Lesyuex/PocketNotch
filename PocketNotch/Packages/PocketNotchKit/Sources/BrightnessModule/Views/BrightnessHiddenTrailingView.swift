import PocketNotchCore
import SwiftUI

/// 亮度调节的右耳内容：进度横条 + 百分比数字，与音量上岛的视觉语言保持一致。
struct BrightnessHiddenTrailingView: View {
    let viewModel: BrightnessViewModel
    @ObservedObject var settings: IslandNotificationSettings
    @Environment(\.notchHiddenIslandSize) private var hiddenIslandSize
    @Environment(\.islandCompactContentSize) private var islandCompactContentSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: BrightnessSnapshot? {
        viewModel.brightnessPresentation
    }

    var body: some View {
        Group {
            if let presentation {
                BrightnessLevelPercentage(
                    percentage: presentation.displayedPercentage,
                    height: diameter,
                    showsPercentage: settings.isBrightnessPercentageEnabled
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .compactIslandContentVisible(presentation != nil)
        .compactIslandPreferredWidth(
            presentation != nil ? CompactIslandTier.secondTierMinimumWidth : nil
        )
        .compactIslandSuppressesResidentContent(presentation != nil)
        .animation(
            PocketNotchTheme.islandCompactModuleAnimation(
                isVisible: presentation != nil,
                reduceMotion: reduceMotion
            ),
            value: viewModel.compactPresentationIdentity
        )
        .accessibilityHidden(true)
    }

    private var diameter: CGFloat {
        islandCompactContentSize?.height
            ?? CompactIslandContentSpec.resolvedContentHeight(for: hiddenIslandSize.height)
    }
}

private struct BrightnessLevelPercentage: View {
    private enum Design {
        static let barHeight: CGFloat = 4
        static let trackOpacity: CGFloat = 0.18
        static let fillOpacity: CGFloat = 0.92
        static let labelSpacing: CGFloat = 6
    }

    let percentage: Int
    let height: CGFloat
    var showsPercentage = true

    var body: some View {
        HStack(spacing: Design.labelSpacing) {
            levelBar

            if showsPercentage {
                Text(percentage, format: .number)
                    .font(.system(size: PocketNotchTheme.islandCompactFontSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(percentage)))
                    .fixedSize()
                    .animation(.easeOut(duration: 0.16), value: percentage)
            }
        }
        .frame(height: height, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("亮度 \(percentage)%")
    }

    private var levelBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(Design.trackOpacity))

                Capsule(style: .continuous)
                    .fill(.white)
                    .opacity(Design.fillOpacity)
                    .frame(
                        width: proxy.size.width
                            * CGFloat(min(max(percentage, 0), 100)) / 100
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Design.barHeight)
        .padding(.leading, 6)
        .animation(.easeOut(duration: 0.16), value: percentage)
    }
}