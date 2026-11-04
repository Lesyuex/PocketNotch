import Foundation
import Combine

/// Runtime 的聚合存储：管理所有被观察到的 Agent Runtime。
///
/// 与 `SessionStore` 平行。Session 表示工作会话，Runtime 表示承载会话的实际进程实例。
@MainActor
public final class RuntimeStore: ObservableObject {
    @Published public private(set) var runtimes: [AgentRuntime] = []

    public init() {}

    // MARK: - Mutations

    public func upsert(_ runtime: AgentRuntime) {
        if let index = runtimes.firstIndex(where: { $0.runtimeId == runtime.runtimeId }) {
            runtimes[index] = runtime
        } else {
            runtimes.append(runtime)
        }
    }

    public func remove(_ runtimeId: String) {
        runtimes.removeAll { $0.runtimeId == runtimeId }
    }

    public func removeExpiredDeadRuntimes(olderThan date: Date) {
        runtimes.removeAll { $0.health == .dead && ($0.endAt ?? .distantPast) < date }
    }

    public func clear() {
        runtimes.removeAll()
    }

    // MARK: - Queries

    public func runtime(id: String) -> AgentRuntime? {
        runtimes.first { $0.runtimeId == id }
    }

    public func runtimes(for agentId: String) -> [AgentRuntime] {
        runtimes.filter { $0.agentId == agentId }
    }

    public func runtime(for sessionId: String) -> AgentRuntime? {
        runtimes.first { $0.sessionId == sessionId }
    }
}
