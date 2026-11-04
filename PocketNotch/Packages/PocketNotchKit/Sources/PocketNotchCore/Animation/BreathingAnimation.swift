import SwiftUI

public enum HaloSymbolEffectPreset: String, CaseIterable, Identifiable, Sendable {
    case breatheSubtle
    case breatheStandard
    case breatheStrong
    case float
    case sway
    case bounce
    case ripple
    case shimmer
    case rotate
    case shake
    case jelly

    public var id: Self { self }

    public var title: String {
        switch self {
        case .breatheSubtle: "轻呼吸"
        case .breatheStandard: "标准呼吸"
        case .breatheStrong: "强呼吸"
        case .float: "浮动"
        case .sway: "摇摆"
        case .bounce: "弹跳"
        case .ripple: "波纹"
        case .shimmer: "闪烁"
        case .rotate: "旋转"
        case .shake: "抖动"
        case .jelly: "果冻缩放"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .breatheSubtle: 2.0
        case .breatheStandard: 1.45
        case .breatheStrong: 1.1
        case .float: 1.9
        case .sway: 1.5
        case .bounce: 0.78
        case .ripple: 1.35
        case .shimmer: 0.96
        case .rotate: 2.4
        case .shake: 0.42
        case .jelly: 0.88
        }
    }
}

private struct HaloSymbolEffectModifier: ViewModifier {
    let preset: HaloSymbolEffectPreset
    let isActive: Bool
    let reduceMotion: Bool

    @State private var phase = false

    func body(content: Content) -> some View {
        let baseContent = content
            .scaleEffect(scale)
            .opacity(opacity)
            .rotationEffect(rotation)
            .offset(offset)
            .onAppear(perform: syncAnimation)
            .onChange(of: isActive) { _, _ in syncAnimation() }
            .onChange(of: reduceMotion) { _, _ in syncAnimation() }

        return ZStack {
            rippleLayer
            baseContent
        }
    }

    @ViewBuilder
    private var rippleLayer: some View {
        if preset == .ripple, isActive, !reduceMotion {
            Circle()
                .stroke(Color.accentColor.opacity(phase ? 0 : 0.45), lineWidth: 1.5)
                .scaleEffect(phase ? 1.72 : 0.62)
                .frame(width: 22, height: 22)
                .allowsHitTesting(false)
        }
    }

    private var scale: CGFloat {
        guard isActive, !reduceMotion else { return 1 }
        switch preset {
        case .breatheSubtle:
            return phase ? 1.04 : 0.94
        case .breatheStandard:
            return phase ? 1.08 : 0.9
        case .breatheStrong:
            return phase ? 1.14 : 0.85
        case .bounce:
            return phase ? 1.08 : 0.94
        case .jelly:
            return phase ? 1.15 : 0.86
        default:
            return 1
        }
    }

    private var opacity: Double {
        guard isActive, !reduceMotion else { return 1 }
        switch preset {
        case .breatheSubtle:
            return phase ? 1 : 0.82
        case .breatheStandard:
            return phase ? 1 : 0.72
        case .breatheStrong:
            return phase ? 1 : 0.62
        case .shimmer:
            return phase ? 1 : 0.5
        default:
            return 1
        }
    }

    private var rotation: Angle {
        guard isActive, !reduceMotion else { return .zero }
        switch preset {
        case .sway:
            return .degrees(phase ? 8 : -8)
        case .rotate:
            return .degrees(phase ? 360 : 0)
        case .shake:
            return .degrees(phase ? 4 : -4)
        case .jelly:
            return .degrees(phase ? 2.2 : -2.2)
        default:
            return .zero
        }
    }

    private var offset: CGSize {
        guard isActive, !reduceMotion else { return .zero }
        switch preset {
        case .float:
            return CGSize(width: 0, height: phase ? -5 : 5)
        case .bounce:
            return CGSize(width: 0, height: phase ? -5 : 4)
        case .shake:
            return CGSize(width: phase ? 2.5 : -2.5, height: 0)
        default:
            return .zero
        }
    }

    private func syncAnimation() {
        guard isActive, !reduceMotion else {
            phase = false
            return
        }
        phase = false
        withAnimation(animation(for: preset)) {
            phase = true
        }
    }

    private func animation(for preset: HaloSymbolEffectPreset) -> Animation {
        switch preset {
        case .rotate:
            return .linear(duration: preset.duration).repeatForever(autoreverses: false)
        case .bounce:
            return .spring(response: preset.duration, dampingFraction: 0.52)
                .repeatForever(autoreverses: true)
        case .jelly:
            return .spring(response: preset.duration, dampingFraction: 0.46)
                .repeatForever(autoreverses: true)
        case .shake:
            return .easeInOut(duration: preset.duration).repeatForever(autoreverses: true)
        default:
            return .easeInOut(duration: preset.duration).repeatForever(autoreverses: true)
        }
    }
}

public extension View {
    func haloSymbolEffect(
        _ preset: HaloSymbolEffectPreset,
        isActive: Bool,
        reduceMotion: Bool = false
    ) -> some View {
        modifier(
            HaloSymbolEffectModifier(
                preset: preset,
                isActive: isActive,
                reduceMotion: reduceMotion
            )
        )
    }
}
