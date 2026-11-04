import Foundation

public enum AgentEventSource: String, Codable, Sendable {
    case rollout
}

/// 被所有 Agent 统一转换后的核心事件模型。
public struct AgentEvent: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let agent: String
    public let sessionId: String
    public let type: EventType
    /// 工具或动作名，如 "Edit"、"Read"。由各 Agent 的 `tool` / `action` / `phase` 字段归一化而来。
    public let action: String?
    public let file: String?
    public let command: String?
    public let message: String?
    /// Hook 运行时继承到的宿主应用名称，例如 `Apple_Terminal` 或 `vscode`。
    public let sourceApplication: String?
    /// Hook 运行时继承到的宿主 bundle ID；仅用于精确匹配正在运行的桌面应用。
    public let sourceBundleIdentifier: String?
    public let pid: Int32?
    public let parentPID: Int32?
    public let exitCode: Int32?
    public let stopRequested: Bool
    /// 事件来源；rollout 的运行态仅用于状态对账，明确的完成/失败仍可触发展示。
    public let source: AgentEventSource?
    public let timestamp: Date

    public init(
        id: String,
        agent: String,
        sessionId: String,
        type: EventType,
        action: String? = nil,
        file: String? = nil,
        command: String? = nil,
        message: String? = nil,
        sourceApplication: String? = nil,
        sourceBundleIdentifier: String? = nil,
        pid: Int32? = nil,
        parentPID: Int32? = nil,
        exitCode: Int32? = nil,
        stopRequested: Bool = false,
        source: AgentEventSource? = nil,
        timestamp: Date
    ) {
        self.id = id
        self.agent = agent
        self.sessionId = sessionId
        self.type = type
        self.action = action
        self.file = file
        self.command = command
        self.message = message
        self.sourceApplication = sourceApplication
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.pid = pid
        self.parentPID = parentPID
        self.exitCode = exitCode
        self.stopRequested = stopRequested
        self.source = source
        self.timestamp = timestamp
    }
}
