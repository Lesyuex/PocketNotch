import Foundation

/// 多信号健康评估的结果。
///
/// 它不直接产出 SessionState（那属于状态机），而是产出 Runtime 层面的健康结论
/// （`RuntimeHealthLevel`）以及「是否应立即视为失去连接」。
public struct HealthVerdict: Sendable, Hashable {
    public let level: RuntimeHealthLevel
    /// 距上次综合活动的秒数（nil 表示从未有活动）。
    public let idleSeconds: TimeInterval?
    /// 已无可用的运行证据（进程消失且无心跳）。
    public let noRuntimeEvidence: Bool

    public init(
        level: RuntimeHealthLevel,
        idleSeconds: TimeInterval?,
        noRuntimeEvidence: Bool
    ) {
        self.level = level
        self.idleSeconds = idleSeconds
        self.noRuntimeEvidence = noRuntimeEvidence
    }
}

/// 把多信号（Hook / Process / Heartbeat / Output）综合成 Runtime 健康结论。
///
/// 设计文档第 11-13 章：Activity ≠ Hook。以下都是活动信号：Hook、PTY/输出、进程 CPU/IO、心跳。
/// 只有当「既无任何活动、又无任何运行证据」时，才允许走向 `dead`（供状态机推进到 LOST）。
public struct HealthEvaluator: Sendable {
    /// 进程保持 stale 到 dead 的判定阈值；无任何活动超过该时长视为失联候选。
    public let staleAfter: TimeInterval
    /// 完全没有运行证据（无进程、无心跳、无 hook）超过该时长即判定失联。
    public let lostAfter: TimeInterval
    /// 等待用户批准 / 显式等待状态下，静默容忍更长（不因无活动误判）。
    public let waitingTolerance: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        staleAfter: TimeInterval = 20,
        lostAfter: TimeInterval = 120,
        waitingTolerance: TimeInterval = 24 * 3600,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.staleAfter = staleAfter
        self.lostAfter = lostAfter
        self.waitingTolerance = waitingTolerance
        self.now = now
    }

    /// 评估一个 Runtime 的健康。
    ///
    /// - Parameters:
    ///   - state: Session 当前状态（waiting 状态使用更宽容的静默容忍，不因无活动自动失败）。
    ///   - signals: Runtime 的已知活动信号。
    ///   - processAlive: 进程探测是否判定存活。
    public func evaluate(
        state: SessionState,
        signals: RuntimeSignals,
        processAlive: Bool?
    ) -> HealthVerdict {
        let lastActivity = signals.lastActivityAt
        let idle = lastActivity.map { now().timeIntervalSince($0) }

        // 1) 进程存活是强运行证据，但「从未有 Hook 且近期也无 CPU 增长」说明这是被进程扫描
        // 抓到的空闲 Agent（如闲置的 opencode TUI），不是正在干活的会话，不能据此持续显示运行。
        // 只有存在工作证据（Hook 事件或进程 CPU 增长）才判定 alive。
        if let processAlive, processAlive {
            if signals.lastHookAt == nil {
                let cpuRecency = signals.lastProcessActivityAt.map { now().timeIntervalSince($0) }
                if cpuRecency.map { $0 > staleAfter } ?? true {
                    return HealthVerdict(level: .stale, idleSeconds: idle, noRuntimeEvidence: false)
                }
            }
            return HealthVerdict(level: .alive, idleSeconds: idle, noRuntimeEvidence: false)
        }

        // 2) 进程明确不存在：依据活动信号与状态容忍。
        if let processAlive, !processAlive {
            let recentlyActive = idle.map { $0 < staleAfter } ?? false
            if recentlyActive {
                return HealthVerdict(level: .alive, idleSeconds: idle, noRuntimeEvidence: false)
            }
            // waiting 状态容忍长时间静默，不因探不到进程而失败。
            if state == .waitingApproval {
                let idleWithinTolerance = idle.map { $0 < waitingTolerance } ?? true
                if idleWithinTolerance {
                    return HealthVerdict(level: .alive, idleSeconds: idle, noRuntimeEvidence: false)
                }
            }
            return HealthVerdict(level: .dead, idleSeconds: idle, noRuntimeEvidence: true)
        }

        // 3) 进程状态未知（nil，无法探测）：依据活动信号时间。
        if let idle {
            let tolerance = state == .waitingApproval ? waitingTolerance : staleAfter
            if idle < tolerance {
                return HealthVerdict(level: .alive, idleSeconds: idle, noRuntimeEvidence: false)
            }
            if idle > lostAfter {
                return HealthVerdict(level: .dead, idleSeconds: idle, noRuntimeEvidence: true)
            }
            return HealthVerdict(level: .stale, idleSeconds: idle, noRuntimeEvidence: false)
        }

        // 4) 完全没有任何信号 → unknown。
        return HealthVerdict(level: .unknown, idleSeconds: nil, noRuntimeEvidence: true)
    }
}
