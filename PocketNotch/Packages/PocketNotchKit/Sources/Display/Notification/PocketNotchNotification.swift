import Foundation

/// 瞬时通知的类型。第一版对应 Session 生命周期事件。
public enum NotificationType: String, Codable, Hashable, Sendable {
    case sessionCreated
    case waitingApproval
    case completed
    case failed
    case stopped
    case unknown
}

/// 通知来源。
public enum NotificationSource: String, Codable, Hashable, Sendable {
    case agent
    case system
    case other
}

/// 一条瞬时通知。
///
/// 设计文档第十、十一章：Notification 不是业务状态，只是对状态变化的一次瞬时反馈。
/// 它消失绝不能改变 Agent / Session 的真实状态。
public struct PocketNotchNotification: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let source: NotificationSource
    public let type: NotificationType
    public let agentId: String?
    public let sessionId: String?
    public let sessionGeneration: Int?
    public let title: String
    public let subtitle: String?
    public let createdAt: Date
    /// 展示时长；结束后由 Scheduler 重新计算 Display，而非恢复历史 UI。
    public let duration: TimeInterval

    public init(
        id: UUID = UUID(),
        source: NotificationSource,
        type: NotificationType,
        agentId: String? = nil,
        sessionId: String? = nil,
        sessionGeneration: Int? = nil,
        title: String,
        subtitle: String? = nil,
        createdAt: Date,
        duration: TimeInterval
    ) {
        self.id = id
        self.source = source
        self.type = type
        self.agentId = agentId
        self.sessionId = sessionId
        self.sessionGeneration = sessionGeneration
        self.title = title
        self.subtitle = subtitle
        self.createdAt = createdAt
        self.duration = duration
    }

    public var expiresAt: Date { createdAt.addingTimeInterval(duration) }

    /// 该通知是否需要额外的交互打断语义。
    ///
    /// 所有通知都会抢占常驻内容；此属性仅保留给需要区分等待授权/失败等
    /// 交互语义的调用方，不再决定通知是否进入展示调度。
    public var isInterrupting: Bool {
        type == .waitingApproval || type == .failed
    }
}
