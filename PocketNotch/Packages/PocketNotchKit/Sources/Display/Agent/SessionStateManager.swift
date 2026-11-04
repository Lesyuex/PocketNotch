import AppKit
import Darwin
import Foundation
import os

public protocol AgentProcessMonitoring: Sendable {
    func isAlive(pid: Int32) -> Bool
    /// 校验 pid 指向的进程可执行名是否在给定集合内；集合为空时退化为仅判存活。
    /// 用于规避 hook shell 退出后 pid 被复用到其它进程造成的误判。
    func isAlive(pid: Int32, executableNames: Set<String>) -> Bool
}

public struct AgentProcessMonitor: AgentProcessMonitoring {
    public init() {}

    public func isAlive(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return NSRunningApplication(processIdentifier: pid) != nil || kill(pid, 0) == 0
    }

    public func isAlive(pid: Int32, executableNames: Set<String>) -> Bool {
        guard !executableNames.isEmpty else { return isAlive(pid: pid) }
        guard isAlive(pid: pid) else { return false }
        guard let name = SystemProcessCommand().executableName(pid: pid) else { return false }
        return executableNames.contains(name)
    }
}

@MainActor
public final class SessionStateManager {
    public struct Config: Sendable {
        public var heartbeatInterval: TimeInterval
        public var staleAfter: TimeInterval
        public var terminalRetention: TimeInterval

        public init(
            heartbeatInterval: TimeInterval = 5,
            staleAfter: TimeInterval = 20,
            terminalRetention: TimeInterval = 30
        ) {
            self.heartbeatInterval = heartbeatInterval
            self.staleAfter = staleAfter
            self.terminalRetention = terminalRetention
        }
    }

    public struct Update: Sendable {
        public let session: AgentSession
        public let changed: Bool
        public let previousState: SessionState?
        public let emittedEvent: AgentEvent?

        public init(session: AgentSession, changed: Bool, previousState: SessionState?, emittedEvent: AgentEvent?) {
            self.session = session
            self.changed = changed
            self.previousState = previousState
            self.emittedEvent = emittedEvent
        }
    }

    private let store: SessionStore
    private let processMonitor: AgentProcessMonitoring
    private let config: Config
    private let now: () -> Date
    private let logger = Logger(subsystem: "PocketNotch", category: "SessionStateManager")
    private var heartbeatTask: Task<Void, Never>?

    public init(
        store: SessionStore,
        processMonitor: AgentProcessMonitoring = AgentProcessMonitor(),
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.processMonitor = processMonitor
        self.config = config
        self.now = now
    }

    deinit {
        heartbeatTask?.cancel()
    }

    public func start() {
        guard heartbeatTask == nil else { return }
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(config.heartbeatInterval))
                self.performHealthCheck()
            }
        }
    }

    public func stop() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    @discardableResult
    public func handle(_ event: AgentEvent) -> Update? {
        let date = event.timestamp
        var session = store.session(id: event.sessionId) ?? AgentSession(
            id: event.sessionId,
            agentId: event.agentId,
            state: .idle,
            pid: event.pid,
            lastActivityAt: date,
            lastEventID: nil,
            createdAt: date,
            updatedAt: date
        )

        if session.lastEventID == event.id {
            return Update(session: session, changed: false, previousState: nil, emittedEvent: nil)
        }
        if isStale(event, for: session) {
            return Update(session: session, changed: false, previousState: nil, emittedEvent: nil)
        }

        let previousState = session.state
        if canReopen(session: session, with: event) {
            session.reopen(at: date)
        }
        session.markActivity(at: date, eventID: event.id)
        if let pid = event.pid {
            session.updatePID(pid, at: date)
        }
        if event.type == .sessionStopRequested {
            session.setStopRequested(true, at: date)
        }

        let targetState = resolveState(for: session, with: event)
        session.updateState(targetState, at: date)
        store.upsert(session)

        let changed = previousState != session.state
        let emittedEvent: AgentEvent?
        if event.type == .sessionStopRequested {
            emittedEvent = makeFeedbackEvent(
                for: session,
                sourceEvent: event,
                feedbackType: .sessionCompleted
            )
        } else {
            emittedEvent = changed ? makeDerivedEvent(for: session, sourceEvent: event) : nil
        }
        if changed {
            logger.debug("session=\(session.id, privacy: .public) agent=\(session.agentId, privacy: .public) \(previousState.rawValue, privacy: .public) -> \(session.state.rawValue, privacy: .public) via \(event.type.rawValue, privacy: .public)")
        }
        return Update(
            session: session,
            changed: changed,
            previousState: previousState,
            emittedEvent: emittedEvent
        )
    }

    public func performHealthCheck() {
        let date = now()
        for session in store.sessions {
            guard !session.state.isTerminal else { continue }
            guard let lastActivityAt = session.lastActivityAt else { continue }

            if session.state != .running && session.state != .waitingApproval {
                continue
            }

            if date.timeIntervalSince(lastActivityAt) < config.staleAfter {
                continue
            }

            let nextState: SessionState
            if let pid = session.pid,
               processMonitor.isAlive(pid: pid, executableNames: AgentExecutableNames.names(for: session.agentId)) {
                nextState = session.state == .waitingApproval ? .waitingApproval : .running
            } else if session.stopRequested {
                nextState = .stopped
            } else if session.state == .running || session.state == .waitingApproval {
                // Hook 上报的 PID 可能是短生命周期的 hook shell（脚本默认使用 $$），
                // 不能用 PID 退出推断 Agent 会话结束。只有明确的终态事件才收口会话。
                nextState = session.state
            } else {
                nextState = .failed
            }

            var updated = session
            let previousState = updated.state
            updated.updateState(nextState, at: date)
            store.upsert(updated)
            if previousState != nextState {
                logger.debug("session=\(updated.id, privacy: .public) agent=\(updated.agentId, privacy: .public) \(previousState.rawValue, privacy: .public) -> \(nextState.rawValue, privacy: .public) via health_check")
            }
        }

        store.removeExpiredTerminalSessions(olderThan: date.addingTimeInterval(-config.terminalRetention))
    }

    private func resolveState(for session: AgentSession, with event: AgentEvent) -> SessionState {
        if session.state.isTerminal && !canReopen(session: session, with: event) {
            return session.state
        }

        switch event.type {
        case .sessionCreated:
            return .idle
        case .sessionRunning:
            return .running
        case .sessionWaitingApproval:
            return .waitingApproval
        case .sessionCompleted:
            return .completed
        case .sessionFailed:
            return .failed
        case .sessionStopped:
            return .stopped
        case .sessionUnknown:
            return .unknown
        case .sessionStopRequested:
            return session.state
        case .sessionEnded:
            if session.stopRequested {
                return .stopped
            }
            if let exitCode = event.exitCode {
                if exitCode == 0 {
                    return .completed
                }
                return .failed
            }
            if let pid = session.pid,
               processMonitor.isAlive(pid: pid, executableNames: AgentExecutableNames.names(for: session.agentId)) {
                return session.state == .waitingApproval ? .waitingApproval : .running
            }
            return .unknown
        }
    }

    private func canReopen(session: AgentSession, with event: AgentEvent) -> Bool {
        guard session.state.isTerminal else { return false }
        switch event.type {
        case .sessionCreated, .sessionRunning, .sessionWaitingApproval:
            return true
        case .sessionCompleted, .sessionFailed, .sessionStopped, .sessionUnknown, .sessionStopRequested, .sessionEnded:
            return false
        }
    }

    private func isStale(_ event: AgentEvent, for session: AgentSession) -> Bool {
        guard let lastEventAt = session.lastHookEventAt else { return false }
        if event.timestamp < lastEventAt {
            return true
        }
        if event.timestamp == lastEventAt,
           session.state.isTerminal,
           event.type == .sessionRunning || event.type == .sessionCreated || event.type == .sessionWaitingApproval {
            return true
        }
        return false
    }

    private func makeDerivedEvent(for session: AgentSession, sourceEvent: AgentEvent) -> AgentEvent {
        let eventType: AgentEventType
        switch session.state {
        case .idle:
            eventType = .sessionCreated
        case .running:
            eventType = .sessionRunning
        case .waitingApproval:
            eventType = .sessionWaitingApproval
        case .suspected:
            eventType = .sessionRunning
        case .lost:
            eventType = .sessionUnknown
        case .completed:
            eventType = .sessionCompleted
        case .failed:
            eventType = .sessionFailed
        case .stopped:
            eventType = .sessionStopped
        case .unknown:
            eventType = .sessionUnknown
        }

        return AgentEvent(
            id: sourceEvent.id,
            agentId: session.agentId,
            sessionId: session.id,
            type: eventType,
            timestamp: sourceEvent.timestamp,
            pid: session.pid,
            exitCode: sourceEvent.exitCode,
            message: sourceEvent.message,
            originType: sourceEvent.originType,
            sessionGeneration: session.generation,
            isStateOnly: sourceEvent.isStateOnly
        )
    }

    private func makeFeedbackEvent(
        for session: AgentSession,
        sourceEvent: AgentEvent,
        feedbackType: AgentEventType
    ) -> AgentEvent {
        AgentEvent(
            id: sourceEvent.id,
            agentId: session.agentId,
            sessionId: session.id,
            type: feedbackType,
            timestamp: sourceEvent.timestamp,
            pid: session.pid,
            exitCode: sourceEvent.exitCode,
            message: sourceEvent.message,
            originType: sourceEvent.originType,
            sessionGeneration: session.generation,
            isStateOnly: sourceEvent.isStateOnly
        )
    }
}
