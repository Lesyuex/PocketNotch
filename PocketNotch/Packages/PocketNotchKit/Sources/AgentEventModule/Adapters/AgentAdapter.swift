import Foundation

/// 将某家 Agent 的私有事件负载转换为统一 `AgentEvent` 的适配器契约。
public protocol AgentAdapter: Sendable {
    /// 该适配器负责的 Agent 标识（如 `"claude"`、`"codex"`、`"gemini"`）。
    var agentID: String { get }
    /// 把原始负载归一化为统一事件。
    func normalize(_ payload: [String: Any]) throws -> AgentEvent
}

/// 对已按统一模型上报的 Agent 直接透传归一化（opencode / qoder / hermes 等）。
public struct GenericAdapter: AgentAdapter {
    public let agentID: String

    public init(agentID: String) {
        self.agentID = agentID
    }

    public func normalize(_ payload: [String: Any]) throws -> AgentEvent {
        try AgentEventNormalizer.normalize(agentID: agentID, payload: payload)
    }
}