import XCTest
import Combine
import Display
@testable import AgentEventModule

@MainActor
final class AgentWorkingPresentationControllerTests: XCTestCase {
    func testRunningPresentationHasNoFixedExpiry() {
        let controller = AgentWorkingPresentationController()

        controller.receive(event(agent: "codex"))

        XCTAssertNotNil(controller.presentation)
        XCTAssertNil(controller.presentation?.expiresAt)
    }

    func testClaudeEventPresentsItsOwnIdentity() {
        let controller = AgentWorkingPresentationController()

        controller.receive(event(agent: "claude"))

        XCTAssertEqual(controller.presentation?.agentID, "claude")
        XCTAssertEqual(controller.presentation?.petState, .waving)
    }

    func testNewCodexEventReplacesPresentationAndIgnoresOldExpiry() throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let controller = AgentWorkingPresentationController(now: { now })

        controller.receive(event(agent: "codex"))
        let first = try XCTUnwrap(controller.presentation)

        now = now.addingTimeInterval(12)
        controller.receive(event(agent: "CODEX"))
        let second = try XCTUnwrap(controller.presentation)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNil(second.expiresAt)

        controller.dismiss(presentationID: first.id)
        XCTAssertEqual(controller.presentation, second)

        controller.dismiss(presentationID: second.id)
        XCTAssertNil(controller.presentation)
    }

    func testPresentationDismissesWhenSessionSnapshotHasNoActiveSession() {
        let controller = AgentWorkingPresentationController()

        controller.receive(event(agent: "codex"))
        XCTAssertNotNil(controller.presentation)

        controller.updateSessions([])
        XCTAssertNil(controller.presentation)
    }

    func testEventTypesMapToPetStates() {
        let controller = AgentWorkingPresentationController()

        controller.receive(event(agent: "claude", type: .thinking, sessionID: "thinking"))
        XCTAssertEqual(controller.presentation?.petState, .review)

        controller.receive(event(agent: "gemini", type: .toolStart, sessionID: "tool"))
        XCTAssertEqual(controller.presentation?.petState, .running)

        controller.receive(event(agent: "codex", type: .completed, sessionID: "complete"))
        XCTAssertEqual(controller.presentation?.petState, .jumping)
    }

    func testCompletedNotificationPresentsFullDetailForFourSeconds() {
        let now = Date(timeIntervalSince1970: 1_000)
        let controller = AgentWorkingPresentationController(
            now: { now }
        )

        controller.receive(event(agent: "codex", type: .completed, sessionID: "complete"))

        XCTAssertEqual(controller.presentation?.expiresAt, now.addingTimeInterval(4))
        XCTAssertTrue(controller.presentation?.isFullDetail == true)
        XCTAssertEqual(controller.presentation?.statusText, "已完成")
    }

    func testStateOnlyCompletionDoesNotCreatePresentation() {
        let controller = AgentWorkingPresentationController()

        controller.receive(Display.AgentEvent(
            agentId: "codex",
            sessionId: "complete",
            type: .sessionCompleted,
            timestamp: Date(),
            originType: EventType.completed.rawValue,
            isStateOnly: true
        ))

        XCTAssertNil(controller.presentation)
    }

    func testDuplicateDisplayCompletionDoesNotRestartFeedback() throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let controller = AgentWorkingPresentationController(now: { now })
        let completion = Display.AgentEvent(
            id: "rollout-completion",
            agentId: "codex",
            sessionId: "complete",
            type: .sessionCompleted,
            timestamp: now,
            originType: EventType.completed.rawValue
        )

        controller.receive(completion)
        let first = try XCTUnwrap(controller.presentation)

        now = now.addingTimeInterval(3)
        controller.receive(completion)

        XCTAssertEqual(controller.presentation?.id, first.id)
        XCTAssertEqual(controller.presentation?.expiresAt, first.expiresAt)
    }

    func testCompletedPresentationUsesSessionPrompt() {
        var now = Date(timeIntervalSince1970: 1_000)
        let controller = AgentWorkingPresentationController(now: { now })

        controller.receive(event(
            agent: "codex",
            type: .agentStart,
            sessionID: "complete",
            message: "检查并优化 CPU 占用"
        ))
        now = now.addingTimeInterval(4)
        controller.receive(event(agent: "codex", type: .completed, sessionID: "complete"))

        XCTAssertEqual(controller.presentation?.petState, .jumping)
        XCTAssertEqual(controller.presentation?.prompt, "检查并优化 CPU 占用")
    }

    func testCompletedEventReplacesRunningPresentationBeforeSessionLeavesRunning() {
        let now = Date(timeIntervalSince1970: 1_000)
        let system = DisplaySystem()
        let controller = AgentWorkingPresentationController(now: { now })
        var cancellables = Set<AnyCancellable>()

        system.awareness.eventsPublisher
            .sink { controller.receive($0) }
            .store(in: &cancellables)
        system.sessionStore.$sessions
            .sink { controller.updateSessions($0) }
            .store(in: &cancellables)

        system.pipeline.ingest(Display.AgentEvent(
            agentId: "codex",
            sessionId: "session",
            type: .sessionRunning,
            timestamp: now,
            originType: EventType.toolStart.rawValue
        ))
        XCTAssertEqual(controller.presentation?.petState, .running)

        system.pipeline.ingest(Display.AgentEvent(
            agentId: "codex",
            sessionId: "session",
            type: .sessionCompleted,
            timestamp: now,
            originType: EventType.completed.rawValue
        ))

        XCTAssertEqual(system.sessionStore.session(id: "session")?.state, .completed)
        XCTAssertEqual(controller.presentation?.petState, .jumping)
        XCTAssertEqual(controller.presentation?.expiresAt, now.addingTimeInterval(4))
    }

    func testWaitingAndFailurePreemptRecentActiveAgent() {
        var now = Date(timeIntervalSince1970: 1_000)
        let controller = AgentWorkingPresentationController(now: { now })

        controller.receive(event(agent: "claude", type: .waitingApproval, sessionID: "waiting"))
        now = now.addingTimeInterval(1)
        controller.receive(event(agent: "codex", type: .failed, sessionID: "failed"))
        now = now.addingTimeInterval(1)
        controller.receive(event(agent: "gemini", type: .toolStart, sessionID: "active"))

        XCTAssertEqual(controller.presentation?.agentID, "claude")
        XCTAssertEqual(controller.presentation?.petState, .waiting)
    }

    func testDismissingForegroundFallsBackToOtherActiveSession() throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let controller = AgentWorkingPresentationController(now: { now })

        controller.receive(event(agent: "claude", type: .toolStart, sessionID: "claude-session"))
        now = now.addingTimeInterval(1)
        controller.receive(event(agent: "codex", type: .toolStart, sessionID: "codex-session"))
        let foreground = try XCTUnwrap(controller.presentation)
        XCTAssertEqual(foreground.agentID, "codex")

        controller.dismiss(presentationID: foreground.id)

        XCTAssertEqual(controller.presentation?.agentID, "claude")
    }

    func testEventsDuringCreationTextPhaseAreQueued() throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let controller = AgentWorkingPresentationController(now: { now })

        // 创建会话 → 文字版（前 3 秒）
        controller.receive(event(agent: "claude", type: .agentStart, sessionID: "session"))
        let creation = try XCTUnwrap(controller.presentation)
        XCTAssertTrue(creation.isFullDetail)

        // 文字版期间又来了新消息，不应打断文字版，而是入队。
        now = now.addingTimeInterval(1)
        controller.receive(event(agent: "claude", type: .toolStart, sessionID: "session"))
        XCTAssertEqual(controller.presentation?.id, creation.id)
        XCTAssertTrue(controller.presentation?.isFullDetail == true)

        // 文字版 3 秒结束后，新消息才被处理。
        now = now.addingTimeInterval(3)
        controller.receive(event(agent: "claude", type: .toolStart, sessionID: "session"))
        XCTAssertNotEqual(controller.presentation?.id, creation.id)
        XCTAssertEqual(controller.presentation?.petState, .running)
        XCTAssertFalse(controller.presentation?.isFullDetail == true)
    }

    func testSessionStartDoesNotNotifyAndAgentStartMerges() throws {
        var now = Date(timeIntervalSince1970: 2_000)
        let controller = AgentWorkingPresentationController(now: { now })

        // sessionStart 暂不产生任何通知。
        controller.receive(event(agent: "claude", type: .sessionStart, sessionID: "s1"))
        XCTAssertNil(controller.presentation)

        // agentStart 触发「已启动」文字版（整个文字版阶段保持 waving 状态）。
        now = now.addingTimeInterval(0.2)
        controller.receive(event(agent: "claude", type: .agentStart, sessionID: "s1"))
        let first = try XCTUnwrap(controller.presentation)
        XCTAssertTrue(first.isFullDetail)
        XCTAssertEqual(first.petState, .waving)
        XCTAssertEqual(first.statusText, "已启动")

        // agentStart 短时间连发时应合并为同一次文字版，不重复、不重置。
        now = now.addingTimeInterval(0.2)
        controller.receive(event(agent: "claude", type: .agentStart, sessionID: "s1"))
        XCTAssertEqual(controller.presentation?.id, first.id)
        XCTAssertTrue(controller.presentation?.isFullDetail == true)
        XCTAssertEqual(controller.presentation?.petState, .waving)

        // 文字版仍从 agentStart 起 3 秒后结束，随后切为运行态。
        now = now.addingTimeInterval(3)
        controller.receive(event(agent: "claude", type: .toolStart, sessionID: "s1"))
        XCTAssertNotEqual(controller.presentation?.id, first.id)
        XCTAssertFalse(controller.presentation?.isFullDetail == true)
        XCTAssertEqual(controller.presentation?.petState, .running)
    }

    func testSessionStartedByNonCreationEventNeverShowsTextPhase() throws {
        var now = Date(timeIntervalSince1970: 3_000)
        let controller = AgentWorkingPresentationController(now: { now })

        // 会话首个事件是 toolStart（非创建会话）→ 标记该会话不展示创建会话文字版。
        controller.receive(event(agent: "claude", type: .toolStart, sessionID: "s"))
        let first = try XCTUnwrap(controller.presentation)
        XCTAssertFalse(first.isFullDetail)

        // 该会话后续再来 agentStart，也应降级为图标版，不再展示创建会话文字版。
        now = now.addingTimeInterval(2)
        controller.receive(event(agent: "claude", type: .agentStart, sessionID: "s"))
        XCTAssertFalse(controller.presentation?.isFullDetail == true)
        XCTAssertEqual(controller.presentation?.petState, .running)
    }

    func testHighPriorityEventPreemptsTextPhase() throws {
        var now = Date(timeIntervalSince1970: 4_000)
        let controller = AgentWorkingPresentationController(now: { now })

        // 创建会话文字版展示中。
        controller.receive(event(agent: "claude", type: .agentStart, sessionID: "a"))
        XCTAssertTrue(controller.presentation?.isFullDetail == true)

        // 另一个会话的失败事件（高优先级）应打断文字版，立即展示，而非排队等待。
        now = now.addingTimeInterval(1)
        controller.receive(event(agent: "codex", type: .failed, sessionID: "b"))
        XCTAssertEqual(controller.presentation?.agentID, "codex")
        XCTAssertEqual(controller.presentation?.petState, .failed)
        XCTAssertFalse(controller.presentation?.isFullDetail == true)
    }

    func testRunningPresentationRemainsWhileSessionIsActive() {
        var now = Date(timeIntervalSince1970: 5_000)
        let controller = AgentWorkingPresentationController(now: { now })
        controller.updateSessions([session(id: "s", agent: "codex", state: .running, at: now)])

        now = now.addingTimeInterval(60)
        controller.updateSessions([session(id: "s", agent: "codex", state: .running, at: now)])

        XCTAssertEqual(controller.presentation?.agentID, "codex")
        XCTAssertEqual(controller.presentation?.petState, .running)
        XCTAssertNil(controller.presentation?.expiresAt)
    }

    func testRunningPresentationDismissesWhenLastActiveSessionEnds() {
        let now = Date(timeIntervalSince1970: 6_000)
        let controller = AgentWorkingPresentationController(now: { now })
        controller.updateSessions([session(id: "s", agent: "codex", state: .running, at: now)])
        XCTAssertNotNil(controller.presentation)

        controller.updateSessions([session(id: "s", agent: "codex", state: .completed, at: now)])

        XCTAssertNil(controller.presentation)
    }

    func testAgentRemainsPresentedWhileAnotherSessionIsActive() {
        let now = Date(timeIntervalSince1970: 7_000)
        let controller = AgentWorkingPresentationController(now: { now })
        controller.updateSessions([
            session(id: "first", agent: "claude", state: .running, at: now),
            session(id: "second", agent: "claude", state: .running, at: now),
        ])

        controller.updateSessions([
            session(id: "first", agent: "claude", state: .completed, at: now),
            session(id: "second", agent: "claude", state: .running, at: now),
        ])

        XCTAssertEqual(controller.presentation?.agentID, "claude")
        XCTAssertEqual(controller.presentation?.sessionID, "second")
    }

    func testMultipleRunningAgentsShowMostRecentFirst() throws {
        // offset=0 时展示「最近活跃」的 agent（新事件立即顶上来）。
        var now = Date(timeIntervalSince1970: 8_000)
        let controller = AgentWorkingPresentationController(now: { now })

        controller.receive(event(agent: "claude", type: .toolStart, sessionID: "c"))
        now = now.addingTimeInterval(1)
        controller.receive(event(agent: "codex", type: .toolStart, sessionID: "x"))

        XCTAssertEqual(controller.presentation?.agentID, "codex")
    }

    func testHighPriorityAgentGovernsOverRunningGroup() {
        // 等待授权（priority 3）高于普通运行（priority 1）：即使运行 agent 更晚，也显示等待授权的。
        var now = Date(timeIntervalSince1970: 9_000)
        let controller = AgentWorkingPresentationController(now: { now })

        controller.receive(event(agent: "gemini", type: .toolStart, sessionID: "active"))
        now = now.addingTimeInterval(1)
        controller.receive(event(agent: "claude", type: .waitingApproval, sessionID: "waiting"))

        XCTAssertEqual(controller.presentation?.agentID, "claude")
        XCTAssertEqual(controller.presentation?.petState, .waiting)
    }

    func testDismissingOneRunningAgentFallsBackToOther() throws {
        // 多运行 agent，dismiss 掉当前展示的，应回落到另一个仍活动的 agent。
        var now = Date(timeIntervalSince1970: 10_000)
        let controller = AgentWorkingPresentationController(now: { now })

        controller.receive(event(agent: "claude", type: .toolStart, sessionID: "c"))
        now = now.addingTimeInterval(1)
        controller.receive(event(agent: "codex", type: .toolStart, sessionID: "x"))
        let current = try XCTUnwrap(controller.presentation)
        XCTAssertEqual(current.agentID, "codex")

        controller.dismiss(presentationID: current.id)
        XCTAssertEqual(controller.presentation?.agentID, "claude")
    }

    func testTerminalFeedbackShowsOverActiveRotation() throws {
        // 完成（非活动终态）存在时，优先展示「已完成」反馈，而不是轮播到其它活动的 agent。
        var now = Date(timeIntervalSince1970: 11_000)
        let controller = AgentWorkingPresentationController(now: { now })

        controller.receive(event(agent: "codex", type: .toolStart, sessionID: "x"))
        now = now.addingTimeInterval(1)
        controller.receive(event(agent: "claude", type: .completed, sessionID: "c"))

        XCTAssertEqual(controller.presentation?.agentID, "claude")
        XCTAssertEqual(controller.presentation?.petState, .jumping)
    }

    func testFailedPreemptsActiveAndShowsFailedState() {
        // 失败（高优终态）优先于活动运行展示，且不被轮播掩盖。
        var now = Date(timeIntervalSince1970: 12_000)
        let controller = AgentWorkingPresentationController(now: { now })

        controller.receive(event(agent: "codex", type: .toolStart, sessionID: "x"))
        now = now.addingTimeInterval(1)
        controller.receive(event(agent: "gemini", type: .failed, sessionID: "g"))

        XCTAssertEqual(controller.presentation?.agentID, "gemini")
        XCTAssertEqual(controller.presentation?.petState, .failed)
    }

    func testSameAgentMultiSessionAggregatesToHighestState() throws {
        // 同一 claude 两个会话：一个运行中、一个等待授权 → 整体显示「等待授权」。
        var now = Date(timeIntervalSince1970: 20_000)
        let controller = AgentWorkingPresentationController(now: { now })

        controller.receive(event(agent: "claude", type: .toolStart, sessionID: "session-run"))
        now = now.addingTimeInterval(1)
        controller.receive(event(agent: "claude", type: .waitingApproval, sessionID: "session-wait"))

        XCTAssertEqual(controller.presentation?.agentID, "claude")
        XCTAssertEqual(controller.presentation?.petState, .waiting)
    }

    func testSameAgentMultiRunningStillShowsSingleAgent() throws {
        // 同一 claude 两个会话都在运行 → 仍只显示一个 claude（不因多会话而重复轮播）。
        var now = Date(timeIntervalSince1970: 21_000)
        let controller = AgentWorkingPresentationController(now: { now })

        controller.receive(event(agent: "claude", type: .toolStart, sessionID: "a"))
        now = now.addingTimeInterval(1)
        controller.receive(event(agent: "claude", type: .toolStart, sessionID: "b"))

        XCTAssertEqual(controller.presentation?.agentID, "claude")
        XCTAssertEqual(controller.presentation?.petState, .running)
    }

    func testIdleAgentWithOnlyCompletedShowsTransientThenNothing() throws {
        // 仅一个「已完成」（瞬时）会话：先弹「已完成」，随后（无持续态）Agent 空闲、不占位。
        var now = Date(timeIntervalSince1970: 22_000)
        let controller = AgentWorkingPresentationController(now: { now })

        controller.receive(event(agent: "codex", type: .completed, sessionID: "done"))
        // 瞬态阶段：展示「已完成」。
        XCTAssertEqual(controller.presentation?.petState, .jumping)

        // 瞬态结束后（推进时间超出展示时长、再 refresh）：不再有持续态 → 无可展示。
        now = now.addingTimeInterval(5)
        controller.receive(event(agent: "codex", type: .toolStart, sessionID: "done"))
        XCTAssertNotEqual(controller.presentation?.petState, .jumping)
    }

    private func event(
        agent: String,
        type: EventType = .agentStart,
        sessionID: String = "session",
        message: String? = nil
    ) -> AgentEventModule.AgentEvent {
        AgentEventModule.AgentEvent(
            id: UUID().uuidString,
            agent: agent,
            sessionId: sessionID,
            type: type,
            message: message,
            timestamp: Date()
        )
    }

    private func session(
        id: String,
        agent: String,
        state: Display.SessionState,
        at date: Date
    ) -> Display.AgentSession {
        Display.AgentSession(
            id: id,
            agentId: agent,
            state: state,
            lastActivityAt: date,
            createdAt: date,
            updatedAt: date
        )
    }
}
