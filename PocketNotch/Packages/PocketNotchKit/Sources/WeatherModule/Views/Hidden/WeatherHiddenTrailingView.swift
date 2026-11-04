import PocketNotchCore
import SwiftUI

struct WeatherCompactMetricValueContent: View {
    let metric: WeatherCompactMetric
    let valueText: String

    @Environment(\.notchHiddenIslandSize) private var hiddenIslandSize
    @Environment(\.islandCompactContentSize) private var islandCompactContentSize

    private var diameter: CGFloat {
        islandCompactContentSize?.height
            ?? CompactIslandContentSpec.resolvedContentHeight(for: hiddenIslandSize.height)
    }

    private var contentWidth: CGFloat {
        islandCompactContentSize?.width
            ?? CompactIslandContentSpec.trailingContentWidth(forHeight: hiddenIslandSize.height)
    }

    var body: some View {
        let text = Text(valueText)
            .font(.system(
                size: PocketNotchTheme.islandCompactFontSize,
                weight: .bold,
                design: metric.usesMonospacedDigits ? .rounded : .default
            ))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: contentWidth, height: diameter, alignment: .trailing)

        if metric.usesMonospacedDigits {
            text.monospacedDigit()
        } else {
            text
        }
    }
}

struct WeatherHiddenTrailingView: View {

    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.notchHiddenIslandSize) private var hiddenIslandSize
    @Environment(\.islandCompactContentSize) private var islandCompactContentSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var diameter: CGFloat {
        islandCompactContentSize?.height
            ?? CompactIslandContentSpec.resolvedContentHeight(for: hiddenIslandSize.height)
    }

    private var contentWidth: CGFloat {
        islandCompactContentSize?.width
            ?? CompactIslandContentSpec.trailingContentWidth(forHeight: hiddenIslandSize.height)
    }

    var body: some View {
        Group {
            if viewModel.isMonitoringEnabled {
                ZStack {
                    WeatherCompactMetricValueContent(
                        metric: viewModel.currentCompactMetric,
                        valueText: valueText
                    )
                    .id(viewModel.currentCompactMetric)
                    .transition(metricTransition)
                }
                .transition(.islandCompactModule(reduceMotion: reduceMotion))
            } else {
                Color.clear
            }
        }
        .frame(width: contentWidth, height: diameter, alignment: .trailing)
        .animation(
            PocketNotchTheme.islandCompactModuleAnimation(
                isVisible: viewModel.isMonitoringEnabled,
                reduceMotion: reduceMotion
            ),
            value: viewModel.isMonitoringEnabled
        )
        .animation(metricAnimation, value: viewModel.currentCompactMetric)
        .onAppear { viewModel.beginCompactPresentation() }
        .onDisappear { viewModel.endCompactPresentation() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var valueText: String {
        viewModel.currentCompactMetric.valueText(for: viewModel.snapshot)
    }

    private var accessibilityText: String {
        let metric = viewModel.currentCompactMetric
        return "\(metric.title)，\(metric.valueText(for: viewModel.snapshot))"
    }

    private var metricTransition: AnyTransition {
        reduceMotion ? .opacity : .weatherPageFlip
    }

    private var metricAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.24)
            : .timingCurve(0.22, 0.68, 0.24, 1, duration: 0.56)
    }
}

private struct WeatherPageFlipModifier: AnimatableModifier {
    var angle: Double
    var yOffset: CGFloat
    var opacity: Double
    let anchor: UnitPoint

    var animatableData: AnimatablePair<Double, AnimatablePair<CGFloat, Double>> {
        get { AnimatablePair(angle, AnimatablePair(yOffset, opacity)) }
        set {
            angle = newValue.first
            yOffset = newValue.second.first
            opacity = newValue.second.second
        }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if abs(angle) < 0.001, abs(yOffset) < 0.001, opacity > 0.999 {
            content
        } else {
            content
                .rotation3DEffect(
                    .degrees(angle),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: anchor,
                    perspective: 0.55
                )
                .offset(y: yOffset)
                .opacity(opacity)
        }
    }
}

private extension AnyTransition {
    static var weatherPageFlip: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: WeatherPageFlipModifier(
                    angle: -76,
                    yOffset: 4,
                    opacity: 0,
                    anchor: .bottom
                ),
                identity: WeatherPageFlipModifier(
                    angle: 0,
                    yOffset: 0,
                    opacity: 1,
                    anchor: .bottom
                )
            ),
            removal: .modifier(
                active: WeatherPageFlipModifier(
                    angle: 76,
                    yOffset: -4,
                    opacity: 0,
                    anchor: .top
                ),
                identity: WeatherPageFlipModifier(
                    angle: 0,
                    yOffset: 0,
                    opacity: 1,
                    anchor: .top
                )
            )
        )
    }
}
