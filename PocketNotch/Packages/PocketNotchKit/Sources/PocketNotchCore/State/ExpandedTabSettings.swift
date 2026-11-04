import Combine
import Foundation

/// 展开页标签栏的启用与顺序偏好，并即时持久化到 UserDefaults。
@MainActor
public final class ExpandedTabSettings: ObservableObject {
    private enum Keys {
        static let order = "interaction.island.expandedTabOrder"
        static let disabledTabs = "interaction.island.expandedTabDisabled"
    }

    @Published public private(set) var order: [ExpandedIslandTab] {
        didSet {
            guard order != oldValue else { return }
            defaults?.set(order.map(\.rawValue), forKey: Keys.order)
        }
    }

    @Published public private(set) var disabledTabs: Set<ExpandedIslandTab> {
        didSet {
            guard disabledTabs != oldValue else { return }
            defaults?.set(
                disabledTabs.map(\.rawValue).sorted(),
                forKey: Keys.disabledTabs
            )
        }
    }

    private let defaults: UserDefaults?

    /// 传入 `nil` 可创建不持久化的实例，便于测试与预览。
    public init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        self.order = Self.storedOrder(defaults: defaults)
        self.disabledTabs = Self.storedDisabledTabs(defaults: defaults)
    }

    /// 标签栏渲染顺序：以 `order` 为基准，过滤禁用项，并补齐未收录的标签
    /// （版本升级新增 case 时旧持久化数据不含它，自动追加到末尾）。
    public var visibleTabs: [ExpandedIslandTab] {
        managedTabs.filter { !disabledTabs.contains($0) }
    }

    /// 设置中心管理的完整标签列表（含禁用项）。
    public var managedTabs: [ExpandedIslandTab] {
        var tabs = order.filter { ExpandedIslandTab.defaultOrder.contains($0) }
        for tab in ExpandedIslandTab.defaultOrder where !tabs.contains(tab) {
            tabs.append(tab)
        }
        return tabs
    }

    public func isEnabled(_ tab: ExpandedIslandTab) -> Bool {
        !disabledTabs.contains(tab)
    }

    public func setEnabled(_ isEnabled: Bool, for tab: ExpandedIslandTab) {
        if isEnabled {
            disabledTabs.remove(tab)
        } else {
            guard canDisable(tab) else { return }
            disabledTabs.insert(tab)
        }
    }

    /// 至少保留一个启用标签。
    public func canDisable(_ tab: ExpandedIslandTab) -> Bool {
        visibleTabs.count > 1
    }

    public func moveUp(_ tab: ExpandedIslandTab) {
        move(tab, offset: -1)
    }

    public func moveDown(_ tab: ExpandedIslandTab) {
        move(tab, offset: 1)
    }

    public func resetToDefaults() {
        order = ExpandedIslandTab.defaultOrder
        disabledTabs = []
    }

    private func move(_ tab: ExpandedIslandTab, offset: Int) {
        var tabs = managedTabs
        guard let index = tabs.firstIndex(of: tab) else { return }
        let targetIndex = index + offset
        guard tabs.indices.contains(targetIndex) else { return }
        tabs.swapAt(index, targetIndex)
        order = tabs
    }

    private static func storedOrder(defaults: UserDefaults?) -> [ExpandedIslandTab] {
        guard let rawValues = defaults?.stringArray(forKey: Keys.order), !rawValues.isEmpty
        else { return ExpandedIslandTab.defaultOrder }
        let tabs = rawValues.compactMap(ExpandedIslandTab.init(rawValue:))
        guard !tabs.isEmpty else { return ExpandedIslandTab.defaultOrder }
        return tabs
    }

    private static func storedDisabledTabs(defaults: UserDefaults?) -> Set<ExpandedIslandTab> {
        guard let rawValues = defaults?.stringArray(forKey: Keys.disabledTabs) else { return [] }
        return Set(rawValues.compactMap(ExpandedIslandTab.init(rawValue:)))
    }
}