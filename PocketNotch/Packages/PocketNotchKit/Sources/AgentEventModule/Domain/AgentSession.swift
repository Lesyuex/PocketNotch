import Foundation

/// 一次 Agent 会话的聚合描述。
///
/// Phase 1 只负责记录会话及其事件序列，不负责排序、显示或调度。
public struct AgentSession: Codable, Sendable {
    public let id: String
    public let agent: String
    public private(set) var events: [AgentEvent]
    public let startTime: Date

    public var lastTransitionAt: Date { events.last?.timestamp ?? startTime }

    public init(id: String, agent: String, events: [AgentEvent] = [], startTime: Date) {
        self.id = id
        self.agent = agent
        self.events = events
        self.startTime = startTime
    }

    public mutating func append(_ event: AgentEvent) {
        events.append(event)
    }
}