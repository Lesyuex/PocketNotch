import Foundation

/// Claude Code Hook 适配器。
///
/// Claude 的 Hook 事件把类型放在 `hook_event_name` 外层，
/// 详细内容在内层 `payload` / `tool_input` / `tool_response`。这里先把
/// 外层 envelope 拍平，再交给统一归一化。
public struct ClaudeAdapter: AgentAdapter {
    public let agentID = "claude"

    public init() {}

    public func normalize(_ payload: [String: Any]) throws -> AgentEvent {
        var flattened = payload
        if let mapped = ClaudeAdapter.mapHookEventName(payload["hook_event_name"] ?? payload["type"]) {
            flattened["event"] = mapped
        }
        for envelopeKey in ["payload", "tool_response", "tool_input", "status"] {
            if let inner = payload[envelopeKey] as? [String: Any] {
                flattened.merge(inner) { _, new in new }
            }
        }
        if let tool = payload["tool_name"] as? String {
            flattened["tool"] = tool
        }
        return try AgentEventNormalizer.normalize(agentID: agentID, payload: flattened)
    }

    /// 把 Claude 的 hook 阶段名映射为统一事件类型名（非 `EventType.rawValue` 用 snake 补差）。
    private static func mapHookEventName(_ value: Any?) -> String? {
        guard let name = value as? String else { return nil }
        switch name.lowercased() {
        case "notification.session_start", "session_start": return "sessionStart"
        case "session_end": return "sessionEnd"
        case "agent_start", "session_start_agent": return "agentStart"
        case "pre_tool_use": return "toolStart"
        case "post_tool_use": return "toolEnd"
        case "pre_compact", "thinking": return "thinking"
        case "user_approval_prompt", "permission_prompt": return "waitingApproval"
        case "stop", "completed": return "completed"
        case "error", "abort": return "failed"
        default: return nil
        }
    }
}
