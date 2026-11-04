import Foundation

/// 统一后的 Agent 事件类型。
///
/// 设计文档第五章：AgentEvent 是「发生了什么」，不是 UI 消息。
/// 一个事件可以同时产生 Notification 并更新 SessionState。
public enum AgentEventType: String, Codable, CaseIterable, Hashable, Sendable {
    case sessionCreated
    case sessionRunning
    case sessionWaitingApproval
    case sessionCompleted
    case sessionFailed
    case sessionStopped
    case sessionUnknown
    case sessionStopRequested
    case sessionEnded
}

/// 统一事件模型：所有 Agent Adapter 最终都转换成它，交给 AgentAwareness。
public struct AgentEvent: Codable, Identifiable, Hashable, Sendable {
    public let agentId: String
    public let sessionId: String
    public let type: AgentEventType
    public let timestamp: Date
    public let pid: Int32?
    public let parentPID: Int32?
    public let exitCode: Int32?
    public let message: String?
    public let originType: String?
    public let sessionGeneration: Int?
    /// 仅更新会话状态，不产生工作展示或瞬时通知。
    public let isStateOnly: Bool

    /// 事件幂等 id；同一「事实」重复上报时应使用相同 id（由上层 Normalizer 提供）。
    public let id: String

    public init(
        id: String = UUID().uuidString,
        agentId: String,
        sessionId: String,
        type: AgentEventType,
        timestamp: Date,
        pid: Int32? = nil,
        parentPID: Int32? = nil,
        exitCode: Int32? = nil,
        message: String? = nil,
        originType: String? = nil,
        sessionGeneration: Int? = nil,
        isStateOnly: Bool = false
    ) {
        self.id = id
        self.agentId = agentId
        self.sessionId = sessionId
        self.type = type
        self.timestamp = timestamp
        self.pid = pid
        self.parentPID = parentPID
        self.exitCode = exitCode
        self.message = message
        self.originType = originType
        self.sessionGeneration = sessionGeneration
        self.isStateOnly = isStateOnly
    }
}
