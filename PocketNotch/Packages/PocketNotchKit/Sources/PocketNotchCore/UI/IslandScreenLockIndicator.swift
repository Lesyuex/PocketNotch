import SwiftUI

/// 锁屏态左耳状态符号：锁上时显示锁，开锁时短暂显示开锁符号。
struct IslandScreenLockIndicator: View {
    let phase: ScreenLockPhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandCompactContentSize) private var compactContentSize

    private var symbolName: String {
        phase == .locked ? "lock.fill" : "lock.open.fill"
    }

    private var fontSize: CGFloat {
        let contentHeight = compactContentSize?.height
            ?? IslandAppearanceConstraints.defaultCompactHeight
        return min(max(contentHeight * 0.64, 10), 18)
    }

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: fontSize, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white.opacity(0.92))
            .contentTransition(
                reduceMotion
                    ? .opacity
                    : ContentTransition.symbolEffect(.replace)
            )
            .animation(
                reduceMotion
                    ? PocketNotchTheme.islandReducedMotionAnimation
                    : PocketNotchTheme.islandScreenLockAnimation,
                value: phase
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityHidden(true)
    }
}
