import Foundation
import Combine

/// 支持的 Agent 集合。
public enum AgentKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case claudeCode
    case codex
    case gemini
    case opencode
    case qoder
    case hermes

    public var id: String { rawValue }

    public var agentId: String {
        switch self {
        case .claudeCode: "claude-code"
        case .codex: "codex"
        case .gemini: "gemini"
        case .opencode: "opencode"
        case .qoder: "qoder"
        case .hermes: "hermes"
        }
    }

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .opencode: "OpenCode"
        case .qoder: "Qoder"
        case .hermes: "Hermes"
        }
    }
}

/// 当前支持的 Agent 注册表。
///
/// 设计文档 4.1：维护所有 AgentAdapter。本阶段以 `PlaceholderAgentAdapter` 占位，
/// 正式 Hook 实现可替换对应 kind。
@MainActor
public final class AgentRegistry: ObservableObject {
    @Published public private(set) var adapters: [AgentAdapter] = []

    public init() {
        registerDefaultAdapters()
    }

    public func register(_ adapter: AgentAdapter) {
        guard !adapters.contains(where: { $0.agentId == adapter.agentId }) else { return }
        adapters.append(adapter)
    }

    public func adapter(for agentId: String) -> AgentAdapter? {
        adapters.first { $0.agentId == agentId }
    }

    public func startAll() {
        adapters.forEach { $0.start() }
    }

    public func stopAll() {
        adapters.forEach { $0.stop() }
    }

    private func registerDefaultAdapters() {
        for kind in AgentKind.allCases {
            register(PlaceholderAgentAdapter(agentId: kind.agentId, displayName: kind.displayName))
        }
    }
}