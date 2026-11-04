import SwiftUI

struct MediaControlButtonStyle: ButtonStyle {
    var size: CGFloat = 34
    var visualSize: CGFloat?
    var isPrimary = false
    var isSelected = false
    var selectedColor: Color = .red
    /// 播放进度 0...1；≥1 时仅显示普通描边，否则把进度绘制到按钮自身边框上
    /// （从 12 点方向顺时针推进）。
    var progress: CGFloat = 1
    /// 为 true 时隐藏纯色/玻璃填充与阴影，只保留 (进度) 描边。
    var transparentBackground = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let isEmphasized = isHovering || configuration.isPressed || isPrimary
        let fillOpacity = resolvedFillOpacity(isPressed: configuration.isPressed)
        let resolvedVisualSize = min(max(visualSize ?? size, 1), size)
        let shape = RoundedRectangle(
            cornerRadius: isPrimary ? min(16, resolvedVisualSize / 2) : resolvedVisualSize / 2,
            style: .continuous
        )

        configuration.label
            .font(
                .system(
                    size: resolvedVisualSize * (isPrimary ? 0.41 : 0.38),
                    weight: .semibold
                )
            )
            .foregroundStyle(
                isSelected ? selectedColor.opacity(0.96) : Color.white.opacity(isPrimary ? 1 : 0.9)
            )
            .frame(width: resolvedVisualSize, height: resolvedVisualSize)
            .background {
                ZStack {
                    if !transparentBackground {
                        if reduceTransparency {
                            shape.fill(.white.opacity(fillOpacity + (isEmphasized ? 0.05 : 0)))
                        } else {
                            shape
                                .fill(.ultraThinMaterial)
                                .opacity(isEmphasized ? 1 : 0)
                            shape.fill(.white.opacity(fillOpacity))
                        }
                    }

                    shape.stroke(
                        .white.opacity(
                            configuration.isPressed
                                ? 0.34
                                : (isHovering ? 0.24 : (isPrimary ? 0.12 : 0))
                        ),
                        lineWidth: 0.8
                    )

                    if trimmedProgress < 1 {
                        // Circle 路径从 3 点方向顺时针起算，逆旋 90° 让起点/终点
                        // 都落在 12 点方向，进度弧从正上方顺时针推进并在正上方闭合。
                        Circle()
                            .trim(from: 0, to: trimmedProgress)
                            .stroke(
                                .white.opacity(0.9),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                    }
                }
                .shadow(
                    color: transparentBackground
                        ? .clear
                        : .black.opacity(isEmphasized ? (isPrimary ? 0.2 : 0.14) : 0),
                    radius: isPrimary ? 7 : 5,
                    y: isPrimary ? 3 : 2
                )
            }
            .scaleEffect(
                configuration.isPressed ? 0.93 : (isHovering ? 1.03 : 1)
            )
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isHovering = true
                case .ended:
                    isHovering = false
                }
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.9),
                value: isHovering
            )
            .animation(
                reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.72),
                value: configuration.isPressed
            )
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 1),
                value: isSelected
            )
    }

    private var trimmedProgress: CGFloat {
        min(max(progress, 0), 1)
    }

    private func resolvedFillOpacity(isPressed: Bool) -> CGFloat {
        if isPressed {
            return isPrimary ? 0.22 : 0.16
        }
        if isHovering {
            return isPrimary ? 0.15 : 0.1
        }
        return isPrimary ? 0.08 : 0
    }
}

struct MediaBorderlessControlButtonStyle: ButtonStyle {
    var size: CGFloat = 44
    var visualSize: CGFloat?
    var isPrimary = false
    var isSelected = false
    var foregroundColor: Color = .white
    var selectedColor: Color = .white
    /// 显式指定图标字号；缺省时按 visualSize × 系数自动推导。
    var iconSize: CGFloat?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let resolvedVisualSize = max(visualSize ?? size, 1)
        let hitExpansion = max((44 - size) / 2, 0)

        configuration.label
            .font(
                .system(
                    size: iconSize ?? resolvedVisualSize * (isPrimary ? 0.41 : 0.38),
                    weight: .semibold
                )
            )
            .foregroundStyle(
                isSelected
                    ? selectedColor.opacity(0.98)
                    : foregroundColor.opacity(isPrimary ? 1 : 0.92)
            )
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(.white.opacity(backgroundColorOpacity(isPressed: configuration.isPressed)))
                    .frame(width: 32, height: 32)
            }
            .opacity(configuration.isPressed ? 0.72 : (isHovering ? 1 : 0.9))
            .scaleEffect(configuration.isPressed ? 0.96 : (isHovering ? 1.02 : 1))
            .contentShape(Rectangle().inset(by: -hitExpansion))
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isHovering = true
                case .ended:
                    isHovering = false
                }
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 1),
                value: isHovering
            )
            .animation(
                reduceMotion ? nil : .spring(response: 0.14, dampingFraction: 1),
                value: configuration.isPressed
            )
    }

    private func backgroundColorOpacity(isPressed: Bool) -> CGFloat {
        if isPressed {
            return 0.10
        }
        if isHovering {
            return 0.05
        }
        return 0
    }
}
