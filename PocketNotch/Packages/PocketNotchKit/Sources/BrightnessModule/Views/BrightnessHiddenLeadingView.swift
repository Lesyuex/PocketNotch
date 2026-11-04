import PocketNotchCore
import SwiftUI

/// 亮度调节的左耳内容：太阳图标 + 二档时补充「亮度」字样，与音量上岛的视觉语言保持一致。
struct BrightnessHiddenLeadingView: View {
    let viewModel: BrightnessViewModel
    @Environment(\.notchHiddenIslandSize) private var hiddenIslandSize
    @Environment(\.islandCompactContentSize) private var islandCompactContentSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: BrightnessSnapshot? {
        viewModel.brightnessPresentation
    }

    private var coverSize: CGFloat {
        islandCompactContentSize?.height
            ?? CompactIslandContentSpec.resolvedContentHeight(for: hiddenIslandSize.height)
    }

    private var contentWidth: CGFloat {
        islandCompactContentSize?.width
            ?? CompactIslandContentSpec.leadingContentWidth(forHeight: hiddenIslandSize.height)
    }

    private var showsLabel: Bool {
        presentation != nil
            && CompactIslandTier.resolved(
                forWidth: hiddenIslandSize.width,
                stockDisplayActive: false
            ) == .second
    }

    var body: some View {
        Group {
            if let presentation {
                BrightnessLevelIcon(
                    systemName: symbolName(for: presentation.displayedPercentage),
                    percentage: presentation.displayedPercentage,
                    diameter: coverSize,
                    showsLabel: showsLabel
                )
            } else {
                Color.clear.frame(width: coverSize, height: coverSize)
            }
        }
        .frame(
            width: showsLabel ? nil : contentWidth,
            height: coverSize,
            alignment: .leading
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .islandGlowColor(presentation != nil ? .white : nil)
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

    private func symbolName(for percentage: Int) -> String {
        percentage == 0 ? "sun.min.fill" : "sun.max.fill"
    }
}

private struct BrightnessLevelIcon: View {
    private enum Design {
        static let labelSpacing: CGFloat = 8
        static let symbolWidthRatio: CGFloat = 0.72
        static let symbolSizeRatio: CGFloat = 0.54
    }

    let systemName: String
    let percentage: Int
    let diameter: CGFloat
    var showsLabel = false

    var body: some View {
        HStack(spacing: showsLabel ? Design.labelSpacing : 0) {
            symbol

            if showsLabel {
                Text("亮度")
                    .font(.system(size: PocketNotchTheme.islandCompactFontSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize()
            }
        }
        .frame(height: diameter, alignment: .leading)
        .shadow(color: .white.opacity(0.24), radius: 2)
        .animation(.easeOut(duration: 0.12), value: systemName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("亮度 \(percentage)%")
    }

    private var symbol: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: diameter * Design.symbolSizeRatio, weight: .semibold))
            .foregroundStyle(.white)
            .frame(
                width: showsLabel ? diameter * Design.symbolWidthRatio : diameter,
                height: diameter,
                alignment: .leading
            )
    }
}