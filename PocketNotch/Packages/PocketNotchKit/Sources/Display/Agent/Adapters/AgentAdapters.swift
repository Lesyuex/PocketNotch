import Foundation

/// 为六种 Agent 提供的占位适配器工厂。
///
/// 设计文档第二十三章：本阶段不实现各家 Hook 的具体细节，
/// 因此统一返回 `PlaceholderAgentAdapter`，并通过 `AgentRegistry` 注册。
/// 后续每个 Agent 接入时，只需把对应工厂替换为真实适配器即可，Display 层无感知。
public enum AgentAdapters {
    @MainActor
    public static func make(for kind: AgentKind) -> any AgentAdapter {
        PlaceholderAgentAdapter(agentId: kind.agentId, displayName: kind.displayName)
    }
}