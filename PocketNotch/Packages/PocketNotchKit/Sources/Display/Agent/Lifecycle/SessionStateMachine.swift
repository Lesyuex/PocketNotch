import Foundation

/// Session 生命周期状态机。负责把「事件」+「运行时健康」转换成可信的最终状态。
///
/// 核心原则（设计文档第 3、12-14 章）：
/// - 没有 Hook ≠ 没有运行。只有「有明确终态证据」或「已无任何运行证据且持续超时」才收敛终态。
/// - 无法确认时进入 `suspected`（可能正常/可能失联），最终无证据进入 `lost`。
/// - `waitingApproval` 可无限等待，绝不因无活动自动失败。
public struct SessionStateMachine: Sendable {
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    /// 在一次健康探测 tick 中，根据新健康判定推进 Session 状态。
    /// - Returns: 返回新状态；若与当前相同返回当前。
    public func advance(
        current: SessionState,
        verdict: HealthVerdict,
        lastActivityAt: Date?
    ) -> SessionState {
        // 明确的终态证据优先：任何终态都返回当前（终态由事件系统收口，健康检查不改变已经结束的会话）。
        if current.isTerminal {
            return current
        }

        switch verdict.level {
        case .alive:
            switch current {
            case .suspected, .lost:
                return .running // 重新确认存活
            case .waitingApproval, .running, .idle, .unknown:
                return current
            case .completed, .failed, .stopped:
                return current
            }
        case .stale:
            switch current {
            case .waitingApproval:
                return current // 等待可以被无限容忍
            case .idle, .unknown:
                // 无实质进展的会话 + 信号变stale → 长时间无活动判 suspected。
                return .suspected
            case .running:
                return .suspected
            case .suspected:
                // 已在 suspected 且持续静默超过该状态容忍时长 → lost。
                if let lastActivityAt,
                   now().timeIntervalSince(lastActivityAt) > SessionState.suspected.silentTimeout {
                    return .lost
                }
                return current
            case .lost, .completed, .failed, .stopped:
                return current
            }
        case .dead:
            switch current {
            case .waitingApproval:
                return current // 等待即使进程探不到也不主动失败（允许外部真正恢复）
            case .idle, .running, .suspected, .unknown:
                return .lost
            case .lost, .completed, .failed, .stopped:
                return current
            }
        case .unknown:
            return current
        }
    }

    /// 收到一条语义事件时，由事件驱动的状态推进（与现有 `SessionStateManager.resolveState` 语义保持一致并补充新状态）。
    public func onEvent(current: SessionState, eventType: AgentEventType) -> SessionState {
        if current.isTerminal {
            // 只有明确的「重新运行」事件才允许 reopen；该判断由调用方（SessionStateManager）处理。
            return current
        }
        switch eventType {
        case .sessionCreated: return .idle
        case .sessionRunning: return current == .waitingApproval ? current : .running
        case .sessionWaitingApproval: return .waitingApproval
        case .sessionCompleted: return .completed
        case .sessionFailed: return .failed
        case .sessionStopped: return .stopped
        case .sessionUnknown: return .unknown
        case .sessionStopRequested: return current
        case .sessionEnded: return current // 由调用方结合 exitCode / stopRequested 决定
        }
    }
}
