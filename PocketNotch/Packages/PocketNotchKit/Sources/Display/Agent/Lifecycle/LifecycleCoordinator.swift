import Foundation
import Combine

/// 生命周期协调器：把事件订阅、冷启动发现、对账、探测、看门狗串成一个可用生命周期。
///
/// 设计文档第 15、18 章的关键流程（必须「先订阅再扫描」以避免竞态）：
/// ```
/// Subscribe Events → Runtime Discovery → Reconciliation → Health Probe → Ready
/// ```
/// PocketNotch 启动前已存在的外部 Agent Session 在这里被「补建」并纳入管理。
@MainActor
public final class LifecycleCoordinator: ObservableObject {
    public let sessionStore: SessionStore
    public let runtimeStore: RuntimeStore
    public let watchdog: LifecycleWatchdog
    public let discovery: RuntimeDiscovery
    public let reconciliation: Reconciliation

    /// 是否已完成冷启动对账。
    @Published public private(set) var isReady = false

    private var cancellables = Set<AnyCancellable>()
    private var reconcileTask: Task<Void, Never>?

    public init(
        sessionStore: SessionStore,
        runtimeStore: RuntimeStore,
        watchdog: LifecycleWatchdog,
        discovery: RuntimeDiscovery,
        reconciliation: Reconciliation
    ) {
        self.sessionStore = sessionStore
        self.runtimeStore = runtimeStore
        self.watchdog = watchdog
        self.discovery = discovery
        self.reconciliation = reconciliation
    }

    /// 启动整个生命周期管理。
    /// 顺序保证：先订阅事件（由调用方在 ingest 前注入），再发现-对账-探测，最后 Ready。
    public func start(attachTo events: AnyPublisher<AgentEvent, Never>) {
        // 1) 订阅（增量）：事件到达时更新对应 Runtime 与 Session 的活动信号。
        events
            .sink { [weak self] event in
                self?.handle(event)
            }
            .store(in: &cancellables)

        // 2) 发现 + 3) 对账 + 4) 探测（放到下一 tick，保证订阅已建立）。
        reconcileTask?.cancel()
        reconcileTask = Task { [weak self] in
            guard let self else { return }
            // 延迟 2 秒确保 App 启动阶段不占用主线程（订阅已建立，增量事件不会丢失）。
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await self.performReconciliation()
            self.isReady = true
        }
    }

    public func stop() {
        reconcileTask?.cancel()
        cancellables.removeAll()
        watchdog.stop()
        isReady = false
    }

    /// 立即执行一次（冷启动或手动）对账。async 版本，因为内部调用 `watchdog.scanActiveSessions()` 是 async。
    public func performReconciliation() async {
        let discovered = await Task.detached(priority: .utility) { [discovery] in
            discovery.scanRunningRuntimes()
        }.value
        let plan = reconciliation.reconcile(
            discovered: discovered,
            knownSessions: sessionStore.sessions
        )

        for created in plan.toCreate {
            guard sessionStore.session(id: created.sessionId) == nil else { continue }
            var session = AgentSession(
                id: created.sessionId,
                agentId: created.agentId,
                // 仅凭进程表扫描到进程 ≠ 正在干活：先标记 suspected（不显示运行），
                // 等 Hook / CPU 增长确认后才升级为 running；空闲进程最终收敛为 lost。
                state: .suspected,
                pid: created.pid,
                lastActivityAt: now(),
                lastEventID: nil,
                createdAt: created.startedAt,
                currentRuntimeId: created.runtimeId,
                attachedAt: created.attachedAt,
                updatedAt: now()
            )
            session.attachRuntime(created.runtimeId, at: created.attachedAt)
            sessionStore.upsert(session)

            let runtime = AgentRuntime(
                runtimeId: created.runtimeId,
                sessionId: created.sessionId,
                agentId: created.agentId,
                pid: created.pid,
                commandLine: nil,
                startedAt: created.startedAt,
                lastProbeAt: now(),
                health: .stale,
                signals: RuntimeSignals()
            )
            runtimeStore.upsert(runtime)
            discovery.persist(DiscoveredRuntime(
                agentId: created.agentId,
                pid: created.pid,
                ppid: 0,
                commandLine: "",
                startedAt: created.startedAt
            ))
        }

        for bind in plan.toBindRuntime {
            guard var session = sessionStore.session(id: bind.sessionId) else { continue }
            session.attachRuntime(bind.runtimeId, at: now())
            session.updatePID(bind.pid, at: now())
            sessionStore.upsert(session)

            if var runtime = runtimeStore.runtime(id: bind.runtimeId) {
                runtime.bind(sessionId: bind.sessionId, pid: bind.pid, at: now())
                runtimeStore.upsert(runtime)
            } else {
                runtimeStore.upsert(makeRuntime(from: bind, agentId: session.agentId))
            }
        }

        // 缺失 → 进入 lost（推进状态机），交由 Watchdog 后续收敛。
        for sessionID in plan.missingSessionIDs {
            guard var session = sessionStore.session(id: sessionID),
                  !session.state.isTerminal else { continue }
            let previous = session.state
            session.updateState(.lost, at: now())
            sessionStore.upsert(session)
            if previous != .lost {
                reconciles.append(session.agentId)
            }
        }

        // 对账完成后立即跑一轮 Watchdog 修正状态（async）。
        await watchdog.scanActiveSessions()

        // 冷启动对账完成。
        isReady = true
    }

    // MARK: - Event handling

    /// 事件到达：更新对应 Session，并驱动 Runtime 健康信号。
    private func handle(_ event: AgentEvent) {
        let signal = RuntimeSignals(lastHookAt: event.timestamp)
        var session = sessionStore.session(id: event.sessionId)
        if let pid = event.pid, pid > 0, session?.pid != pid {
            session?.updatePID(pid, at: event.timestamp)
        }
        if var session {
            if let runtime = runtimeStore.runtime(for: session.id) {
                var mutated = runtime
                mutated.asAlive(at: event.timestamp, signals: signal)
                runtimeStore.upsert(mutated)
            }
            sessionStore.upsert(session)
        }
    }

    private var reconciles: [String] = []

    private func now() -> Date { Date() }

    private func makeRuntime(from bind: ReconcileBindRuntime, agentId: String) -> AgentRuntime {
        AgentRuntime(
            runtimeId: bind.runtimeId,
            sessionId: bind.sessionId,
            agentId: agentId,
            pid: bind.pid,
            startedAt: bind.startedAt,
            lastProbeAt: now(),
            health: .alive
        )
    }
}
