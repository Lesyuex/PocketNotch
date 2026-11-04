import Foundation

/// Agent 适配器契约。
///
/// 设计文档 4.1：AgentAdapter 负责解决「如何从具体 Agent 获取事件」，
/// 不能把具体 Agent 的 Hook / CLI / IPC 实现渗透到 PocketNotch Display 层。
/// 本阶段只定义数据流契约与事件流抽象，不实现各家 Hook 细节（见设计文档第二十三章）。
@MainActor
public protocol AgentAdapter: Identifiable, Sendable {
    /// 稳定 agent 标识，如 `claude-code`、`codex`。
    var agentId: String { get }
    /// 展示名，如 "Claude Code"。
    var displayName: String { get }
    /// 启动采集（可空实现，本阶段不要求具体 Hook）。
    func start()
    /// 停止采集。
    func stop()
    /// 统一事件流。Adapters 必须把私有事件归一化为 `AgentEvent`。
    func events() -> AsyncStream<AgentEvent>
}

public extension AgentAdapter {
    var id: String { agentId }
    func start() {}
    func stop() {}
}

/// 未实现具体 Hook 的占位适配器（Claude / Codex / Gemini / OpenCode / Qoder / Hermes）。
/// 通过手动 `push(_:)` 喂入归一化事件，便于阶段一的数据流验证。
@MainActor
public final class PlaceholderAgentAdapter: AgentAdapter {
    public let agentId: String
    public let displayName: String

    private var continuation: AsyncStream<AgentEvent>.Continuation?
    private var stream: AsyncStream<AgentEvent>

    public init(agentId: String, displayName: String) {
        self.agentId = agentId
        self.displayName = displayName
        var continuation: AsyncStream<AgentEvent>.Continuation?
        stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public func events() -> AsyncStream<AgentEvent> {
        stream
    }

    /// 手动注入一条归一化事件（阶段一验证数据流用；正式实现由 Hook 归一化产生）。
    public func push(_ event: AgentEvent) {
        continuation?.yield(event)
    }
}