import SwiftUI
import PocketNotchCore

struct HeadphoneBatteryRing: View {
    private enum Design {
        static let ringScale: CGFloat = 0.78
        static let minimumLineWidth: CGFloat = 1.9
    }

    let percentage: Int?
    let deviceName: String
    let diameter: CGFloat
    @Environment(\.displayScale) private var displayScale

    private var normalizedPercentage: Int? {
        percentage.map { min(max($0, 0), 100) }
    }

    private var progress: CGFloat {
        CGFloat(normalizedPercentage ?? 0) / 100
    }

    private var ringDiameter: CGFloat {
        pixelAligned(diameter * Design.ringScale)
    }

    private var lineWidth: CGFloat {
        pixelAligned(max(ringDiameter * 0.13, Design.minimumLineWidth))
    }

    private var ringColor: Color {
        guard let normalizedPercentage, normalizedPercentage <= 20 else {
            return .green
        }
        return .red
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(ringColor.opacity(0.28), lineWidth: lineWidth)
                .frame(width: ringDiameter, height: ringDiameter)

            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: progress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: ringDiameter, height: ringDiameter)
        }
        .frame(width: pixelAligned(diameter), height: pixelAligned(diameter))
        .contentShape(Circle())
        .animation(.easeOut(duration: 0.35), value: normalizedPercentage)
        .accessibilityLabel(
            normalizedPercentage.map { "\(deviceName) 电量 \($0)%" } ?? "\(deviceName) 电量未知"
        )
    }

    private func pixelAligned(_ value: CGFloat) -> CGFloat {
        guard displayScale > 0, value.isFinite else { return value }
        return (value * displayScale).rounded(.toNearestOrAwayFromZero) / displayScale
    }
}
