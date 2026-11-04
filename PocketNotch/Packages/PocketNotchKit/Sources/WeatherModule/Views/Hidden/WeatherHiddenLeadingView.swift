import PocketNotchCore
import SwiftUI

struct WeatherCompactSymbolContent: View {
    private static let iconHeightScale: CGFloat = 0.70
    private static let cloudIconHeightScale: CGFloat = 0.50
    private static let fogIconHeightScale: CGFloat = 0.60
    private static let windIconHeightScale: CGFloat = 0.50

    let symbolName: String
    let symbolColor: Color
    @Environment(\.notchHiddenIslandSize) private var hiddenIslandSize
    @Environment(\.islandCompactContentSize) private var islandCompactContentSize

    private var diameter: CGFloat {
        islandCompactContentSize?.height
            ?? CompactIslandContentSpec.resolvedContentHeight(for: hiddenIslandSize.height)
    }

    private var contentWidth: CGFloat {
        islandCompactContentSize?.width
            ?? CompactIslandContentSpec.leadingContentWidth(forHeight: hiddenIslandSize.height)
    }

    private var iconHeight: CGFloat {
        let scale = switch symbolName {
        case "cloud.fill": Self.cloudIconHeightScale
        case "cloud.fog.fill": Self.fogIconHeightScale
        case "wind": Self.windIconHeightScale
        default: Self.iconHeightScale
        }
        return diameter * scale
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(symbolColor.opacity(0.05))
                .frame(width: diameter * 0.88, height: diameter * 0.88)

            Image(systemName: symbolName)
                .symbolRenderingMode(.hierarchical)
                .resizable()
                .scaledToFit()
                .foregroundStyle(symbolColor)
                .frame(height: iconHeight)
        }
        .frame(width: contentWidth, height: diameter, alignment: .leading)
    }
}

struct WeatherHiddenLeadingView: View {
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
            ?? CompactIslandContentSpec.leadingContentWidth(forHeight: hiddenIslandSize.height)
    }

    var body: some View {
        Group {
            if viewModel.isMonitoringEnabled {
                ZStack {
                    WeatherCompactSymbolContent(
                        symbolName: symbolName,
                        symbolColor: symbolColor
                    )
                    .id(viewModel.currentCompactMetric)
                    .transition(metricTransition)
                }
                .transition(.islandCompactModule(reduceMotion: reduceMotion))
            } else {
                Color.clear
            }
        }
        .frame(width: contentWidth, height: diameter, alignment: .leading)
        .compactIslandContentVisible(viewModel.isMonitoringEnabled)
        .islandGlowColor(viewModel.isMonitoringEnabled ? symbolColor : nil)
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

    private var symbolName: String {
        viewModel.currentCompactMetric.symbolName(for: viewModel.snapshot)
    }

    private var symbolColor: Color {
        switch viewModel.currentCompactMetric {
        case .temperature: return .orange
        case .apparentTemperature: return .cyan
        case .humidity: return .blue
        case .windSpeed: return .white
        case .condition: break
        }

        guard let snapshot = viewModel.snapshot else { return .white }
        if snapshot.weatherCode == 0 { return snapshot.isDay ? .yellow : .white }
        switch snapshot.weatherCode {
        case 95, 96, 99: return .purple
        default: return .white
        }
    }

    private var accessibilityText: String {
        let metric = viewModel.currentCompactMetric
        return "\(metric.title)，\(metric.valueText(for: viewModel.snapshot))"
    }

    private var metricTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.88).combined(with: .opacity)
    }

    private var metricAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.34, dampingFraction: 0.90)
    }
}
