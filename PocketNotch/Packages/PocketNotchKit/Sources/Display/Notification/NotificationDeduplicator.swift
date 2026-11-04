import Foundation
import Combine

/// 通知去重器。
///
/// 负责在通知入队前抑制重复/无效通知，避免同一「事实」重复反馈。
/// 本阶段提供简单的 key 去重；复杂策略后续在 `NotificationDeduplicator` 中扩展。
public protocol NotificationDeduplicating {
    /// 返回 nil 表示该通知应被丢弃；返回原值表示通过。
    func deduplicate(_ notification: PocketNotchNotification) -> PocketNotchNotification?
}

/// 默认去重：同一 agent + session + type 的重复通知只保留最新一条。
public final class NotificationDeduplicator: NotificationDeduplicating {
    private var recentKeys: [String: Date] = [:]

    public init() {}

    public func deduplicate(_ notification: PocketNotchNotification) -> PocketNotchNotification? {
        guard let agentId = notification.agentId, let sessionId = notification.sessionId else {
            return notification
        }
        let generation = notification.sessionGeneration ?? 0
        let key = "\(agentId)|\(sessionId)|\(generation)|\(notification.type.rawValue)"
        // 简单实现：相同 key 在 0.5 秒内的重复通知被丢弃。
        if let last = recentKeys[key], notification.createdAt.timeIntervalSince(last) < 0.5 {
            return nil
        }
        recentKeys[key] = notification.createdAt
        return notification
    }
}
