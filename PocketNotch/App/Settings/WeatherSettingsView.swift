import AppKit
import Combine
import Foundation
import PocketNotchCore
import SwiftUI
import WeatherModule

private enum WeatherPreviewLayout {
    static let previewSize = CGSize(width: 270, height: 164)
}

struct WeatherMonitoringSettingsView: View {
    @ObservedObject var settings: WeatherMonitoringSettings
    var isEmbedded = false
    var appearanceSettings: IslandAppearanceSettings?
    var registry: ModuleRegistry?
    var wallpaperImage: NSImage?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isReordering = false

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { settings.isWeatherMonitoringEnabled },
            set: { settings.isWeatherMonitoringEnabled = $0 }
        )
    }

    var body: some View {
        Group {
            if isEmbedded {
                cards
            } else {
                ScrollView {
                    cards
                        .frame(maxWidth: 620, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 28)
                }
                .settingsDetailScrolling()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: SettingsHeaderLayout.cardSpacing) {
            SettingsCard {
                realtimeWeatherCard
            }

            SettingsCard {
                weatherPreviewCard
            }

            SettingsCard {
                weatherConfigurationCard
            }
        }
    }

    private var realtimeWeatherCard: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("settings.weather.realtimeWeather")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                statusBadge
            }

            Spacer(minLength: 8)

            Toggle("settings.weather.showWeatherMonitoring", isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(SettingsCompactSwitchToggleStyle())
                .frame(width: 44, height: 44)
                .accessibilityHint("settings.weather.showWeatherMonitoring.description")
        }
        .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)
    }

    var weatherPreviewCard: some View {
        Group {
            if let appearanceSettings, let registry {
                HStack(alignment: .top, spacing: 0) {
                    Text("settings.weather.weatherDynamic")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    CompactContentPreview(
                        feature: .weather,
                        registry: registry,
                        wallpaperImage: wallpaperImage,
                        previewHeight: WeatherPreviewLayout.previewSize.height
                    )
                    .frame(
                        width: WeatherPreviewLayout.previewSize.width,
                        height: WeatherPreviewLayout.previewSize.height
                    )
                }
                .frame(height: WeatherPreviewLayout.previewSize.height)
                .padding(.vertical, AppearanceCardLayout.contentInset)
            }
        }
    }

    private var weatherConfigurationCard: some View {
VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("settings.weather.displayAndOrder")
                        .font(.system(size: 12, weight: .semibold))

                    Spacer(minLength: 8)

                    SettingsSortModeButton(isActive: $isReordering)
                }
                .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)

                ForEach(Array(displayMetrics.enumerated()), id: \.element) { index, metric in
                    metricRow(metric)
                    if index < displayMetrics.count - 1 {
                        AppearanceRowDivider()
                    }
                }
            }
    }

    private func metricRow(_ metric: WeatherCompactMetric) -> some View {
        let isSelected = settings.isMetricEnabled(metric)
        let orderIndex = settings.metricOrder.firstIndex(of: metric) ?? 0
        let isFirst = orderIndex == 0
        let isLast = orderIndex == settings.metricOrder.count - 1

        return HStack(spacing: 12) {
            Image(systemName: settingsSymbol(for: metric))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(metricTint(for: metric))
                .frame(width: 20)

            Text(metric.title)
                .font(.callout.weight(.medium))

            Spacer(minLength: 12)

            if isReordering {
                HStack(spacing: 0) {
                    if isFirst {
                        Color.clear
                            .frame(width: 44, height: 44)
                    } else {
                        SettingsMoveArrowButton(
                            systemImage: "chevron.up",
                            help: NSLocalizedString("settings.common.moveUp", comment: ""),
                            xOffset: 7
                        ) {
                            settings.moveMetric(metric, by: -1)
                        }
                    }

                    if isLast {
                        Color.clear
                            .frame(width: 44, height: 44)
                    } else {
                        SettingsMoveArrowButton(
                            systemImage: "chevron.down",
                            help: NSLocalizedString("settings.common.moveDown", comment: ""),
                            xOffset: -7
                        ) {
                            settings.moveMetric(metric, by: 1)
                        }
                    }
                }
            } else {
                Toggle(metric.title, isOn: Binding(
                    get: { settings.isMetricEnabled(metric) },
                    set: { settings.setMetric(metric, isEnabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(SettingsCompactSwitchToggleStyle())
                .frame(width: 44, height: 44)
                .disabled(isSelected && settings.compactMetrics.count == 1)
            }
        }
        .frame(height: AppearanceRowLayout.moduleRowHeight)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isReordering)
    }

    private var displayMetrics: [WeatherCompactMetric] {
        settings.metricOrder
    }

    private func settingsSymbol(for metric: WeatherCompactMetric) -> String {
        switch metric {
        case .condition: "cloud.sun.fill"
        default: metric.symbolName(for: nil)
        }
    }

    private func metricTint(for metric: WeatherCompactMetric) -> Color {
        switch metric {
        case .temperature: .orange
        case .condition: .yellow
        case .apparentTemperature: .cyan
        case .humidity: .blue
        case .windSpeed: .white
        }
    }

    private var statusBadge: some View {
        Text(settings.isWeatherMonitoringEnabled ? NSLocalizedString("settings.common.enabled", comment: "") : NSLocalizedString("settings.common.closed", comment: ""))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(settings.isWeatherMonitoringEnabled ? Color.yellow : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(settings.isWeatherMonitoringEnabled ? Color.yellow.opacity(0.12) : Color.secondary.opacity(0.10))
            }
            .animation(.easeOut(duration: 0.16), value: settings.isWeatherMonitoringEnabled)
    }

}

/// 排序模式的本地切换按钮：进入排序模式后行内显示上移/下移图标。
private struct SettingsSortModeButton: View {
    @Binding var isActive: Bool

    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                isActive.toggle()
            }
        } label: {
            Label(
                LocalizedStringKey(isActive ? "settings.common.done" : "settings.common.sort"),
                systemImage: isActive ? "checkmark" : "arrow.up.arrow.down"
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(
                        isActive
                            ? Color.accentColor.opacity(isHovering ? 0.18 : 0.12)
                            : Color.primary.opacity(isHovering ? 0.12 : 0.06)
                    )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .onHover { isHovering = $0 }
        .help(isActive ? NSLocalizedString("settings.common.finishSort", comment: "") : NSLocalizedString("settings.common.enterSort", comment: ""))
        .accessibilityLabel(isActive ? NSLocalizedString("settings.common.finishSort", comment: "") : NSLocalizedString("settings.common.enterSort", comment: ""))
    }
}
