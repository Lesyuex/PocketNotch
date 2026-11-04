import PocketNotchCore
import PocketNotchShared
import SwiftUI

/// 倒计时完成色：与 `NowTimerCardView.Design.finishedColor` 保持一致。
private let timerFinishedColor = Color(red: 1.0, green: 0.66, blue: 0.30).opacity(0.95)

/// 倒计时完成时 compact 前导临时通知：timer 圆形图标。
struct TimerCompletionLeadingView: View {
    let store: TimerStore
    @Environment(\.notchHiddenIslandSize) private var hiddenIslandSize
    @Environment(\.islandCompactContentSize) private var islandCompactContentSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var diameter: CGFloat {
        islandCompactContentSize?.height
            ?? CompactIslandContentSpec.resolvedContentHeight(for: hiddenIslandSize.height)
    }

    private var contentWidth: CGFloat {
        islandCompactContentSize?.width
            ?? CompactIslandContentSpec.leadingContentWidth(forHeight: hiddenIslandSize.height)
    }

    private var isVisible: Bool { store.completionPresentation != nil }

    private var currentTitle: String {
        let trimmed = store.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return store.mode == .countdown
                ? L10n.tr("timer.countdownModeTitle")
                : L10n.tr("timer.stopwatchModeTitle")
        }
        return trimmed
    }

    var body: some View {
        Group {
            if isVisible {
                Text(verbatim: currentTitle)
                    .font(.system(
                        size: PocketNotchTheme.islandCompactFontSize,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(height: diameter, alignment: .leading)
            } else {
                Color.clear
            }
        }
        .frame(height: diameter, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .islandGlowColor(isVisible ? .white : nil)
        .compactIslandContentVisible(isVisible)
        .compactIslandSuppressesResidentContent(isVisible)
        .animation(
            PocketNotchTheme.islandCompactModuleAnimation(
                isVisible: isVisible,
                reduceMotion: reduceMotion
            ),
            value: store.completionPresentation
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isVisible ? L10n.tr("timer.timeUp") : "")
    }
}

/// 倒计时完成时 compact 尾随临时通知：「时间到」文案。
struct TimerCompletionTrailingView: View {
    let store: TimerStore
    @Environment(\.notchHiddenIslandSize) private var hiddenIslandSize
    @Environment(\.islandCompactContentSize) private var islandCompactContentSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var diameter: CGFloat {
        islandCompactContentSize?.height
            ?? CompactIslandContentSpec.resolvedContentHeight(for: hiddenIslandSize.height)
    }

    private var isVisible: Bool { store.completionPresentation != nil }

    var body: some View {
        Group {
            if isVisible {
                Text("timer.timeUp")
                    .font(.system(
                        size: PocketNotchTheme.islandCompactFontSize,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(timerFinishedColor)
                    .fixedSize()
                    .frame(height: diameter, alignment: .center)
            } else {
                Color.clear
            }
        }
        .frame(height: diameter, alignment: .center)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .compactIslandContentVisible(isVisible)
        .compactIslandPreferredWidth(isVisible ? CompactIslandTier.secondTierMinimumWidth : nil)
        .compactIslandSuppressesResidentContent(isVisible)
        .animation(
            PocketNotchTheme.islandCompactModuleAnimation(
                isVisible: isVisible,
                reduceMotion: reduceMotion
            ),
            value: store.completionPresentation
        )
        .accessibilityHidden(true)
    }
}