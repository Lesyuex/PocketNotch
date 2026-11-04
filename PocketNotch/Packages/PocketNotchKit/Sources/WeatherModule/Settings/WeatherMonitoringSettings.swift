import Combine
import Foundation

public enum WeatherCompactMetric: String, CaseIterable, Codable, Identifiable, Sendable {
    case temperature
    case condition
    case apparentTemperature
    case humidity
    case windSpeed

    public var id: Self { self }

    public var title: String {
        switch self {
        case .temperature: "温度"
        case .condition: "天气状况"
        case .apparentTemperature: "体感温度"
        case .humidity: "湿度"
        case .windSpeed: "风速"
        }
    }

    public func symbolName(for snapshot: WeatherSnapshot?) -> String {
        switch self {
        case .temperature: "thermometer.medium"
        case .condition: snapshot?.symbolName ?? "location.fill"
        case .apparentTemperature: "thermometer.variable"
        case .humidity: "humidity.fill"
        case .windSpeed: "wind"
        }
    }

    public func valueText(for snapshot: WeatherSnapshot?) -> String {
        guard let snapshot else {
            return self == .condition ? "等待" : "--"
        }

        switch self {
        case .temperature:
            return snapshot.roundedTemperatureText
        case .condition:
            return snapshot.conditionText == "大致晴朗" ? "晴朗" : snapshot.conditionText
        case .apparentTemperature:
            return "\(Int(snapshot.apparentTemperature.rounded()))°"
        case .humidity:
            return snapshot.humidity.map { "\($0)%" } ?? "--"
        case .windSpeed:
            return snapshot.windSpeed.map { "\(Int($0.rounded()))km/h" } ?? "--"
        }
    }

    public var usesMonospacedDigits: Bool {
        self != .condition
    }
}

public struct WeatherSavedCoordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
}

/// 天气 compact 内容的用户偏好。只控制灵动刘海的常驻显示，天气数据在模块激活时始终获取。
@MainActor
public final class WeatherMonitoringSettings: ObservableObject {
    private enum Keys {
        static let weatherMonitoringEnabled = "weather.monitoringEnabled"
        static let compactMetrics = "weather.compactMetrics"
        static let metricOrder = "weather.metricOrder"
        static let automaticLocationEnabled = "weather.automaticLocationEnabled"
        static let lastLatitude = "weather.lastLatitude"
        static let lastLongitude = "weather.lastLongitude"
    }

    public static let defaultCompactMetrics: [WeatherCompactMetric] = [.temperature, .condition]

    @Published public var isWeatherMonitoringEnabled: Bool {
        didSet {
            defaults.set(isWeatherMonitoringEnabled, forKey: Keys.weatherMonitoringEnabled)
        }
    }

    /// 启用指标的有序子集（轮播展示用），始终按 `metricOrder` 的顺序排列。
    @Published public private(set) var compactMetrics: [WeatherCompactMetric] {
        didSet {
            defaults.set(compactMetrics.map(\.rawValue), forKey: Keys.compactMetrics)
        }
    }

    /// 全部指标（含未启用的）的完整顺序，排序操作与设置列表展示均基于此顺序。
    @Published public private(set) var metricOrder: [WeatherCompactMetric] {
        didSet {
            persistOrder()
        }
    }

    @Published public var isAutomaticLocationEnabled: Bool {
        didSet {
            defaults.set(isAutomaticLocationEnabled, forKey: Keys.automaticLocationEnabled)
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedMetrics = (defaults.stringArray(forKey: Keys.compactMetrics) ?? [])
            .compactMap(WeatherCompactMetric.init(rawValue:))
            .reduce(into: [WeatherCompactMetric]()) { metrics, metric in
                guard !metrics.contains(metric) else { return }
                metrics.append(metric)
            }
        let resolvedMetrics = storedMetrics.isEmpty ? Self.defaultCompactMetrics : storedMetrics
        compactMetrics = resolvedMetrics
        metricOrder = Self.resolvedMetricOrder(
            storedOrder: defaults.stringArray(forKey: Keys.metricOrder),
            enabledMetrics: resolvedMetrics
        )
        // 自动定位不再提供用户开关，始终开启。
        isAutomaticLocationEnabled = true

        if defaults.object(forKey: Keys.weatherMonitoringEnabled) == nil {
            isWeatherMonitoringEnabled = false
        } else {
            isWeatherMonitoringEnabled = defaults.bool(forKey: Keys.weatherMonitoringEnabled)
        }

        // 迁移：旧版本没有 metricOrder，首次写入以保持持久化。
        if defaults.stringArray(forKey: Keys.metricOrder) == nil {
            persistOrder()
        }
    }

    public func isMetricEnabled(_ metric: WeatherCompactMetric) -> Bool {
        compactMetrics.contains(metric)
    }

    private func persistOrder() {
        defaults.set(metricOrder.map(\.rawValue), forKey: Keys.metricOrder)
    }

    public func setMetric(_ metric: WeatherCompactMetric, isEnabled: Bool) {
        if isEnabled {
            guard !compactMetrics.contains(metric) else { return }
            var order = metricOrder
            if !order.contains(metric) {
                order.append(metric)
            }
            metricOrder = order
            compactMetrics = order.filter { $0 == metric || compactMetrics.contains($0) }
            return
        }

        guard compactMetrics.count > 1 else { return }
        compactMetrics = compactMetrics.filter { $0 != metric }
    }

    public func moveMetric(_ metric: WeatherCompactMetric, by offset: Int) {
        guard let sourceIndex = metricOrder.firstIndex(of: metric) else { return }
        let destinationIndex = sourceIndex + offset
        guard metricOrder.indices.contains(destinationIndex) else { return }
        metricOrder.swapAt(sourceIndex, destinationIndex)
        syncCompactMetricsFromOrder()
    }

    public func moveMetric(_ metric: WeatherCompactMetric, before target: WeatherCompactMetric) {
        guard metric != target,
              let fromIndex = metricOrder.firstIndex(of: metric),
              metricOrder.firstIndex(of: target) != nil else { return }
        var order = metricOrder
        order.remove(at: fromIndex)
        let insertIndex = order.firstIndex(of: target) ?? order.count
        order.insert(metric, at: insertIndex)
        metricOrder = order
        syncCompactMetricsFromOrder()
    }

    /// 排序变化后，让启用子集的顺序与全量顺序保持一致。
    private func syncCompactMetricsFromOrder() {
        let enabled = Set(compactMetrics)
        compactMetrics = metricOrder.filter(enabled.contains)
    }

    private static func resolvedMetricOrder(
        storedOrder: [String]?,
        enabledMetrics: [WeatherCompactMetric]
    ) -> [WeatherCompactMetric] {
        // 优先使用已持久化的全量顺序（去重、过滤未知项、补齐缺失项）。
        let stored = (storedOrder ?? [])
            .compactMap(WeatherCompactMetric.init(rawValue:))
            .reduce(into: [WeatherCompactMetric]()) { order, metric in
                guard !order.contains(metric) else { return }
                order.append(metric)
            }
        let order = stored.isEmpty
            ? enabledMetrics + WeatherCompactMetric.allCases.filter { !enabledMetrics.contains($0) }
            : stored + WeatherCompactMetric.allCases.filter { !stored.contains($0) }
        return order
    }

    public var savedCoordinate: WeatherSavedCoordinate? {
        guard defaults.object(forKey: Keys.lastLatitude) != nil,
              defaults.object(forKey: Keys.lastLongitude) != nil else {
            return nil
        }
        let latitude = defaults.double(forKey: Keys.lastLatitude)
        let longitude = defaults.double(forKey: Keys.lastLongitude)
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            return nil
        }
        return WeatherSavedCoordinate(latitude: latitude, longitude: longitude)
    }

    public func saveCoordinate(latitude: Double, longitude: Double) {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return }
        defaults.set(latitude, forKey: Keys.lastLatitude)
        defaults.set(longitude, forKey: Keys.lastLongitude)
    }

    public func resetToDefault() {
        isWeatherMonitoringEnabled = false
        compactMetrics = Self.defaultCompactMetrics
        metricOrder = Self.resolvedMetricOrder(
            storedOrder: nil,
            enabledMetrics: Self.defaultCompactMetrics
        )
        isAutomaticLocationEnabled = true
    }

    public var usesDefaultValues: Bool {
        isWeatherMonitoringEnabled == false
            && compactMetrics == Self.defaultCompactMetrics
            && isAutomaticLocationEnabled
    }
}
