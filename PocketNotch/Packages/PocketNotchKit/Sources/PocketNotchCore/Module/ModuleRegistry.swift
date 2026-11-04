import Foundation
import Observation

/// 模块注册与调度中心：按 priority 排序，向容器视图提供激活模块列表。
@Observable
@MainActor
public final class ModuleRegistry {
    public private(set) var modules: [any PocketNotchModule] = []

    public init() {}

    public func register(_ module: any PocketNotchModule) {
        guard !modules.contains(where: { $0.id == module.id }) else { return }
        modules.append(module)
        modules.sort { $0.priority < $1.priority }
    }

    public func activateAll() {
        modules.forEach { $0.activate() }
    }

    public func deactivateAll() {
        modules.forEach { $0.deactivate() }
    }
}
