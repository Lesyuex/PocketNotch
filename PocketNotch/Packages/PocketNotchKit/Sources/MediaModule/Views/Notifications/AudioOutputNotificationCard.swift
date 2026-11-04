import AppKit
import PocketNotchCore
import SwiftUI

private enum AudioOutputNotificationDesign {
    static let deviceIconSize: CGFloat = 40
    static let horizontalInset: CGFloat = 10
    static let contentGap: CGFloat = 8
    static let statusHorizontalInset: CGFloat = 7
    static let statusVerticalInset: CGFloat = 2.5
    static let accentColor = Color(red: 0.78, green: 0.86, blue: 0.96)
    static let glowColor = PocketNotchTheme.islandHoverGlow
    /// 输出设备卡片使用更克制的外发光，避免浅色设备图标与蓝色光晕叠加后过亮。
    static let glowOpacity: Double = 0.08
}

/// 音频输出通知组件：统一封装卡片外壳、当前输出状态、设备图标和进退场动画。
struct AudioOutputNotificationCard: View {
    let snapshot: AudioOutputDeviceSnapshot
    let width: CGFloat
    let isDismissing: Bool
    var dismissalEffect: IslandNotificationDismissalEffect = .standard

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        IslandNotificationCard(
            width: width,
            height: IslandNotificationDesign.cardHeight,
            accentColor: AudioOutputNotificationDesign.accentColor,
            glowColor: AudioOutputNotificationDesign.glowColor,
            glowOpacity: AudioOutputNotificationDesign.glowOpacity,
            tintColors: [
                .white.opacity(0.075),
                Color(red: 0.43, green: 0.62, blue: 0.82).opacity(0.055),
                .clear
            ],
            dismissalEffect: dismissalEffect,
            isDismissing: isDismissing
        ) {
            HStack(spacing: AudioOutputNotificationDesign.contentGap) {
                AudioOutputDeviceSymbolView(
                    systemName: snapshot.deviceSymbolName,
                    appeared: appeared,
                    reduceMotion: reduceMotion,
                    isDismissing: isDismissing
                )
                .frame(
                    width: AudioOutputNotificationDesign.deviceIconSize,
                    height: AudioOutputNotificationDesign.deviceIconSize
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: snapshot.deviceName)
                        .font(Font(NSFont.preferredFont(forTextStyle: .headline)))
                        .foregroundStyle(.white.opacity(0.97))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 4, height: 4)
                            .shadow(color: .green.opacity(0.48), radius: 2)

                        Text(snapshot.notificationStatusText)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    .padding(.horizontal, AudioOutputNotificationDesign.statusHorizontalInset)
                    .padding(.vertical, AudioOutputNotificationDesign.statusVerticalInset)
                    .background {
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.055))
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, AudioOutputNotificationDesign.horizontalInset)
            .frame(width: width, height: IslandNotificationDesign.cardHeight)
        }
        .opacity(appeared ? 1 : 0)
        .blur(radius: reduceMotion || appeared ? 0 : 1.5)
        .scaleEffect(
            reduceMotion || appeared ? 1 : 0.985,
            anchor: .top
        )
        .offset(y: reduceMotion || appeared ? 0 : -4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(snapshot.deviceName)，\(snapshot.notificationStatusText)")
        .task(id: snapshot.deviceName) {
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.16)
                    : IslandNotificationDesign.insertionAnimation
            ) {
                appeared = true
            }
        }
    }
}

private struct AudioOutputDeviceSymbolView: View {
    let systemName: String
    let appeared: Bool
    let reduceMotion: Bool
    let isDismissing: Bool

    @State private var symbolScale: CGFloat
    @State private var symbolOffsetY: CGFloat
    @State private var shineOffset: CGFloat
    @State private var hasRunEntrance: Bool

    init(systemName: String, appeared: Bool, reduceMotion: Bool, isDismissing: Bool) {
        self.systemName = systemName
        self.appeared = appeared
        self.reduceMotion = reduceMotion
        self.isDismissing = isDismissing

        // 粒子消散开始时内容会进入 Timeline 分支；重建后的图标必须保持当前静止位置。
        let startsSettled = appeared || reduceMotion
        _symbolScale = State(initialValue: startsSettled ? 1 : 0.9)
        _symbolOffsetY = State(initialValue: startsSettled ? 0 : -2)
        _shineOffset = State(initialValue: startsSettled ? 18 : -18)
        _hasRunEntrance = State(initialValue: startsSettled)
    }

    var body: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(appeared ? 0.32 : 0.1))
                .frame(width: 27, height: 5)
                .blur(radius: 3)
                .scaleEffect(x: appeared ? 1 : 0.76)
                .offset(y: 17)

            if systemName.hasPrefix("airpods") {
                AirPodsModelNotificationIcon(
                    reduceMotion: reduceMotion,
                    isActive: appeared && !isDismissing
                )
                .scaleEffect(reduceMotion ? 1 : symbolScale)
                .offset(y: reduceMotion ? 0 : symbolOffsetY)
                .allowsHitTesting(false)
            } else {
                systemSymbol
            }
        }
        .task(id: appeared) {
            guard appeared, !hasRunEntrance else { return }
            hasRunEntrance = true
            guard !reduceMotion else {
                symbolScale = 1
                symbolOffsetY = 0
                shineOffset = 18
                return
            }

            // 设备图标只做一次无回弹落位和高光扫过，结束后完全静止。
            withAnimation(.spring(response: 0.34, dampingFraction: 1)) {
                symbolScale = 1
                symbolOffsetY = 0
                shineOffset = 7
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 1)) {
                shineOffset = 18
            }
        }
    }

    private var systemSymbol: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(
                LinearGradient(
                    colors: [.white, .white.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                // 沿系统设备图标轮廓扫过一次高光，提供产品质感但不伪造三维几何。
                LinearGradient(
                    colors: [.clear, .white.opacity(0.5), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 9)
                .offset(x: shineOffset)
                .mask {
                    Image(systemName: systemName)
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 30, weight: .medium))
                }
            }
            .shadow(color: .white.opacity(0.16), radius: 1)
            .shadow(color: .black.opacity(0.42), radius: 4, y: 2)
            .scaleEffect(reduceMotion ? 1 : symbolScale)
            .offset(y: reduceMotion ? 0 : symbolOffsetY)
    }
}
