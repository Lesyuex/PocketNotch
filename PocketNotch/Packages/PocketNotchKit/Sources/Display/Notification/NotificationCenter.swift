import Foundation
import PocketNotchShared
import Combine

/// 通知中枢。
///
/// 职责（设计文档第十章）：把「状态变化」转换为「瞬时通知」。
/// - 接收 AgentEvent（以及未来 Other/System Event）。
/// - 去重 → 记录到 Store → 入队 Queue。
///
/// 铁律：通知与 Agent 解耦。通知的入队/消失都不会修改任何 Agent / Session 状态。
@MainActor
public final class NotificationCenter: ObservableObject {
    public let queue: NotificationQueue
    public let store: NotificationStore
    public let deduplicator: NotificationDeduplicating

    private let now: () -> Date

    public init(
        queue: NotificationQueue? = nil,
        store: NotificationStore? = nil,
        deduplicator: NotificationDeduplicating? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        // 在 MainActor 上下文内构造默认实例，避免非隔离默认参数错误。
        self.queue = queue ?? NotificationQueue(now: now)
        self.store = store ?? NotificationStore(now: now)
        self.deduplicator = deduplicator ?? NotificationDeduplicator()
        self.now = now
    }

    /// 由 AgentEvent 生成并投递通知。
    /// - Returns: 实际入队的通知；若被去重丢弃则返回 nil。
    @discardableResult
    public func receive(_ event: AgentEvent, agentDisplayName: String? = nil) -> PocketNotchNotification? {
        let notification = makeNotification(from: event, agentDisplayName: agentDisplayName)
        return deliver(notification)
    }

    /// 直接投递一条已构造好的通知（供 System/Other Event 使用）。
    @discardableResult
    public func deliver(_ notification: PocketNotchNotification) -> PocketNotchNotification? {
        guard let allowed = deduplicator.deduplicate(notification) else { return nil }
        store.record(allowed)
        queue.enqueue(allowed)
        return allowed
    }

    // MARK: - Event → Notification

    private func makeNotification(from event: AgentEvent, agentDisplayName: String?) -> PocketNotchNotification {
        let type = NotificationType(from: event.type)
        let agentName = agentDisplayName ?? event.agentId

        switch event.type {
        case .sessionCreated:
            return PocketNotchNotification(
                source: .agent,
                type: type,
                agentId: event.agentId,
                sessionId: event.sessionId,
                sessionGeneration: event.sessionGeneration,
                title: agentName,
                subtitle: L10n.tr("agent.notification.sessionStarted"),
                createdAt: now(),
                duration: 3
            )
        case .sessionRunning:
            return PocketNotchNotification(
                source: .agent,
                type: type,
                agentId: event.agentId,
                sessionId: event.sessionId,
                sessionGeneration: event.sessionGeneration,
                title: agentName,
                subtitle: L10n.tr("agent.notification.working"),
                createdAt: now(),
                duration: 3
            )
        case .sessionWaitingApproval:
            return PocketNotchNotification(
                source: .agent,
                type: type,
                agentId: event.agentId,
                sessionId: event.sessionId,
                sessionGeneration: event.sessionGeneration,
                title: agentName,
                subtitle: L10n.tr("agent.notification.waitingApproval"),
                createdAt: now(),
                duration: 8
            )
        case .sessionCompleted:
            return PocketNotchNotification(
                source: .agent,
                type: type,
                agentId: event.agentId,
                sessionId: event.sessionId,
                sessionGeneration: event.sessionGeneration,
                title: agentName,
                subtitle: L10n.tr("agent.notification.completed"),
                createdAt: now(),
                duration: 4
            )
        case .sessionFailed:
            return PocketNotchNotification(
                source: .agent,
                type: type,
                agentId: event.agentId,
                sessionId: event.sessionId,
                sessionGeneration: event.sessionGeneration,
                title: agentName,
                subtitle: L10n.tr("agent.notification.failed"),
                createdAt: now(),
                duration: 4
            )
        case .sessionStopped:
            return PocketNotchNotification(
                source: .agent,
                type: .stopped,
                agentId: event.agentId,
                sessionId: event.sessionId,
                sessionGeneration: event.sessionGeneration,
                title: agentName,
                subtitle: L10n.tr("agent.notification.stopped"),
                createdAt: now(),
                duration: 4
            )
        case .sessionUnknown:
            return PocketNotchNotification(
                source: .agent,
                type: .unknown,
                agentId: event.agentId,
                sessionId: event.sessionId,
                sessionGeneration: event.sessionGeneration,
                title: agentName,
                subtitle: L10n.tr("agent.notification.unknown"),
                createdAt: now(),
                duration: 4
            )
        case .sessionStopRequested:
            return PocketNotchNotification(
                source: .agent,
                type: .stopped,
                agentId: event.agentId,
                sessionId: event.sessionId,
                sessionGeneration: event.sessionGeneration,
                title: agentName,
                subtitle: L10n.tr("agent.notification.stopping"),
                createdAt: now(),
                duration: 3
            )
        case .sessionEnded:
            return PocketNotchNotification(
                source: .agent,
                type: type,
                agentId: event.agentId,
                sessionId: event.sessionId,
                sessionGeneration: event.sessionGeneration,
                title: agentName,
                subtitle: L10n.tr("agent.notification.ended"),
                createdAt: now(),
                duration: 4
            )
        }
    }
}

extension NotificationType {
    /// 从统一 Agent 事件类型映射。
    init(from eventType: AgentEventType) {
        switch eventType {
        case .sessionCreated: self = .sessionCreated
        case .sessionRunning: self = .sessionCreated
        case .sessionWaitingApproval: self = .waitingApproval
        case .sessionCompleted: self = .completed
        case .sessionFailed: self = .failed
        case .sessionStopped: self = .stopped
        case .sessionUnknown: self = .unknown
        case .sessionStopRequested: self = .stopped
        case .sessionEnded: self = .unknown
        }
    }
}
