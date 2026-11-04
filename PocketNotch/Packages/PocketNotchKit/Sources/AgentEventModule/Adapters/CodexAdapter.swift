import Foundation

/// Codex CLI 事件适配器。
///
/// Codex 事件以 `StreamEventType` 形式上报，类型字段多为 `phase` / `type`，
/// 命令信息位于 `payload.command`。这里做一次针对性抽取。
public struct CodexAdapter: AgentAdapter {
    public let agentID = "codex"

    public init() {}

    public func normalize(_ payload: [String: Any]) throws -> AgentEvent {
        var flattened = payload
        if let mapped = CodexAdapter.mapPhaseEvent(payload["phase"]) {
            flattened["event"] = mapped
        }
        if let payloadDict = payload["payload"] as? [String: Any] {
            flattened.merge(payloadDict) { _, new in new }
        }
        if let sessionID = payload["session_id"] as? String {
            flattened["sessionId"] = sessionID
        }
        return try AgentEventNormalizer.normalize(agentID: agentID, payload: flattened)
    }

    private static func mapPhaseEvent(_ value: Any?) -> String? {
        guard let name = value as? String else { return nil }
        switch name.lowercased() {
        case "init", "session_start": return "sessionStart"
        case "session_end", "session_closed": return "sessionEnd"
        case "stop": return "completed"
        case "stop_requested", "terminate_requested": return "stopRequested"
        case "tool_call", "tool_use", "tool_start": return "toolStart"
        case "tool_end", "tool_result": return "toolEnd"
        case "command_start", "run_command", "shell": return "commandStart"
        case "command_end": return "commandEnd"
        case "permission_request", "needs_user_input", "approval": return "waitingApproval"
        case "done", "completed", "finished": return "completed"
        case "error", "failed": return "failed"
        default: return nil
        }
    }
}
