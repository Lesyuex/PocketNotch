import SwiftUI
import PocketNotchShared
import PocketNotchCore

struct AudioVolumeIcon: View {
    private enum Design {
        static let labelSpacing: CGFloat = 8
        static let symbolWidthRatio: CGFloat = 0.72
        static let symbolSizeRatio: CGFloat = 0.54
    }

    private static let symbols = [
        "speaker.slash.fill",
        "speaker.wave.1.fill",
        "speaker.wave.2.fill",
        "speaker.wave.3.fill"
    ]

    let systemName: String
    let percentage: Int
    let diameter: CGFloat
    var showsLabel = false

    var body: some View {
        HStack(alignment: .center, spacing: showsLabel ? Design.labelSpacing : 0) {
            symbol

            if showsLabel {
                Text("media.volume")
                    .font(.system(size: PocketNotchTheme.islandCompactFontSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize()
            }
        }
        .frame(height: diameter, alignment: .leading)
        .shadow(color: .white.opacity(0.24), radius: 2)
        .animation(.easeOut(duration: 0.12), value: systemName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: L10n.tr("media.volumePercentFormat"), percentage))
    }

    private var symbol: some View {
        // 音量等级在四个扬声器符号间交叉淡化；设备图标等其它符号直接渲染。
        ZStack {
            if Self.symbols.contains(systemName) {
                ForEach(Self.symbols, id: \.self) { symbol in
                    Image(systemName: symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: diameter * Design.symbolSizeRatio, weight: .semibold))
                        .foregroundStyle(.white)
                        // 固定左侧扬声器主体，仅让右侧声波数量变化。
                        .frame(width: diameter * Design.symbolWidthRatio, alignment: .leading)
                        .opacity(symbol == systemName ? 1 : 0)
                }
            } else {
                Image(systemName: systemName)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: diameter * Design.symbolSizeRatio, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(
            width: showsLabel ? diameter * Design.symbolWidthRatio : diameter,
            height: diameter,
            alignment: .leading
        )
    }
}

struct AudioVolumePercentage: View {
    private enum Design {
        static let barHeight: CGFloat = 4
        static let trackOpacity: CGFloat = 0.18
        static let fillOpacity: CGFloat = 0.92
        static let labelSpacing: CGFloat = 6
    }

    let percentage: Int
    let height: CGFloat
    var fill: VolumeBarFillStyle = .solid(.default)
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
        .accessibilityLabel(String(format: L10n.tr("media.volumePercentFormat"), percentage))
    }

    private var levelBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(Design.trackOpacity))

                Capsule(style: .continuous)
                    .fill(fillStyle)
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

    private var fillStyle: AnyShapeStyle {
        fill.shapeStyle
    }
}
