import Foundation

/// 面向显示层的 Agent 状态。
///
/// 设计文档第七章：不要把 `SessionState` 直接交给 DisplayScheduler。
/// `AgentAwareness` 必须根据所有 Session 计算一个面向显示层的聚合状态。
public struct AgentDisplayState: Identifiable, Hashable, Sendable {
    public let agentId: String
    public let hasRunningSession: Bool
    public let runningSessionCount: Int
    public let hasAttentionSession: Bool
    /// 是否存在无法确认健康（suspected）的 Session。
    public let hasSuspectedSession: Bool
    /// 是否存在已失去连接证据（lost）的 Session。
    public let hasLostSession: Bool
    /// 最近一次 Session 更新（用于轮换排序）。
    public let updatedAt: Date

    public var id: String { agentId }

    public init(
        agentId: String,
        hasRunningSession: Bool,
        runningSessionCount: Int,
        hasAttentionSession: Bool,
        hasSuspectedSession: Bool = false,
        hasLostSession: Bool = false,
        updatedAt: Date
    ) {
        self.agentId = agentId
        self.hasRunningSession = hasRunningSession
        self.runningSessionCount = runningSessionCount
        self.hasAttentionSession = hasAttentionSession
        self.hasSuspectedSession = hasSuspectedSession
        self.hasLostSession = hasLostSession
        self.updatedAt = updatedAt
    }
}
