import XCTest
import Combine
@testable import Display

/// 验收测试：覆盖设计文档第二十四章的 Case 1–6。
@MainActor
final class DisplayAcceptanceTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Helpers

    private func makeEvent(_ agent: String, _ session: String, _ type: AgentEventType, at date: Date) -> AgentEvent {
        AgentEvent(agentId: agent, sessionId: session, type: type, timestamp: date)
    }

    // MARK: - Case 1: 只有音乐

    func testCase1_onlyMusic() {
        let system = DisplaySystem()
        let now = Date()
        system.activityStore.update(ActivityContent(kind: .music, isActive: true, updatedAt: now))
        system.coordinator.refresh()

        guard let decision = system.coordinator.decision else {
            return XCTFail("应当产出一个决策")
        }
        XCTAssertEqual(decision.source, .activity)
        guard case .activity(let content) = decision.content else {
            return XCTFail("应为 activity 内容")
        }
        XCTAssertEqual(content.kind, .music)
    }

    // MARK: - 多个 Activity 同时 active → 轮换

    func testMultipleActiveActivitiesRotate() {
        let system = DisplaySystem()
        let now = Date()
        system.activityStore.update(ActivityContent(kind: .music, isActive: true, updatedAt: now))
        system.activityStore.update(ActivityContent(kind: .weather, isActive: true, updatedAt: now.addingTimeInterval(1)))
        system.activityStore.update(ActivityContent(kind: .stock, isActive: true, updatedAt: now.addingTimeInterval(2)))
        system.coordinator.refresh()

        // advanceRotation 会在三个 active Activity 之间轮换。
        let kinds = (0..<6).map { _ -> ActivityKind in
            system.scheduler.advanceRotation()
            guard case .activity(let content)? = system.coordinator.decision?.content else {
                return .music
            }
            return content.kind
        }
        XCTAssertEqual(Set(kinds), Set(ActivityKind.allCases))
        XCTAssertGreaterThanOrEqual(Set(kinds).count, 2)
    }

    // MARK: - Case 2: Claude Running 覆盖音乐

    func testCase2_claudeRunningOverridesMusic() {
        let system = DisplaySystem()
        let now = Date()
        system.activityStore.update(ActivityContent(kind: .music, isActive: true, updatedAt: now))
        system.pipeline.ingest(makeEvent("claude-code", "sessionA", .sessionRunning, at: now))
        system.coordinator.refresh()

        guard let decision = system.coordinator.decision else {
            return XCTFail("应当产出一个决策")
        }
        XCTAssertEqual(decision.source, .agent)
        guard case .agent(let agent) = decision.content else {
            return XCTFail("应为 agent 内容")
        }
        XCTAssertEqual(agent.agentId, "claude-code")
        XCTAssertTrue(agent.hasRunningSession)
    }

    // MARK: - Case 3: 三个 Agent 同时运行 → 进入 Agent Display Pool

    func testCase3_threeAgentsRunningPool() {
        let system = DisplaySystem()
        let now = Date()
        system.pipeline.ingest(makeEvent("claude-code", "sA", .sessionRunning, at: now))
        system.pipeline.ingest(makeEvent("codex", "sB", .sessionRunning, at: now))
        system.pipeline.ingest(makeEvent("gemini", "sC", .sessionRunning, at: now))
        system.coordinator.refresh()

        let pool = system.awareness.activeAgents()
        XCTAssertEqual(pool.count, 3)

        // 轮换：advanceRotation 后 decision 始终是 agent 类别，且会轮转三个 agent。
        let agentIDs = (0..<6).map { _ -> String in
            system.scheduler.advanceRotation()
            guard case .agent(let agent)? = system.coordinator.decision?.content else {
                return "not-agent"
            }
            return agent.agentId
        }
        XCTAssertFalse(agentIDs.contains("not-agent"))
        // 六个 tick 应覆盖到全部三个 agent（轮换确实发生，而非固定展示一个）。
        XCTAssertEqual(Set(agentIDs), Set(["claude-code", "codex", "gemini"]))
        XCTAssertGreaterThanOrEqual(Set(agentIDs).count, 2)
    }

    // MARK: - Case 4: Agent 没有 Running Session → 不进池，但 Session 保留

    func testCase4_noRunningSessionKeepsSessionState() {
        let system = DisplaySystem()
        let now = Date()
        // Claude 只有 waitingApproval / completed / failed。
        system.pipeline.ingest(makeEvent("claude-code", "sA", .sessionWaitingApproval, at: now))
        system.pipeline.ingest(makeEvent("claude-code", "sB", .sessionCompleted, at: now))
        system.pipeline.ingest(makeEvent("claude-code", "sC", .sessionFailed, at: now))
        system.coordinator.refresh()

        // 不进 Agent Display Pool。
        XCTAssertTrue(system.awareness.activeAgents().isEmpty)
        // Session 状态仍被保存。
        XCTAssertEqual(system.sessionStore.sessions(for: "claude-code").count, 3)
        XCTAssertEqual(system.sessionStore.session(id: "sA")?.state, .waitingApproval)
        XCTAssertEqual(system.sessionStore.session(id: "sB")?.state, .completed)
        XCTAssertEqual(system.sessionStore.session(id: "sC")?.state, .failed)
    }

    // MARK: - Case 5: Waiting Approval 产生 Notification，且不改变 Session 状态

    func testCase5_waitingApprovalCreatesNotification() {
        let system = DisplaySystem()
        let now = Date()
        system.pipeline.ingest(makeEvent("codex", "sA", .sessionWaitingApproval, at: now))

        // SessionStore 更新状态。
        XCTAssertEqual(system.sessionStore.session(id: "sA")?.state, .waitingApproval)
        // NotificationCenter 创建了通知。
        XCTAssertEqual(system.notificationStore.history.count, 1)
        XCTAssertEqual(system.notificationStore.history.first?.type, .waitingApproval)
        // 通知展示期间，决策为 notification。
        system.coordinator.refresh()
        XCTAssertEqual(system.coordinator.decision?.source, .notification)
        guard case .notification(let n) = system.coordinator.decision?.content else {
            return XCTFail("应为 notification 内容")
        }
        XCTAssertEqual(n.sessionId, "sA")
        XCTAssertEqual(n.agentId, "codex")

        // 通知结束（手动 dismiss）后，Session 状态仍为 waitingApproval。
        system.notificationQueue.dismiss(n.id)
        XCTAssertEqual(system.sessionStore.session(id: "sA")?.state, .waitingApproval)
    }

    func testStopRequestedCreatesCompletedNotification() {
        let system = DisplaySystem()
        let now = Date()
        system.pipeline.ingest(makeEvent("codex", "sA", .sessionStopRequested, at: now))

        XCTAssertEqual(system.sessionStore.session(id: "sA")?.stopRequested, true)
        XCTAssertEqual(system.notificationStore.history.last?.type, .completed)
        XCTAssertEqual(system.notificationStore.history.last?.title, "Codex")
        XCTAssertEqual(system.notificationStore.history.last?.subtitle, "已完成")
    }

    // MARK: - Case 6: Notification 结束时重新计算，而非恢复历史

    func testCase6_notificationEndsRecomputes() {
        let system = DisplaySystem()
        let now = Date()
        // Codex 先失败 → 产生 Notification。
        system.pipeline.ingest(makeEvent("codex", "sA", .sessionFailed, at: now))
        system.coordinator.refresh()
        XCTAssertEqual(system.coordinator.decision?.source, .notification)

        // 通知展示期间：Claude 开始 Running，Codex 完成。
        system.pipeline.ingest(makeEvent("claude-code", "sB", .sessionRunning, at: now.addingTimeInterval(1)))
        system.pipeline.ingest(makeEvent("codex", "sA", .sessionCompleted, at: now.addingTimeInterval(2)))

        // 通知结束后：应重新计算为 Claude（而非恢复 Codex）。
        guard case .notification(let n) = system.coordinator.decision?.content else {
            return XCTFail("当前仍应是通知")
        }
        system.notificationQueue.dismiss(n.id)
        system.coordinator.refresh()

        XCTAssertEqual(system.coordinator.decision?.source, .agent)
        guard case .agent(let agent) = system.coordinator.decision?.content else {
            return XCTFail("应为 agent 内容")
        }
        XCTAssertEqual(agent.agentId, "claude-code")
    }

    func testTerminalSessionCanReopenWithSameSessionIDAndNotifyAgain() {
        let system = DisplaySystem()
        let now = Date()

        system.pipeline.ingest(makeEvent("codex", "sA", .sessionCompleted, at: now))
        XCTAssertEqual(system.sessionStore.session(id: "sA")?.state, .completed)
        XCTAssertEqual(system.notificationStore.history.last?.type, .completed)

        system.pipeline.ingest(makeEvent("codex", "sA", .sessionRunning, at: now.addingTimeInterval(1)))
        XCTAssertEqual(system.sessionStore.session(id: "sA")?.state, .running)

        system.pipeline.ingest(makeEvent("codex", "sA", .sessionCompleted, at: now.addingTimeInterval(2)))
        XCTAssertEqual(system.sessionStore.session(id: "sA")?.state, .completed)

        let completedNotifications = system.notificationStore.history.filter {
            $0.sessionId == "sA" && $0.type == .completed
        }
        XCTAssertEqual(completedNotifications.count, 2)
    }

    func testLateRunningEventCannotReopenCompletedSession() {
        let system = DisplaySystem()
        let now = Date()

        system.pipeline.ingest(makeEvent("codex", "sA", .sessionRunning, at: now))
        system.pipeline.ingest(makeEvent("codex", "sA", .sessionCompleted, at: now.addingTimeInterval(2)))
        system.pipeline.ingest(makeEvent("codex", "sA", .sessionRunning, at: now.addingTimeInterval(1)))

        XCTAssertEqual(system.sessionStore.session(id: "sA")?.state, .completed)
        XCTAssertEqual(system.sessionStore.session(id: "sA")?.generation, 0)
    }

    func testSameTimestampTerminalEventWinsOverRunningEvent() {
        let system = DisplaySystem()
        let now = Date()

        system.pipeline.ingest(makeEvent("codex", "sA", .sessionCompleted, at: now))
        system.pipeline.ingest(makeEvent("codex", "sA", .sessionRunning, at: now))

        XCTAssertEqual(system.sessionStore.session(id: "sA")?.state, .completed)
    }

    // MARK: - 通知与 Agent 状态解耦

    func testNotificationDoesNotMutateSession() {
        let system = DisplaySystem()
        let now = Date()
        system.pipeline.ingest(makeEvent("codex", "sA", .sessionWaitingApproval, at: now))
        system.coordinator.refresh()

        // 通知被 dismiss 后 Session 不变。
        guard case .notification(let n) = system.coordinator.decision?.content else {
            return XCTFail("应为通知")
        }
        system.notificationQueue.dismiss(n.id)
        XCTAssertEqual(system.sessionStore.session(id: "sA")?.state, .waitingApproval)
    }

    // MARK: - Agent 与 Activity 的关系

    func testAgentPoolEmptyFallsBackToActivity() {
        let system = DisplaySystem()
        let now = Date()
        system.activityStore.update(ActivityContent(kind: .weather, isActive: true, updatedAt: now))
        system.coordinator.refresh()
        XCTAssertEqual(system.coordinator.decision?.source, .activity)

        // Agent 进入 Running → 覆盖 Activity。
        system.pipeline.ingest(makeEvent("gemini", "sA", .sessionRunning, at: now))
        system.coordinator.refresh()
        XCTAssertEqual(system.coordinator.decision?.source, .agent)

        // Agent 变为 completed → 退出池 → 回到 Activity。
        system.pipeline.ingest(makeEvent("gemini", "sA", .sessionCompleted, at: now.addingTimeInterval(1)))
        if let notification = system.notificationQueue.peek() {
            system.notificationQueue.dismiss(notification.id)
        }
        system.coordinator.refresh()
        XCTAssertEqual(system.coordinator.decision?.source, .activity)
    }

    // MARK: - Agent 感知关闭后回落到 Activity

    /// Agent 感知关闭（清空感知状态）后，残留的 Running Session 不应继续阻塞
    /// 常驻内容：决策应回落到仍活跃的音乐 Activity。
    func testClearAgentStateRestoresMusicActivity() {
        let system = DisplaySystem()
        let now = Date()
        system.activityStore.update(ActivityContent(kind: .music, isActive: true, updatedAt: now))
        system.pipeline.ingest(makeEvent("claude-code", "sA", .sessionRunning, at: now))
        system.coordinator.refresh()
        XCTAssertEqual(system.coordinator.decision?.source, .agent)

        // 模拟 Agent 感知关闭：清空残留的 Running Session 感知状态。
        system.clearAgentState()

        XCTAssertTrue(system.awareness.displayStates.isEmpty)
        XCTAssertTrue(system.awareness.activeAgents().isEmpty)
        XCTAssertTrue(system.sessionStore.sessions.isEmpty)
        XCTAssertEqual(system.coordinator.decision?.source, .activity)
        guard case .activity(let content) = system.coordinator.decision?.content else {
            return XCTFail("应为 activity 内容")
        }
        XCTAssertEqual(content.kind, .music)
    }

    // MARK: - Agent 运行时通知不重叠

    /// sessionRunning 不应产生瞬时通知（运行状态已由 Agent 展示表达），
    /// 避免 Agent 运行时通知与运行内容重叠/堆积。
    func testRunningAgentDoesNotEmitRunningNotification() {
        let system = DisplaySystem()
        let now = Date()
        // 模拟 Agent 运行期连续产生多个 running 事件。
        for i in 0..<5 {
            system.pipeline.ingest(makeEvent("claude-code", "sA", .sessionRunning, at: now.addingTimeInterval(TimeInterval(i))))
        }
        system.coordinator.refresh()

        // 不产生 running 通知。
        XCTAssertTrue(system.notificationStore.history.isEmpty)
        // 决策保持单一 Agent 内容（无重叠）。
        XCTAssertEqual(system.coordinator.decision?.source, .agent)
        guard case .agent(let agent)? = system.coordinator.decision?.content else {
            return XCTFail("应为 agent 内容")
        }
        XCTAssertEqual(agent.agentId, "claude-code")
    }

    func testStateOnlyCompletionUpdatesSessionWithoutNotification() {
        let system = DisplaySystem()

        system.pipeline.ingest(AgentEvent(
            agentId: "codex",
            sessionId: "sA",
            type: .sessionCompleted,
            timestamp: Date(),
            isStateOnly: true
        ))

        XCTAssertEqual(system.sessionStore.session(id: "sA")?.state, .completed)
        XCTAssertTrue(system.notificationStore.history.isEmpty)
    }

    func testAgentStartEmitsOneTemporaryNotification() {
        let system = DisplaySystem()
        let now = Date()
        system.pipeline.ingest(AgentEvent(
            agentId: "codex",
            sessionId: "sA",
            type: .sessionRunning,
            timestamp: now,
            message: "检查并优化 CPU 占用",
            originType: "agentStart"
        ))

        XCTAssertEqual(system.notificationStore.history.count, 1)
        XCTAssertEqual(system.notificationStore.history.first?.type, .sessionCreated)
        XCTAssertEqual(system.notificationStore.history.first?.agentId, "codex")
        XCTAssertEqual(system.sessionStore.session(id: "sA")?.state, .running)
    }

    /// Hook shell 的 PID 可能已退出，健康检查不应据此误清除 Running。
    func testRunningSessionSurvivesDeadHookPIDHealthCheck() {
        let system = DisplaySystem()
        let staleDate = Date().addingTimeInterval(-60)
        let event = AgentEvent(
            agentId: "codex",
            sessionId: "sA",
            type: .sessionRunning,
            timestamp: staleDate,
            pid: 999_999
        )
        system.pipeline.ingest(event)

        system.awareness.stateManager.performHealthCheck()

        XCTAssertEqual(system.sessionStore.session(id: "sA")?.state, .running)
        XCTAssertTrue(system.awareness.displayState(for: "codex")?.hasRunningSession == true)
    }

    /// Agent 运行时决策始终是单一内容：临时通知出现时统一抢占 Agent，绝不两者同时展示。
    func testDecisionIsSingleContentWhileAgentRuns() {
        let system = DisplaySystem()
        let now = Date()
        system.pipeline.ingest(makeEvent("claude-code", "sA", .sessionRunning, at: now))
        // 任意临时通知进入队列。
        system.notificationQueue.enqueue(PocketNotchNotification(
            source: .system,
            type: .sessionCreated,
            title: "提示",
            createdAt: now.addingTimeInterval(1),
            duration: 5
        ))
        system.coordinator.refresh()

        // 任意临时通知都应抢占 Agent，决策绝不会同时包含两者。
        switch system.coordinator.decision?.content {
        case .agent(let a):
            XCTFail("临时通知应抢占 Agent，当前仍为 \(a.agentId)")
        case .notification(let n):
            XCTAssertEqual(n.type, .sessionCreated)
        case .activity, nil:
            XCTFail("不应回退到 activity 或无决策")
        }
    }

    func testAnyTransientNotificationOverridesResidentActivity() {
        let system = DisplaySystem()
        let now = Date()
        system.activityStore.update(ActivityContent(kind: .music, isActive: true, updatedAt: now))
        system.notificationQueue.enqueue(PocketNotchNotification(
            source: .system,
            type: .sessionCreated,
            title: "提示",
            createdAt: now.addingTimeInterval(1),
            duration: 5
        ))
        system.coordinator.refresh()

        XCTAssertEqual(system.coordinator.decision?.source, .notification)
        XCTAssertFalse(system.coordinator.shouldShow(.activity))

        guard let notification = system.notificationQueue.peek() else {
            return XCTFail("应存在临时通知")
        }
        system.notificationQueue.dismiss(notification.id)
        system.coordinator.refresh()
        XCTAssertEqual(system.coordinator.decision?.source, .activity)
    }

    /// 渲染门控：shouldShow 必须与单一决策来源一致，避免多来源重叠渲染。
    func testShouldShowReflectsSingleDecision() {
        let system = DisplaySystem()
        let now = Date()
        system.activityStore.update(ActivityContent(kind: .music, isActive: true, updatedAt: now))
        system.pipeline.ingest(makeEvent("claude-code", "sA", .sessionRunning, at: now))
        system.coordinator.refresh()

        // 决策为 agent → 只应展示 agent，通知与 activity 都不应展示。
        XCTAssertTrue(system.coordinator.shouldShow(.agent))
        XCTAssertFalse(system.coordinator.shouldShow(.notification))
        XCTAssertFalse(system.coordinator.shouldShow(.activity))
    }
}
