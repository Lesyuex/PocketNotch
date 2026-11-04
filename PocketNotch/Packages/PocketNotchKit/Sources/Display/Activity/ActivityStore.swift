import Foundation
import Combine

/// Activity 的聚合存储。
///
/// 职责边界（遵循设计文档第三章）：
/// - 只负责提供「当前有哪些 Activity、是否 active、数据、更新时间」。
/// - 不在内部决定「是否显示 / 什么时候显示 / 是否抢占 Agent」——
///   这些属于 `DisplayScheduler`。
///
/// 各业务模块（Music / Weather / Stock）通过 `update(_:)` 喂入快照，
/// 或注册为 `ActivityProviding` 由 Store 按需拉取。Store 对业务实现无感知。
@MainActor
public final class ActivityStore: ObservableObject {
    @Published public private(set) var activities: [ActivityKind: ActivityContent] = [:]

    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// 由业务模块直接喂入最新快照。
    public func update(_ content: ActivityContent) {
        activities[content.kind] = content
    }

    /// 标记某种 Activity 已不再 active（停止展示的语义仍交给 Scheduler）。
    public func setInactive(_ kind: ActivityKind) {
        guard let current = activities[kind] else { return }
        activities[kind] = ActivityContent(
            kind: kind,
            isActive: false,
            updatedAt: now(),
            payload: current.payload
        )
    }

    public func snapshot(_ kind: ActivityKind) -> ActivityContent? {
        activities[kind]
    }

    /// 当前处于 active 的 Activity，按更新时间升序（稳定顺序便于轮换）。
    public var activeActivities: [ActivityContent] {
        activities.values
            .filter(\.isActive)
            .sorted { $0.updatedAt < $1.updatedAt }
    }
}