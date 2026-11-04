import Combine
import Foundation

public enum CompactIslandTier: Int, CaseIterable, Identifiable, Sendable {
    case first = 1
    case second = 2

    public static let secondTierMinimumWidth: CGFloat = 345

    public var id: Self { self }
    public var title: String { "\(rawValue)档" }

    public static func resolved(
        forWidth width: CGFloat,
        stockDisplayActive: Bool
    ) -> Self {
        stockDisplayActive || width >= secondTierMinimumWidth ? .second : .first
    }

    public static func resolvedPreferredWidth(
        _ preferredWidth: CGFloat?,
        stockDisplayActive: Bool
    ) -> CGFloat? {
        guard stockDisplayActive else { return preferredWidth }
        return max(preferredWidth ?? IslandAppearanceConstraints.defaultCompactWidth, secondTierMinimumWidth)
    }

}

public enum CompactResidentModule: String, CaseIterable, Identifiable, Sendable {
    case none
    case stocks
    case media
    case weather
    public var id: Self { self }
    public var title: String {
        switch self { case .none: "不常驻"; case .stocks: "股票"; case .media: "歌曲"; case .weather: "天气" }
    }

    /// 显式常驻优先级表（数值越大优先级越高）：股票 > 音乐 > 天气 > 不常驻。
    /// `activeModule` 依据它来裁决，而不是依赖 if-else 的书写顺序。
    public var priority: Int {
        switch self {
        case .stocks: 4
        case .media: 3
        case .weather: 2
        case .none: 0
        }
    }
}

@MainActor
public final class CompactResidentSettings: ObservableObject {
    @Published public var selectedModule: CompactResidentModule {
        didSet { defaults.set(selectedModule.rawValue, forKey: "compact.resident.module") }
    }

    @Published public private(set) var isStockMonitoringEnabled = false
    @Published public private(set) var isStockPriorityActive = false
    @Published public private(set) var isMediaCompactDisplayActive = false
    @Published public private(set) var isMediaInitialStateResolving = false
    @Published public private(set) var isWeatherMonitoringEnabled = false
    /// Agent 运行时，常驻内容（股票/媒体/天气）让位于 agent 感知展示。
    @Published public private(set) var isAgentDisplayActive = false

    private let defaults: UserDefaults

    public var isStockCompactDisplayActive: Bool {
        isStockMonitoringEnabled && isStockPriorityActive
    }

    /// 股票是否仍驱动灵动岛的二档宽度。
    /// Agent 运行时股票让位（`activeModule` 返回 `.none`），此处同样回缩，
    /// 避免灵动岛停留在股票的二档长度。
    public var isStockDisplayActiveForLayout: Bool {
        isAgentDisplayActive ? false : isStockCompactDisplayActive
    }

    /// 实时内容只在这里仲裁，避免各 Feature 模块分别决定后产生重叠或空档。
    ///
    /// 依据 `CompactResidentModule.priority` 显式优先级表取舍：
    /// Agent 运行（最高的常驻）永远优先，其次股票 > 音乐 > 天气。
    public var activeModule: CompactResidentModule {
        // Agent 运行中优先级高于一切常驻：先让步，让 agent 感知展示独占灵动岛。
        if isAgentDisplayActive { return .none }
        // 候选：当前「真正 active」的常驻（股票需监控开 + 优先时段内）。
        var candidates: [CompactResidentModule] = []
        if isStockCompactDisplayActive { candidates.append(.stocks) }
        if isMediaCompactDisplayActive { candidates.append(.media) }
        if isWeatherMonitoringEnabled { candidates.append(.weather) }
        // 取最高优先级常驻。
        let selected = candidates.max { $0.priority < $1.priority } ?? .none
        // 媒体初始态尚未解析且媒体自身未 active 时，抑制「天气」这一未被媒体覆盖的低优先常驻，
        // 避免封面未就绪时先占右耳。媒体一旦 active 则按优先级正常胜出。
        if isMediaInitialStateResolving && !isMediaCompactDisplayActive && selected == .weather {
            return .none
        }
        return selected
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedModule = defaults.string(forKey: "compact.resident.module")
            .flatMap(CompactResidentModule.init(rawValue:)) ?? .none
    }

    public func setStockMonitoringEnabled(_ isEnabled: Bool) {
        isStockMonitoringEnabled = isEnabled
    }

    public func setStockPriorityActive(_ isActive: Bool) {
        isStockPriorityActive = isActive
    }

    public func setMediaCompactDisplayActive(_ isActive: Bool) {
        isMediaCompactDisplayActive = isActive
    }

    public func setMediaInitialStateResolving(_ isResolving: Bool) {
        isMediaInitialStateResolving = isResolving
    }

    public func setWeatherMonitoringEnabled(_ isEnabled: Bool) {
        isWeatherMonitoringEnabled = isEnabled
    }

    public func setAgentDisplayActive(_ isActive: Bool) {
        isAgentDisplayActive = isActive
    }
}
