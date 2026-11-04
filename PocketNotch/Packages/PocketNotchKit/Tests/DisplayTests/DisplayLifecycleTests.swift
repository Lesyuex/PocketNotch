import XCTest
import Combine
import Darwin
@testable import Display

/// 可编程的进程命令替身，用于精确控制进程存活 / CPU 活动，以验证多信号评估。
final class FakeProcessCommand: ProcessCommandProviding, @unchecked Sendable {
    var alivePIDs: Set<Int32> = []
    var cpuByPID: [Int32: TimeInterval] = [:]
    var executableByPID: [Int32: String] = [:]
    var parentByPID: [Int32: Int32] = [:]

    func probe(pid: Int32) -> (cpuSeconds: TimeInterval?, alive: Bool) {
        guard alivePIDs.contains(pid) else { return (nil, false) }
        return (cpuByPID[pid], true)
    }

    func executableName(pid: Int32) -> String? { executableByPID[pid] }

    func parentPID(pid: Int32) -> Int32? { parentByPID[pid] }
}

/// 静态扫描器替身，用于冷启动对账测试注入固定的发现结果。
struct StaticAgentProcessScanner: AgentProcessScanner {
    let processes: [DetectedProcess]
    func scan() -> [DetectedProcess] { processes }
}

final class SystemProcessCommandTests: XCTestCase {
    func testProbeReadsCurrentProcessCPUTimeWithoutCorruptingMemory() throws {
        let result = SystemProcessCommand().probe(pid: getpid())

        XCTAssertTrue(result.alive)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(result.cpuSeconds), 0)
    }
}

final class AgentProcessAncestryResolverTests: XCTestCase {
    func testResolvesHookChildToSessionAgentProcess() {
        let fake = FakeProcessCommand()
        fake.executableByPID = [400: "curl", 300: "zsh", 200: "codex", 100: "Terminal"]
        fake.parentByPID = [400: 300, 300: 200, 200: 100]
        let resolver = AgentProcessAncestryResolver(processCommand: fake)

        XCTAssertEqual(
            resolver.resolve(agentId: "codex", pid: 400, parentPID: 300),
            200
        )
    }

    func testDoesNotBindUnrelatedHookProcess() {
        let fake = FakeProcessCommand()
        fake.executableByPID = [400: "curl", 300: "zsh", 100: "Terminal"]
        fake.parentByPID = [400: 300, 300: 100]
        let resolver = AgentProcessAncestryResolver(processCommand: fake)

        XCTAssertNil(resolver.resolve(agentId: "codex", pid: 400, parentPID: 300))
    }

    func testSeparateSessionsResolveToTheirOwnAgentProcesses() {
        let fake = FakeProcessCommand()
        fake.executableByPID = [410: "curl", 210: "codex", 420: "curl", 220: "codex"]
        fake.parentByPID = [410: 210, 420: 220]
        let resolver = AgentProcessAncestryResolver(processCommand: fake)

        XCTAssertEqual(resolver.resolve(agentId: "codex", pid: 410, parentPID: 210), 210)
        XCTAssertEqual(resolver.resolve(agentId: "codex", pid: 420, parentPID: 220), 220)
    }
}

// MARK: - HealthEvaluator

final class HealthEvaluatorTests: XCTestCase {

    func testAliveProcessKeepsRunningRegardlessOfIdle() {
        var now = Date(timeIntervalSince1970: 1000)
        var evaluator = HealthEvaluator(staleAfter: 20, lostAfter: 120, now: { now })
        let verdict = evaluator.evaluate(
            state: .running,
            signals: RuntimeSignals(lastHookAt: now.addingTimeInterval(-1000)),
            processAlive: true
        )
        XCTAssertEqual(verdict.level, .alive)
    }

    func testProcessGoneAfterIdleGoesDead() {
        var now = Date(timeIntervalSince1970: 1000)
        let evaluator = HealthEvaluator(staleAfter: 20, lostAfter: 120, now: { now })
        let verdict = evaluator.evaluate(
            state: .running,
            signals: RuntimeSignals(lastHookAt: now.addingTimeInterval(-200)),
            processAlive: false
        )
        XCTAssertEqual(verdict.level, .dead)
        XCTAssertTrue(verdict.noRuntimeEvidence)
    }

    func testWaitingKeepsAliveEvenWithNoProcess() {
        var now = Date(timeIntervalSince1970: 1000)
        let evaluator = HealthEvaluator(staleAfter: 20, lostAfter: 120, waitingTolerance: 3600, now: { now })
        // 等待 1 小时都 < 容忍时长。
        let verdict = evaluator.evaluate(
            state: .waitingApproval,
            signals: RuntimeSignals(lastHookAt: now.addingTimeInterval(-3500)),
            processAlive: false
        )
        XCTAssertEqual(verdict.level, .alive)
    }

    func testNoSignalAndNoProcessIsUnknown() {
        var now = Date(timeIntervalSince1970: 1000)
        let evaluator = HealthEvaluator(now: { now })
        let verdict = evaluator.evaluate(
            state: .running,
            signals: RuntimeSignals(),
            processAlive: nil
        )
        XCTAssertEqual(verdict.level, .unknown)
    }

    /// 进程仍然存活，即使长时间无 Hook → 保持 alive（进程存在即运行证据，不降级）。
    func testProcessAliveRemainsAliveEvenWhenLongIdle() {
        var now = Date(timeIntervalSince1970: 1000)
        let evaluator = HealthEvaluator(staleAfter: 20, lostAfter: 120, now: { now })
        let verdict = evaluator.evaluate(
            state: .running,
            signals: RuntimeSignals(lastHookAt: now.addingTimeInterval(-200)),
            processAlive: true
        )
        XCTAssertEqual(verdict.level, .alive)
    }
}

// MARK: - SessionStateMachine

final class SessionStateMachineTests: XCTestCase {
    private func makeMachine(now: @escaping @Sendable () -> Date = Date.init) -> SessionStateMachine {
        SessionStateMachine(now: now)
    }

    func testRunningWithAliveStaysRunning() {
        let machine = makeMachine()
        XCTAssertEqual(
            machine.advance(current: .running, verdict: HealthVerdict(level: .alive, idleSeconds: 5, noRuntimeEvidence: false), lastActivityAt: nil),
            .running
        )
    }

    func testRunningStaleMovesToSuspected() {
        let machine = makeMachine()
        XCTAssertEqual(
            machine.advance(current: .running, verdict: HealthVerdict(level: .stale, idleSeconds: 60, noRuntimeEvidence: false), lastActivityAt: nil),
            .suspected
        )
    }

    func testRunningDeadMovesToLost() {
        let machine = makeMachine()
        XCTAssertEqual(
            machine.advance(current: .running, verdict: HealthVerdict(level: .dead, idleSeconds: 200, noRuntimeEvidence: true), lastActivityAt: nil),
            .lost
        )
    }

    func testSuspectedRecoversToRunning() {
        let machine = makeMachine()
        XCTAssertEqual(
            machine.advance(current: .suspected, verdict: HealthVerdict(level: .alive, idleSeconds: nil, noRuntimeEvidence: false), lastActivityAt: nil),
            .running
        )
    }

    func testSuspectedSustainedStaleMovesToLost() {
        var now = Date(timeIntervalSince1970: 1000)
        let machine = makeMachine(now: { now })
        let sustainedIdle = Date(timeIntervalSince1970: 1000 - 400) // > silentTimeout(300)
        XCTAssertEqual(
            machine.advance(
                current: .suspected,
                verdict: HealthVerdict(level: .stale, idleSeconds: 400, noRuntimeEvidence: false),
                lastActivityAt: sustainedIdle
            ),
            .lost
        )
    }

    func testWaitingNeverFailsUnderAnyVerdict() {
        let machine = makeMachine()
        let verdicts: [RuntimeHealthLevel] = [.alive, .stale, .dead, .unknown]
        for level in verdicts {
            XCTAssertEqual(
                machine.advance(
                    current: .waitingApproval,
                    verdict: HealthVerdict(level: level, idleSeconds: 4000, noRuntimeEvidence: true),
                    lastActivityAt: nil
                ),
                .waitingApproval,
                "waitingApproval 不应因无活动而失败：\(level)"
            )
        }
    }

    func testTerminalStateNeverChangedByHealth() {
        let machine = makeMachine()
        let terminals: [SessionState] = [.completed, .failed, .stopped, .lost]
        for terminal in terminals {
            XCTAssertEqual(
                machine.advance(current: terminal, verdict: HealthVerdict(level: .dead, idleSeconds: 999, noRuntimeEvidence: true), lastActivityAt: nil),
                terminal
            )
        }
    }
}

// MARK: - LifecycleWatchdog 集成（多信号推进）

@MainActor
final class LifecycleWatchdogTests: XCTestCase {

    private func makeWatchdog(
        sessionStore: SessionStore,
        runtimeStore: RuntimeStore,
        processCommand: ProcessCommandProviding,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> LifecycleWatchdog {
        LifecycleWatchdog(
            sessionStore: sessionStore,
            runtimeStore: runtimeStore,
            evaluator: HealthEvaluator(now: now),
            stateMachine: SessionStateMachine(now: now),
            processProbe: AgentProcessProbe(processCommand: processCommand),
            now: now
        )
    }

    /// 进程存活但「从未有 Hook 且无 CPU 增长」→ 空闲进程不是运行证据，收敛为 SUSPECTED（不误判 FAILED）。
    func testIdleAliveProcessWithoutWorkEvidenceMovesToSuspected() async {
        var now = Date(timeIntervalSince1970: 1000)
        let store = SessionStore(now: { now })
        let runtimeStore = RuntimeStore()
        let fake = FakeProcessCommand()
        fake.alivePIDs = [123]
        fake.executableByPID = [123: "codex"]

        var session = AgentSession(id: "sA", agentId: "codex", state: .running, pid: 123, lastActivityAt: now.addingTimeInterval(-600), createdAt: now)
        store.upsert(session)

        let watcher = makeWatchdog(sessionStore: store, runtimeStore: runtimeStore, processCommand: fake, now: { now })
        await watcher.scanActiveSessions()

        XCTAssertEqual(store.session(id: "sA")?.state, .suspected)
    }

    /// pid 仍存活但可执行名不是该 Agent（hook shell 退出后 pid 被复用）→
    /// 不视为运行证据 → 已关闭的会话应收敛为 LOST。
    func testAlivePidWithWrongExecutableBecomesLost() async {
        var now = Date(timeIntervalSince1970: 1000)
        let store = SessionStore(now: { now })
        let runtimeStore = RuntimeStore()
        let fake = FakeProcessCommand()
        fake.alivePIDs = [456]
        fake.executableByPID = [456: "bash"]

        var session = AgentSession(id: "sE", agentId: "codex", state: .running, pid: 456, lastActivityAt: now.addingTimeInterval(-300), createdAt: now)
        store.upsert(session)

        let watcher = makeWatchdog(sessionStore: store, runtimeStore: runtimeStore, processCommand: fake, now: { now })
        await watcher.scanActiveSessions()

        XCTAssertEqual(store.session(id: "sE")?.state, .lost)
    }

    /// 长时间无 Hook + 进程已消失 → LOST。
    func testIdleWithDeadProcessBecomesLost() async {
        var now = Date(timeIntervalSince1970: 1000)
        let store = SessionStore(now: { now })
        let runtimeStore = RuntimeStore()
        let fake = FakeProcessCommand() // 无存活进程

        var session = AgentSession(id: "sB", agentId: "claude-code", state: .running, pid: 999_999, lastActivityAt: now.addingTimeInterval(-300), createdAt: now)
        store.upsert(session)

        let watcher = makeWatchdog(sessionStore: store, runtimeStore: runtimeStore, processCommand: fake, now: { now })
        await watcher.scanActiveSessions()

        XCTAssertEqual(store.session(id: "sB")?.state, .lost)
    }

    /// waitingApproval 长时间无 Hook + 无进程 → 仍保持 WAITING（不失败）。
    func testWaitingApprovalSurvivesIdleAndProcessGone() async {
        var now = Date(timeIntervalSince1970: 1000)
        let store = SessionStore(now: { now })
        let runtimeStore = RuntimeStore()
        let fake = FakeProcessCommand()

        var session = AgentSession(id: "sC", agentId: "codex", state: .waitingApproval, pid: 999_999, lastActivityAt: now.addingTimeInterval(-7200), createdAt: now)
        store.upsert(session)

        let watcher = makeWatchdog(sessionStore: store, runtimeStore: runtimeStore, processCommand: fake, now: { now })
        await watcher.scanActiveSessions()

        XCTAssertEqual(store.session(id: "sC")?.state, .waitingApproval)
    }

    /// 进程 CPU 持续增长 → 有真实工作证据，保持 running（并推进活动时间）。
    func testProcessActivityAdvancesActivityAndKeepsRunning() async {
        var now = Date(timeIntervalSince1970: 1000)
        let store = SessionStore(now: { now })
        let runtimeStore = RuntimeStore()
        let fake = FakeProcessCommand()
        fake.alivePIDs = [55]
        fake.cpuByPID = [55: 12]
        fake.executableByPID = [55: "gemini"]

        var session = AgentSession(id: "sD", agentId: "gemini", state: .running, pid: 55, lastActivityAt: now.addingTimeInterval(-600), createdAt: now)
        store.upsert(session)

        let watcher = makeWatchdog(sessionStore: store, runtimeStore: runtimeStore, processCommand: fake, now: { now })
        await watcher.scanActiveSessions() // 首次采样：建立 CPU 基线，不算活动

        // 第二次采样 CPU 增长 → 判定正在干活，保持 running。
        fake.cpuByPID[55] = 14
        await watcher.scanActiveSessions()

        XCTAssertEqual(store.session(id: "sD")?.state, .running)
        XCTAssertGreaterThanOrEqual(store.session(id: "sD")?.lastActivityAt ?? .distantPast, now.addingTimeInterval(-600))
    }
}

// MARK: - Reconciliation

final class ReconciliationTests: XCTestCase {
    func testIdleCodexProcessDoesNotCreateSyntheticRunningSession() {
        let now = Date(timeIntervalSince1970: 3000)
        let reconciliation = Reconciliation(now: { now })
        let runtime = DiscoveredRuntime(
            agentId: "codex",
            pid: 42,
            ppid: 1,
            commandLine: "codex",
            startedAt: Date(timeIntervalSince1970: 2000)
        )

        let plan = reconciliation.reconcile(discovered: [runtime], knownSessions: [])

        XCTAssertTrue(plan.toCreate.isEmpty)
    }


    func testDiscoversNewSessionUsesStartedAtNotAttachTime() {
        var now = Date(timeIntervalSince1970: 10_000)
        let reconciliation = Reconciliation(now: { now })
        let discovered = [
            DiscoveredRuntime(agentId: "claude-code", pid: 777, ppid: 1, commandLine: "claude", startedAt: Date(timeIntervalSince1970: 2000))
        ]
        let plan = reconciliation.reconcile(discovered: discovered, knownSessions: [])
        XCTAssertEqual(plan.toCreate.count, 1)
        XCTAssertEqual(plan.toCreate[0].startedAt, Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(plan.toCreate[0].attachedAt, now) // attachedAt = PocketNotch attach 时间
        XCTAssertTrue(plan.toBindRuntime.isEmpty)
    }

    func testExistingKnownSessionGetsBindRuntime() {
        let now = Date(timeIntervalSince1970: 10_000)
        let reconciliation = Reconciliation(now: { now })
        let session = AgentSession(id: "sX", agentId: "claude-code", state: .running, pid: 777, createdAt: now)
        let discovered = [
            DiscoveredRuntime(agentId: "claude-code", pid: 777, ppid: 1, commandLine: "claude", startedAt: now)
        ]
        let plan = reconciliation.reconcile(discovered: discovered, knownSessions: [session])
        XCTAssertTrue(plan.toCreate.isEmpty)
        XCTAssertEqual(plan.toBindRuntime.count, 1)
        XCTAssertEqual(plan.toBindRuntime[0].sessionId, "sX")
        XCTAssertEqual(plan.toBindRuntime[0].pid, 777)
    }

    func testUnknownNonWaitingSessionMarkedLost() {
        let now = Date(timeIntervalSince1970: 10_000)
        let reconciliation = Reconciliation(now: { now })
        let session = AgentSession(id: "sY", agentId: "codex", state: .running, pid: 777, createdAt: now)
        // 进程已消失（无 running runtime）。
        let plan = reconciliation.reconcile(discovered: [], knownSessions: [session])
        XCTAssertEqual(plan.missingSessionIDs, ["sY"])
        XCTAssertTrue(plan.toCreate.isEmpty)
    }
}

// MARK: - LifecycleCoordinator 冷启动对账

@MainActor
final class LifecycleCoordinatorTests: XCTestCase {

    func testPerformReconciliationDoesNotAdoptIdleCodexProcessAsSession() async {
        var now = Date(timeIntervalSince1970: 10_000)
        let store = SessionStore(now: { now })
        let runtimeStore = RuntimeStore()
        let fake = FakeProcessCommand()
        // Codex 进程可以承载空闲线程，不能仅凭进程补建运行会话。
        let scanner = StaticAgentProcessScanner(processes: [
            DetectedProcess(pid: 777, ppid: 1, agentId: "codex", commandLine: "codex run --task", workingDirectory: nil, startedAt: now)
        ])
        fake.alivePIDs = [777]

        let discovery = RuntimeDiscovery(scanner: scanner, registry: InMemoryRegistry(), now: { now })
        let reconciliation = Reconciliation(now: { now })
        let watchdog = LifecycleWatchdog(
            sessionStore: store,
            runtimeStore: runtimeStore,
            evaluator: HealthEvaluator(now: { now }),
            stateMachine: SessionStateMachine(now: { now }),
            processProbe: AgentProcessProbe(processCommand: fake),
            now: { now }
        )
        let coordinator = LifecycleCoordinator(
            sessionStore: store,
            runtimeStore: runtimeStore,
            watchdog: watchdog,
            discovery: discovery,
            reconciliation: reconciliation
        )

        await coordinator.performReconciliation()

        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertTrue(runtimeStore.runtimes(for: "codex").isEmpty)
        XCTAssertTrue(coordinator.isReady)
    }

    /// 不在监听名单内的 CLI（如 opencode）不会被冷启动进程扫描采纳：
    /// get_agent_sessions.py 白名单只含 claude/codex/gemini，opencode 不会出现在扫描结果中。
    func testPerformReconciliationIgnoresUnmonitoredAgentProcess() async {
        var now = Date(timeIntervalSince1970: 10_000)
        let store = SessionStore(now: { now })
        let runtimeStore = RuntimeStore()
        let fake = FakeProcessCommand()
        // Python 脚本白名单已排除 opencode，扫描结果为空。
        let scanner = StaticAgentProcessScanner(processes: [])
        fake.alivePIDs = [75479]

        let discovery = RuntimeDiscovery(scanner: scanner, registry: InMemoryRegistry(), now: { now })
        let reconciliation = Reconciliation(now: { now })
        let watchdog = LifecycleWatchdog(
            sessionStore: store,
            runtimeStore: runtimeStore,
            evaluator: HealthEvaluator(now: { now }),
            stateMachine: SessionStateMachine(now: { now }),
            processProbe: AgentProcessProbe(processCommand: fake),
            now: { now }
        )
        let coordinator = LifecycleCoordinator(
            sessionStore: store,
            runtimeStore: runtimeStore,
            watchdog: watchdog,
            discovery: discovery,
            reconciliation: reconciliation
        )

        await coordinator.performReconciliation()

        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertTrue(runtimeStore.runtimes(for: "opencode").isEmpty)
        XCTAssertTrue(coordinator.isReady)
    }

    /// 监听名单内的 Agent（gemini）在冷启动被发现时先以 SUSPECTED 补建（不立即显示运行），
    /// 空闲进程不会被当成「正在执行」常驻灵动岛。
    func testPerformReconciliationCreatesMonitoredAgentAsSuspected() async {
        var now = Date(timeIntervalSince1970: 10_000)
        let store = SessionStore(now: { now })
        let runtimeStore = RuntimeStore()
        let fake = FakeProcessCommand()
        let scanner = StaticAgentProcessScanner(processes: [
            DetectedProcess(pid: 4242, ppid: 38918, agentId: "gemini", commandLine: "gemini run --task", workingDirectory: nil, startedAt: now)
        ])
        fake.alivePIDs = [4242]

        let discovery = RuntimeDiscovery(scanner: scanner, registry: InMemoryRegistry(), now: { now })
        let reconciliation = Reconciliation(now: { now })
        let watchdog = LifecycleWatchdog(
            sessionStore: store,
            runtimeStore: runtimeStore,
            evaluator: HealthEvaluator(now: { now }),
            stateMachine: SessionStateMachine(now: { now }),
            processProbe: AgentProcessProbe(processCommand: fake),
            now: { now }
        )
        let coordinator = LifecycleCoordinator(
            sessionStore: store,
            runtimeStore: runtimeStore,
            watchdog: watchdog,
            discovery: discovery,
            reconciliation: reconciliation
        )

        await coordinator.performReconciliation()

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions[0].agentId, "gemini")
        XCTAssertEqual(store.sessions[0].state, .suspected)
        XCTAssertEqual(store.sessions[0].pid, 4242)
        XCTAssertTrue(coordinator.isReady)
    }
}

/// 内存版 registry，避免测试写真实文件系统。
final class InMemoryRegistry: RuntimeRegistryStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: StoredRuntimeRecord] = [:]

    func loadAll() -> [StoredRuntimeRecord] {
        lock.lock(); defer { lock.unlock() }
        return Array(storage.values)
    }

    func save(_ record: StoredRuntimeRecord) {
        lock.lock(); defer { lock.unlock() }
        storage[record.runtimeId] = record
    }

    func remove(runtimeId: String) {
        lock.lock(); defer { lock.unlock() }
        storage[runtimeId] = nil
    }
}
