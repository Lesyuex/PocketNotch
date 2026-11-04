import Foundation
import Combine

/// Session 的聚合存储：Agent × N Session。
///
/// 职责（设计文档第六、九章）：
/// - 维护每个 Agent 下所有 Session 的生命周期状态。
/// - 幂等应用事件（同一事实重复上报不会产生抖动）。
/// - 对外只提供「按 Agent 聚合的查询」，不直接参与 UI 调度。
@MainActor
public final class SessionStore: ObservableObject {
    @Published public private(set) var sessions: [AgentSession] = []

    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    // MARK: - Mutations

    public func upsert(_ session: AgentSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }

    /// 显式清理某 Agent 的所有 Session（用于退出展示或重置）。
    public func removeAll(for agentId: String) {
        sessions.removeAll { $0.agentId == agentId }
    }

    public func removeExpiredTerminalSessions(olderThan date: Date) {
        sessions.removeAll { $0.state.isTerminal && $0.updatedAt < date }
    }

    public func clear() {
        sessions.removeAll()
    }

    // MARK: - Queries

    public func sessions(for agentId: String) -> [AgentSession] {
        sessions.filter { $0.agentId == agentId }
    }

    public func session(id: String) -> AgentSession? {
        sessions.first { $0.id == id }
    }

    /// 处于 running 状态的 Session 数量。
    public func runningCount(for agentId: String) -> Int {
        sessions(for: agentId).filter { $0.state == .running }.count
    }
}
