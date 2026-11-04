import Combine
import PocketNotchCore
import SwiftUI

public struct WeatherModule: PocketNotchModule {
    public let id = "weather"
    public let title: LocalizedStringKey = "module.weather.title"
    public let priority = 20

    @MainActor private let viewModel: WeatherViewModel
    @MainActor private let settings: WeatherMonitoringSettings
    @MainActor private let residentSettings: CompactResidentSettings
    @MainActor private let monitoringObserver: AnyCancellable

    @MainActor
    public init(settings: WeatherMonitoringSettings, residentSettings: CompactResidentSettings) {
        self.settings = settings
        viewModel = WeatherViewModel(settings: settings)
        self.residentSettings = residentSettings
        monitoringObserver = settings.$isWeatherMonitoringEnabled
            .removeDuplicates()
            .sink { [weak residentSettings] isEnabled in
                residentSettings?.setWeatherMonitoringEnabled(isEnabled)
            }
    }

    @MainActor public var isCompactModuleEnabled: Bool { residentSettings.activeModule == .weather }

    public func hiddenLeadingView() -> AnyView {
        AnyView(WeatherHiddenLeadingView(viewModel: viewModel))
    }

    public func hiddenTrailingView() -> AnyView {
        AnyView(WeatherHiddenTrailingView(viewModel: viewModel))
    }

    public var showsInCompactSettingsPreview: Bool { true }

    public var isCompactSettingsPreviewEnabled: Bool {
        settings.isWeatherMonitoringEnabled
    }

    public func compactSettingsPreviewLeadingView() -> AnyView {
        AnyView(WeatherSettingsPreviewLeadingView(viewModel: viewModel, settings: settings))
    }

    public func compactSettingsPreviewTrailingView() -> AnyView {
        AnyView(WeatherSettingsPreviewTrailingView(viewModel: viewModel, settings: settings))
    }

    public var showsInExpandedPage: Bool { true }

    public var expandedPageWeight: CGFloat { 3.3 }

    public func expandedView() -> AnyView {
        AnyView(WeatherExpandedPanelView(viewModel: viewModel))
    }

    public func activate() {
        Task { @MainActor in viewModel.activate() }
    }

    public func deactivate() {
        Task { @MainActor in viewModel.deactivate() }
    }
}

private struct WeatherSettingsPreviewLeadingView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @ObservedObject var settings: WeatherMonitoringSettings

    var body: some View {
        WeatherCompactSymbolContent(
            symbolName: metric.symbolName(for: viewModel.snapshot),
            symbolColor: symbolColor
        )
    }

    private var metric: WeatherCompactMetric {
        settings.compactMetrics[0]
    }

    private var symbolColor: Color {
        guard viewModel.snapshot != nil else { return .secondary }
        switch metric {
        case .temperature: return Color.orange
        case .condition: return Color.yellow
        case .apparentTemperature: return Color.cyan
        case .humidity: return Color.blue
        case .windSpeed: return Color.white
        }
    }
}

private struct WeatherSettingsPreviewTrailingView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @ObservedObject var settings: WeatherMonitoringSettings

    var body: some View {
        let metric = settings.compactMetrics[0]
        WeatherCompactMetricValueContent(
            metric: metric,
            valueText: metric.valueText(for: viewModel.snapshot)
        )
    }
}
