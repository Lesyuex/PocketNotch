import SwiftUI

public struct CompactPercentageLabel: View {
    let percentage: Int
    let width: CGFloat
    let height: CGFloat
    let color: Color
    let accessibilityText: String
    let percentSignOpacity: Double

    public init(
        percentage: Int,
        width: CGFloat,
        height: CGFloat,
        color: Color,
        accessibilityText: String,
        percentSignOpacity: Double = 0.72
    ) {
        self.percentage = percentage
        self.width = width
        self.height = height
        self.color = color
        self.accessibilityText = accessibilityText
        self.percentSignOpacity = percentSignOpacity
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0.5) {
            Text(percentage, format: .number)
                .font(.system(
                    size: PocketNotchTheme.islandCompactFontSize,
                    weight: .bold,
                    design: .rounded
                ))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(percentage)))

            Text("%")
                .font(.system(
                    size: PocketNotchTheme.islandCompactFontSize,
                    weight: .semibold,
                    design: .rounded
                ))
                .foregroundStyle(color.opacity(percentSignOpacity))
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .frame(width: width, height: height, alignment: .trailing)
        .animation(.easeOut(duration: 0.16), value: percentage)
        .accessibilityLabel(accessibilityText)
    }
}
