import Foundation

/// 对账操作集：描述一次 Reveal 后需要做的 Session/Runtime 变更。
public struct ReconciliationPlan: Sendable {
    /// 需要新建（启动前已存在、PocketNotch 尚未感知）的 Session。
    public let toCreate: [ReconcileNewSession]
    /// 需要更新 runtime 关联的既有 Session。
    public let toBindRuntime: [ReconcileBindRuntime]
    /// 需要标记为 lost（PocketNotch 已知但在 Runtime 世界已消失、且无终态证据）的 Session。
    public let missingSessionIDs: [String]

    public init(
        toCreate: [ReconcileNewSession] = [],
        toBindRuntime: [ReconcileBindRuntime] = [],
        missingSessionIDs: [String] = []
    ) {
        self.toCreate = toCreate
        self.toBindRuntime = toBindRuntime
        self.missingSessionIDs = missingSessionIDs
    }

    public var isEmpty: Bool {
        toCreate.isEmpty && toBindRuntime.isEmpty && missingSessionIDs.isEmpty
    }
}

/// 一条需要新建的 Session（由发现到的外部 Runtime 派生）。
public struct ReconcileNewSession: Sendable {
    public let sessionId: String
    public let agentId: String
    public let runtimeId: String
    public let pid: Int32
    public let startedAt: Date
    /// PocketNotch attach 该 Session 的时间。与 Agent 真实启动时间（startedAt）分离。
    public let attachedAt: Date

    public init(sessionId: String, agentId: String, runtimeId: String, pid: Int32, startedAt: Date, attachedAt: Date) {
        self.sessionId = sessionId
        self.agentId = agentId
        self.runtimeId = runtimeId
        self.pid = pid
        self.startedAt = startedAt
        self.attachedAt = attachedAt
    }
}

/// 一条需要绑定到既有 Session 的 Runtime 更新。
public struct ReconcileBindRuntime: Sendable {
    public let sessionId: String
    public let runtimeId: String
    public let pid: Int32
    public let startedAt: Date

    public init(sessionId: String, runtimeId: String, pid: Int32, startedAt: Date) {
        self.sessionId = sessionId
        self.runtimeId = runtimeId
        self.pid = pid
        self.startedAt = startedAt
    }
}

/// Reconciliation：把「当前 Runtime 世界」与「PocketNotch 已知 Session 世界」对账。
///
/// 设计文档第 19 章：对账在冷启动 / 定时刷新时执行。
/// - Runtime 世界有、PocketNotch 没有 → 新建 Session（用进程的 startedAt，而非 attach 时间）。
/// - Runtime 世界的进程可归属到某个已知 Session（按 agentId + pid 匹配）→ 绑定 Runtime。
/// - PocketNotch 有、Runtime 世界没有、且该 Session 无终态证据 → 标记为 lost（进入清理流程）。
public struct Reconciliation: Sendable {
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    /// 计算对账计划。
    /// - Parameters:
    ///   - discovered: 冷启动/扫描发现到的运行中 Runtime。
    ///   - knownSessions: PocketNotch 当前已知的 Session 快照。
    public func reconcile(
        discovered: [DiscoveredRuntime],
        knownSessions: [AgentSession]
    ) -> ReconciliationPlan {
        let attachDate = now()

        // 1) 已知 agent 的运行 pid，用于判断已知 Session 是否仍存活。
        var aliveByAgentPID: [String: Set<Int32>] = [:]
        var byAgent: [String: [DiscoveredRuntime]] = [:]
        for runtime in discovered {
            aliveByAgentPID[runtime.agentId, default: []].insert(runtime.pid)
            byAgent[runtime.agentId, default: []].append(runtime)
        }

        // 2) 新建：发现的 Runtime 中，无法归属到任何已知 Session 的。
        var created: [ReconcileNewSession] = []
        // 记录已归属的 runtime id，避免无意义地重复新建。
        var seenPIDs = Set<Int32>()
        for runtime in discovered where !seenPIDs.contains(runtime.pid) {
            let isKnown = knownSessions.contains { s in
                s.agentId == runtime.agentId && s.pid == runtime.pid
            }
            // A living Codex process may be an idle thread. Its rollout log is the only
            // reliable source for the stable session ID and active-vs-idle state.
            if !isKnown && runtime.agentId != "codex" {
                created.append(ReconcileNewSession(
                    sessionId: makeSessionID(agentId: runtime.agentId, pid: runtime.pid),
                    agentId: runtime.agentId,
                    runtimeId: runtimeID(agentId: runtime.agentId, pid: runtime.pid),
                    pid: runtime.pid,
                    startedAt: runtime.startedAt,
                    attachedAt: attachDate
                ))
            }
            seenPIDs.insert(runtime.pid)
        }

        // 3) 绑定 runtime：已知 Session 若已在 Runtime 世界存活，补绑 runtime（当尚未绑定或 pid 变化时）。
        var toBind: [ReconcileBindRuntime] = []
        for session in knownSessions where !session.state.isTerminal {
            if let candidates = byAgent[session.agentId] {
                // 匹配：pid 相同，或该 agent 下只有这一个运行进程。
                if let match = candidates.first(where: { $0.pid == session.pid })
                    ?? (candidates.count == 1 ? candidates.first : nil) {
                    if session.currentRuntimeId == nil || session.pid != match.pid {
                        toBind.append(ReconcileBindRuntime(
                            sessionId: session.id,
                            runtimeId: runtimeID(agentId: match.agentId, pid: match.pid),
                            pid: match.pid,
                            startedAt: match.startedAt
                        ))
                    }
                }
            }
        }

        // 4) 缺失：已知的非终态 Session，在其 agent 的发现集合中找不到对应进程，且无明确终态 → lost。
        var missing: [String] = []
        for session in knownSessions where !session.state.isTerminal {
            let agentAlive = aliveByAgentPID[session.agentId] ?? []
            let hasAgentProcess = discovered.contains { $0.agentId == session.agentId }
            // 我才能判断「该 agent 完全无进程」且该 session 也非 waiting（waiting 可能只是探不到）。
            let aliveForThisSession = session.pid.map { agentAlive.contains($0) } ?? hasAgentProcess
            if !aliveForThisSession && session.state != .waitingApproval {
                missing.append(session.id)
            }
        }

        return ReconciliationPlan(
            toCreate: created,
            toBindRuntime: toBind,
            missingSessionIDs: missing
        )
    }

    private func makeSessionID(agentId: String, pid: Int32) -> String {
        "runtime-\(agentId)-pid\(pid)"
    }

    public func runtimeID(agentId: String, pid: Int32) -> String {
        "\(agentId)-pid\(pid)"
    }
}
