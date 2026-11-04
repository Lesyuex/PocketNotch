import Foundation

/// Gemini CLI 上报事件适配器。
///
/// Gemini 主要以上下文流式事件上报，类型字段为 `event` / `step`，
/// 文件操作信息在 `changes` / `skill` 中描述。
public struct GeminiAdapter: AgentAdapter {
    public let agentID = "gemini"

    public init() {}

    public func normalize(_ payload: [String: Any]) throws -> AgentEvent {
        var flattened = payload
        if let mapped = GeminiAdapter.mapStepEvent(payload["step"]) {
            flattened["event"] = mapped
        }
        for envelopeKey in ["changes", "tool_data", "execution"] {
            if let inner = payload[envelopeKey] as? [String: Any] {
                flattened.merge(inner) { _, new in new }
            }
        }
        return try AgentEventNormalizer.normalize(agentID: agentID, payload: flattened)
    }

    private static func mapStepEvent(_ value: Any?) -> String? {
        guard let name = value as? String else { return nil }
        switch name.lowercased() {
        case "initial", "initialize": return "sessionStart"
        case "reasoning", "thinking", "replan": return "thinking"
        case "filechange", "change_file", "edit", "generating": return "toolStart"
        case "execution", "command", "running_command": return "commandStart"
        case "await", "ask_for_permission": return "waitingApproval"
        case "completion", "done", "complete": return "completed"
        case "fail", "error": return "failed"
        default: return nil
        }
    }
}