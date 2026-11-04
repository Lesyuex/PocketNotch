import Foundation
import Combine
import os

/// Agent 感知中枢。
///
/// 职责（设计文档第四、七、八、九章 + 生命周期管理优化）：
/// - 接收统一 `AgentEvent`，更新 `SessionStore`（事件驱动状态）。
/// - 通过 `LifecycleWatchdog` + 多信号 Runtime 健康评估兜底（「无事件 ≠ 没运行」）。
/// - 依据 Session 状态计算 `AgentDisplayState`（面向显示层）。
/// - 对外提供 `activeAgents()`（Agent Display Pool）与轮换顺序。
///
/// 不做的事：不直接操作 PocketNotch UI，不决定具体 priority 数值。
@MainActor
public final class AgentAwareness: ObservableObject {
    @Published public private(set) var sessionStore: SessionStore
    @Published public private(set) var runtimeStore: RuntimeStore
    @Published public private(set) var displayStates: [String: AgentDisplayState] = [:]
    public var eventsPublisher: AnyPublisher<AgentEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    /// 事件更新后的回调（供 Notification 等下游订阅，与业务解耦）。
    public var onEvent: ((AgentEvent) -> Void)?

    public let stateManager: SessionStateManager
    public let watchdog: LifecycleWatchdog
    public let lifecycleCoordinator: LifecycleCoordinator
    private let now: () -> Date
    private let eventSubject = PassthroughSubject<AgentEvent, Never>()
    private let logger = Logger(subsystem: "PocketNotch", category: "AgentAwareness")

    public init(
        sessionStore: SessionStore? = nil,
        runtimeStore: RuntimeStore? = nil,
        stateManager: SessionStateManager? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        let resolvedStore = sessionStore ?? SessionStore(now: now)
        let resolvedRuntimeStore = runtimeStore ?? RuntimeStore()
        self.sessionStore = resolvedStore
        self.runtimeStore = resolvedRuntimeStore
        self.stateManager = stateManager ?? SessionStateManager(store: resolvedStore, now: now)
        self.now = now

        // 组装多信号健康评估 + 看门狗。
        let processProbe = AgentProcessProbe(processCommand: SystemProcessCommand())
        let evaluator = HealthEvaluator(now: now)
        let stateMachine = SessionStateMachine(now: now)
        let watchdog = LifecycleWatchdog(
            sessionStore: resolvedStore,
            runtimeStore: resolvedRuntimeStore,
            evaluator: evaluator,
            stateMachine: stateMachine,
            processProbe: processProbe,
            now: now
        )
        self.watchdog = watchdog

        // 冷启动发现 + 对账。
        let scanner = PythonAgentProcessScanner(now: now)
        let registry = FileRuntimeRegistry()
        let discovery = RuntimeDiscovery(scanner: scanner, registry: registry, now: now)
        let reconciliation = Reconciliation(now: now)
        self.lifecycleCoordinator = LifecycleCoordinator(
            sessionStore: resolvedStore,
            runtimeStore: resolvedRuntimeStore,
            watchdog: watchdog,
            discovery: discovery,
            reconciliation: reconciliation
        )

        // 状态变更 → 重算展示（此时 self 已完全初始化）。
        self.watchdog.onSessionStateChanged = { [weak self] agentId in
            self?.recompute(for: agentId)
        }
    }

    // MARK: - Ingest

    /// 应用一条事件并重算显示状态。幂等。
    public func ingest(_ event: AgentEvent) {
        logger.info("INGEST agent=\(event.agentId, privacy: .public) session=\(event.sessionId, privacy: .public) type=\(event.type.rawValue, privacy: .public) origin=\(event.originType ?? "", privacy: .public) pid=\(event.pid ?? 0)")
        // 原始事件始终发布给生命周期协调器（同步 Runtime 信号），供冷启动对账与 runtime 绑定。
        eventSubject.send(event)
        if let update = stateManager.handle(event) {
            // 有 pid / runtime 时，同步 Runtime 健康信号。
            if let pid = event.pid, pid > 0 {
                touchRuntime(for: update.session, pid: pid, at: event.timestamp)
            }
            recompute(for: update.session.agentId)
            if let emittedEvent = update.emittedEvent {
                onEvent?(emittedEvent)
            }
        }
    }

    // MARK: - Lifecycle

    /// 启动事件采集 + 生命周期管理（watchdog + 冷启动发现对账）。
    public func start() {
        watchdog.start()
        // Coordinator 内部执行「订阅 → 发现 → 对账 → 探测 → Ready」。
        lifecycleCoordinator.start(attachTo: eventsPublisher)
    }

    public func stop() {
        watchdog.stop()
        lifecycleCoordinator.stop()
    }

    /// 手动触发一轮健康扫描（供测试/诊断）。
    public func tickHealth() async {
        await watchdog.scanActiveSessions()
    }

    // MARK: - Display computation

    private func touchRuntime(for session: AgentSession, pid: Int32, at date: Date) {
        if let runtime = runtimeStore.runtime(for: session.id) {
            var mutated = runtime
            if mutated.sessionId == nil || mutated.pid != pid {
                mutated.bind(sessionId: session.id, pid: pid, at: date)
            }
            mutated.asAlive(at: date)
            runtimeStore.upsert(mutated)
        } else if session.currentRuntimeId != nil {
            // 已有 runtime id 但未找到，尝试按 id 匹配。
            if let runtime = runtimeStore.runtime(id: session.currentRuntimeId!) {
                var mutated = runtime
                mutated.bind(sessionId: session.id, pid: pid, at: date)
                mutated.asAlive(at: date)
                runtimeStore.upsert(mutated)
            }
        }
    }

    private func recompute(for agentId: String) {
        let sessions = sessionStore.sessions(for: agentId)
        let running = sessions.filter { $0.state == .running }
        let hasAttention = sessions.contains { $0.state.needsAttention }
        let hasSuspected = sessions.contains { $0.state == .suspected }
        let hasLost = sessions.contains { $0.state == .lost }
        let lastUpdate = sessions.map(\.updatedAt).max() ?? now()

        // lost 是终态（isTerminal），表示已无运行证据且超过容忍超时。
        // 不应再让 Agent 留在 Display Pool 中，否则调度器会持续产出 Agent 决策，
        // 导致常驻内容（媒体/股票/天气）一直被让位、宠物动画持续播放。
        // 仅包含 running + suspected 的非终态会话才属于 Display Pool。
        let hasActiveSession = !running.isEmpty || hasSuspected

        if !hasActiveSession && !hasAttention && !hasLost {
            // 该 Agent 已无任何可感知 Session，移除出池。
            displayStates.removeValue(forKey: agentId)
            return
        }

        displayStates[agentId] = AgentDisplayState(
            agentId: agentId,
            hasRunningSession: hasActiveSession,
            runningSessionCount: running.count
                + sessions.filter { $0.state == .suspected }.count,
            hasAttentionSession: hasAttention,
            hasSuspectedSession: hasSuspected,
            hasLostSession: hasLost,
            updatedAt: lastUpdate
        )
    }

    /// Agent Display Pool：只要存在 Running（含 suspected）Session 就进入。
    /// 保持稳定顺序（agentId 升序）以便轮换调度。
    public func activeAgents() -> [AgentDisplayState] {
        displayStates.values
            .filter(\.hasRunningSession)
            .sorted { $0.agentId < $1.agentId }
    }

    public func displayState(for agentId: String) -> AgentDisplayState? {
        displayStates[agentId]
    }

    /// 是否有任何 Agent 处于感知状态（含仅 attention 但无 running）。
    public var hasAnyPerceivedAgent: Bool {
        !displayStates.isEmpty
    }

    /// 清除全部感知状态（Agent 感知关闭/重置时调用）。
    /// 避免残留的 Running Session 持续占据 Agent Display Pool，阻塞常驻内容展示。
    public func clear() {
        watchdog.stop()
        lifecycleCoordinator.stop()
        stateManager.stop()
        sessionStore.clear()
        runtimeStore.clear()
        displayStates.removeAll()
    }
}
