import Foundation

/// 根据上报的 Agent 名称选择对应适配器。
public enum AgentAdapterFactory {
    /// 把各类别名归一化为稳定 agent id。
    public static func canonicalID(_ agent: String?) -> String {
        guard let agent else { return "unknown" }
        let raw = agent.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "cli", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        if raw.contains("claude") { return "claude" }
        if raw.contains("codex") { return "codex" }
        if raw.contains("gemini") { return "gemini" }
        return raw.isEmpty ? "unknown" : raw
    }

    public static func adapter(for agent: String?) -> AgentAdapter {
        let id = canonicalID(agent)
        switch id {
        case "claude": return ClaudeAdapter()
        case "codex": return CodexAdapter()
        case "gemini": return GeminiAdapter()
        default: return GenericAdapter(agentID: id)
        }
    }
}