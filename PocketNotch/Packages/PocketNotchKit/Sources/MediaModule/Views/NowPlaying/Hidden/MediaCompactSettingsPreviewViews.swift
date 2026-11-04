import PocketNotchCore
import SwiftUI

struct MediaCompactSettingsPreviewLeadingView: View {
    @ObservedObject var settings: MediaMonitoringSettings
    @Environment(\.notchHiddenIslandSize) private var hiddenIslandSize
    @Environment(\.islandCompactContentSize) private var islandCompactContentSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Design {
        static let staticArtworkScale: CGFloat = 0.96
        static let glowOpacity: CGFloat = 0.22
        static let glowRadius: CGFloat = 3
        static let rotationDuration: Double = 10
    }

    private let palette = [
        Color(red: 0.18, green: 0.38, blue: 0.92),
        Color(red: 0.96, green: 0.42, blue: 0.50),
        Color(red: 0.98, green: 0.78, blue: 0.38),
    ]

    private var size: CGFloat {
        islandCompactContentSize?.height
            ?? CompactIslandContentSpec.resolvedContentHeight(for: hiddenIslandSize.height)
    }

    /// 与运行时一致：旋转模式封面铺满耳朵槽；非旋转模式取 92%，并在槽内居中。
    private var artworkSide: CGFloat {
        settings.isCompactArtworkRotationEnabled
            ? size
            : size * Design.staticArtworkScale
    }

    private var cornerRadius: CGFloat {
        let percentage = settings.isCompactArtworkRotationEnabled
            ? settings.compactRotatingArtworkCornerRadiusPercentage
            : settings.compactStaticArtworkCornerRadiusPercentage
        return artworkSide * 0.5 * CGFloat(min(max(percentage / 100, 0), 1))
    }

    private var isRotating: Bool {
        settings.isCompactArtworkRotationEnabled && !reduceMotion
    }

    var body: some View {
        RotatingCoverView(
            content: AnyView(previewCoverContent),
            isRotating: isRotating,
            resetToken: isRotating ? "rotating" : "static",
            songKey: "preview",
            rotationDuration: Design.rotationDuration,
            isRotationEnabledForChanges: isRotating
        )
        .frame(width: size, height: size, alignment: .leading)
    }

    private var previewCoverContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.black.opacity(0.92))
            previewArtwork
        }
        .frame(width: artworkSide, height: artworkSide)
        .frame(width: size, height: size)
        .shadow(
            color: palette[0].opacity(Design.glowOpacity),
            radius: Design.glowRadius
        )
    }

    private var previewArtwork: some View {
        LinearGradient(
            colors: palette,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "waveform")
                .font(.system(size: artworkSide * 0.38, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
        }
        .frame(width: artworkSide, height: artworkSide)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

}

struct MediaCompactSettingsPreviewTrailingView: View {
    @ObservedObject var settings: MediaMonitoringSettings
    @Environment(\.notchHiddenIslandSize) private var hiddenIslandSize
    @Environment(\.islandCompactContentSize) private var islandCompactContentSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let colors = [
        Color(red: 0.20, green: 0.74, blue: 0.96),
        Color(red: 0.52, green: 0.38, blue: 0.94),
        Color(red: 0.95, green: 0.38, blue: 0.58),
    ]

    private var diameter: CGFloat {
        islandCompactContentSize?.height
            ?? CompactIslandContentSpec.resolvedContentHeight(for: hiddenIslandSize.height)
    }

    var body: some View {
        SpectrumBarsView(
            source: PreviewSpectrumSource(),
            colors: colors,
            isActive: !reduceMotion,
            reduceMotion: reduceMotion,
            configuration: settings.musicSpectrumConfiguration
        )
        .frame(
            width: CompactIslandContentSpec.defaultSideContentWidth,
            height: diameter,
            alignment: .trailing
        )
    }
}

/// 设置预览用的合成频谱源：无真实 FFT，按显示时间生成律动。
final class PreviewSpectrumSource: SpectrumDataSource {
    let bandCount = AudioSpectrumConfiguration.sampledBandCount

    func readBands() -> [Float] {
        let time = Date().timeIntervalSinceReferenceDate
        return (0..<bandCount).map { index in
            let primary = abs(sin(time * 3.1 + Double(index) * 0.92))
            let secondary = abs(sin(time * 1.7 + Double(index) * 1.43))
            return Float(0.20 + primary * 0.52 + secondary * 0.24)
        }
    }
}
