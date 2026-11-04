import SwiftUI
import PocketNotchCore

struct HeadphoneIcon: View {
    private enum Motion {
        static let initialScale: CGFloat = 0.88
        static let overshootScale: CGFloat = 1.035
        static let initialOffsetY: CGFloat = 1.5
        static let reveal = Animation.spring(response: 0.34, dampingFraction: 0.76)
        static let settle = Animation.spring(response: 0.22, dampingFraction: 0.9)
    }

    let systemName: String
    let deviceName: String
    let diameter: CGFloat
    let isDismissing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var symbolScale = Motion.initialScale
    @State private var symbolOffsetY = Motion.initialOffsetY
    @State private var symbolOpacity = 1.0
    @State private var symbolBlur: CGFloat = 0
    @State private var shineProgress: CGFloat = 0

    private var isAirPods: Bool {
        AudioOutputDeviceSymbol.isAirPods(deviceName: deviceName, symbolName: systemName)
    }

    var body: some View {
        Group {
            if isAirPods {
                AirPodsSpatialIcon(
                    systemName: systemName,
                    presentationKey: deviceName,
                    diameter: diameter,
                    isDismissing: isDismissing
                )
            } else {
                layeredIcon
                    .scaleEffect(
                        reduceMotion ? 1 : (isDismissing ? 0.97 : symbolScale)
                    )
                    .offset(y: reduceMotion ? 0 : (isDismissing ? 1 : symbolOffsetY))
                    .opacity(isDismissing ? 0 : (reduceMotion ? 1 : symbolOpacity))
                    .blur(radius: reduceMotion ? 0 : symbolBlur)
                    .animation(
                        PocketNotchTheme.islandCompactModuleAnimation(
                            isVisible: !isDismissing,
                            reduceMotion: reduceMotion
                        ),
                        value: isDismissing
                    )
                    .task(id: deviceName) { await reveal() }
            }
        }
        .frame(width: diameter, height: diameter, alignment: .leading)
        .accessibilityLabel("已连接 \(deviceName)")
    }

    private var layeredIcon: some View {
        ZStack {
            headphoneSymbol
                .foregroundStyle(.black.opacity(0.72))
                .offset(x: diameter * 0.035, y: diameter * 0.035)

            headphoneSymbol
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.5), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: diameter * 0.18)
                    .offset(x: diameter * (-0.7 + shineProgress * 1.4))
                    .mask { headphoneSymbol }
                }
        }
        .shadow(color: .white.opacity(0.22), radius: 0.8)
    }

    private var headphoneSymbol: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: floor(diameter * 0.64), weight: .semibold))
            .frame(height: diameter)
    }

    @MainActor
    private func reveal() async {
        guard !reduceMotion else {
            symbolScale = 1
            symbolOffsetY = 0
            symbolOpacity = 1
            symbolBlur = 0
            shineProgress = 1
            return
        }

        withAnimation(Motion.reveal) {
            symbolScale = Motion.overshootScale
            symbolOffsetY = 0
            symbolOpacity = 1
            symbolBlur = 0
            shineProgress = 0.72
        }

        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }

        withAnimation(Motion.settle) {
            symbolScale = 1
            shineProgress = 1
        }
    }
}
