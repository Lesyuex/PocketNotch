import Foundation
import os

/// 周期扫描所有活跃 Session 的多信号生命周期看门狗。
///
/// 设计文档第 12、24 章：Watchdog 的职责不是主动结束 Session，而是——
/// 获取活跃 Session → 查 Runtime → Process Probe → Activity Probe → Health Evaluator
/// → StateMachine → 更新 Session/Runtime 状态。
///
/// ps 进程探测在后台线程执行（`Task.detached`），避免阻塞主线程 UI。
@MainActor
public final class LifecycleWatchdog {
    public struct Config: Sendable {
        public var interval: TimeInterval
        public var processProbeInterval: TimeInterval
        public var deadRuntimeRetention: TimeInterval
        public var terminalSessionRetention: TimeInterval
        public init(
            interval: TimeInterval = 60,
            processProbeInterval: TimeInterval = 60,
            deadRuntimeRetention: TimeInterval = 60,
            terminalSessionRetention: TimeInterval = 30
        ) {
            self.interval = interval
            self.processProbeInterval = processProbeInterval
            self.deadRuntimeRetention = deadRuntimeRetention
            self.terminalSessionRetention = terminalSessionRetention
        }
    }

    /// 状态变更回调（供 AgentAwareness 重算展示状态）。
    public var onSessionStateChanged: ((String) -> Void)?

    private let sessionStore: SessionStore
    private let runtimeStore: RuntimeStore
    private let evaluator: HealthEvaluator
    private let stateMachine: SessionStateMachine
    private let processProbe: AgentProcessProbe
    private let config: Config
    private let now: () -> Date
    private let logger = Logger(subsystem: "PocketNotch", category: "LifecycleWatchdog")
    private var task: Task<Void, Never>?

    public init(
        sessionStore: SessionStore,
        runtimeStore: RuntimeStore,
        evaluator: HealthEvaluator,
        stateMachine: SessionStateMachine,
        processProbe: AgentProcessProbe,
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) {
        self.sessionStore = sessionStore
        self.runtimeStore = runtimeStore
        self.evaluator = evaluator
        self.stateMachine = stateMachine
        self.processProbe = processProbe
        self.config = config
        self.now = now
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(config.interval))
                guard !Task.isCancelled else { break }
                await self.scanActiveSessions()
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// 立即执行一次全量扫描（主要供测试与手动触发）。
    /// ps 探测定时在后台 `Task.detached` 中执行，结果回到主线程更新状态。
    public func scanActiveSessions() async {
        let date = now()
        var touchedAgents: Set<String> = []

        // 收集所有非终态 Session 的快照（在主线程上做，因为 sessionStore 是 @MainActor）。
        let activeSessions = sessionStore.sessions.filter { !$0.state.isTerminal }

        // 并行探测所有活跃 Session 的进程（在后台线程执行 ps 命令）。
        let results = await withTaskGroup(
            of: (String, AgentSession, Bool, Bool).self
        ) { group in
            for session in activeSessions {
                group.addTask { [weak self] in
                    guard let self else { return ("", session, false, false) }
                    let (agentId, session, updated, changed) = await self.evaluate(session: session, at: date)
                    return (agentId, session, updated, changed)
                }
            }
            var collected: [(String, AgentSession, Bool, Bool)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // 在主线程上应用结果。
        for (agentId, updatedSession, _, changedState) in results {
            sessionStore.upsert(updatedSession)
            if changedState {
                touchedAgents.insert(agentId)
                logger.debug("session=\(updatedSession.id, privacy: .public) agent=\(agentId, privacy: .public) -> \(updatedSession.state.rawValue, privacy: .public) via watchdog")
            }
        }

        // 清理过期的死 Runtime。
        runtimeStore.removeExpiredDeadRuntimes(olderThan: date.addingTimeInterval(-config.deadRuntimeRetention))
        sessionStore.removeExpiredTerminalSessions(
            olderThan: date.addingTimeInterval(-config.terminalSessionRetention)
        )

        touchedAgents.forEach { onSessionStateChanged?($0) }
    }

    // MARK: - Evaluation

    /// 对单个 Session 执行一次探测-评估-推进。在后台线程执行（`Task.detached`）。
    /// 返回 `(agentId, 更新后的 Session, 是否有更新, 状态是否改变)`。
    private func evaluate(session: AgentSession, at date: Date) async -> (String, AgentSession, Bool, Bool) {
        var session = session
        var hadUpdates = false
        var changedState = false

        // 1) 找到关联 Runtime；若 session.pid 存在但无 Runtime，补建一个（关联 Hook 观察到的 pid）。
        var runtime = runtimeStore.runtime(for: session.id) ?? runtimeStore.runtime(id: session.currentRuntimeId ?? "")
        if runtime == nil, let pid = session.pid, pid > 0 {
            runtime = makeTransientRuntime(session: session, pid: pid, at: date)
            runtimeStore.upsert(runtime!)
            session.attachRuntime(runtime!.runtimeId, at: date)
            hadUpdates = true
        }

        // 2) 进程探测（在后台线程执行 ps 命令）。
        var signals = runtime?.signals ?? RuntimeSignals(lastHookAt: session.lastHookEventAt)
        signals.lastHookAt = session.lastHookEventAt

        // 在后台线程执行 ps 探测。
        let probeResult: ProcessProbeResult
        if let runtime, let pid = runtime.pid, pid > 0 {
            // 校验可执行名：hook shell 退出后 pid 被复用会误报为存活，
            // 名字不符的进程不视为 Agent 的运行证据。
            let expectedExecutables = AgentExecutableNames.names(for: session.agentId)
            // 用 Task.detached 把 ps 探测推到后台。
            probeResult = await Task.detached { [processProbe, expectedExecutables] in
                processProbe.probe(pid: pid, expectedExecutables: expectedExecutables)
            }.value
        } else {
            probeResult = .dead
        }

        let processAlive = probeResult.isAlive
        if probeResult.hasCPUActivity {
            signals.lastProcessActivityAt = date
        }

        // 3) 综合评估（在主线程上快速执行，不涉及 IO）。
        let verdict = evaluator.evaluate(state: session.state, signals: signals, processAlive: processAlive)

        // 4) 更新 Runtime 健康。
        if let runtime {
            var mutated = runtime
            switch verdict.level {
            case .alive:
                mutated.asAlive(at: date, signals: signals)
            case .stale:
                mutated.asStale(at: date)
            case .dead:
                mutated.asDead(at: date)
            case .unknown:
                break
            }
            if mutated != runtime {
                runtimeStore.upsert(mutated)
                hadUpdates = true
            }
        }

        // 5) 推进状态机。
        // 无任何信号（nil）时用 attach 时间作活动基准，避免「进程扫描抓到的空闲会话」
        // 永远卡在 suspected：attach 后静默超过容忍时长即收敛为 lost。
        let decisionActivity = signals.lastActivityAt ?? session.attachedAt ?? session.createdAt
        let newState = stateMachine.advance(
            current: session.state,
            verdict: verdict,
            lastActivityAt: decisionActivity
        )
        if newState != session.state {
            changedState = true
            session.updateState(newState, at: date)
        }

        // 更新综合活动时间戳（若进程等活动推进了）。
        if let procActivity = signals.lastProcessActivityAt,
           session.lastActivityAt == nil || procActivity > session.lastActivityAt! {
            session.markRuntimeActivity(at: procActivity)
        }

        return (session.agentId, session, hadUpdates || changedState, changedState)
    }

    /// 为 Hook 观察到的 pid 构造一个临时 Runtime（未在进程表中识别到主进程时）。
    private func makeTransientRuntime(session: AgentSession, pid: Int32, at date: Date) -> AgentRuntime {
        AgentRuntime(
            runtimeId: "hook-\(session.id)-\(pid)",
            sessionId: session.id,
            agentId: session.agentId,
            pid: pid,
            startedAt: session.createdAt,
            lastProbeAt: date,
            signals: RuntimeSignals(lastHookAt: session.lastHookEventAt)
        )
    }
}
