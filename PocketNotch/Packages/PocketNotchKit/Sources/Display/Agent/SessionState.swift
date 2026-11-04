import Foundation

/// Session 是 Agent Awareness 的核心状态。
///
/// 设计文档第六章：一个 Agent 可以拥有任意数量 Session，每个 Session 有自己的生命周期。
/// 该状态是业务真实状态，`Notification` 的消失绝不能反过来改变它。
///
/// 「无事件 ≠ 失败」原则（设计文档 12-14 章）：
/// `suspected` 表示 PocketNotch 当前无法确认 Runtime 是否仍健康；`lost` 表示已无运行证据但仍
/// 未收到明确终态事件。两者都不得在收到明确证据（session.completed / session.failed 等）
/// 之前武断判为失败。
public enum SessionState: String, Codable, CaseIterable, Hashable, Sendable {
    case idle
    case running
    case waitingApproval
    case suspected
    case lost
    case completed
    case failed
    case stopped
    case unknown

    /// 是否属于「让 Agent 进入 Agent Display Pool」的状态。
    /// 当前阶段唯一确定的显示规则：至少一个 Session 处于 Running。
    public var keepsAgentActive: Bool {
        switch self {
        case .running, .suspected, .lost, .waitingApproval:
            return true
        case .idle, .completed, .failed, .stopped, .unknown:
            return false
        }
    }

    /// 是否属于需要引起注意（等待确认 / 失败）的状态。
    public var needsAttention: Bool {
        switch self {
        case .waitingApproval, .failed, .suspected, .lost:
            return true
        case .idle, .running, .completed, .stopped, .unknown:
            return false
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .stopped, .unknown, .lost:
            return true
        case .idle, .running, .waitingApproval, .suspected:
            return false
        }
    }

    /// 该状态下「长时间无事件」的容忍时长。用于 LifecycleWatchdog 决定是否推进状态。
    /// - running / waitingApproval / suspected：任务可能正在长时间编译、下载或等待用户批准，
    ///   不应因无事件就结束；running 需要更长的静默容忍。
    /// - unknown / starting：缺乏事实信号，允许更短超时以便尽快收敛。
    /// - idle：创建后长时间没有实质进展视为异常，缩短超时。
    public var silentTimeout: TimeInterval {
        switch self {
        case .waitingApproval: return 24 * 3600
        case .running: return 1800
        case .suspected: return 300
        case .idle: return 300
        case .unknown: return 300
        case .lost, .completed, .failed, .stopped: return 0
        }
    }

    /// 面向显示层的状态文案（设计文档第 25 章）。
    /// 内部状态可以很细，但 UI 只暴露有限的友好语义。
    public var displayLabel: String {
        switch self {
        case .running: "运行中"
        case .waitingApproval: "等待中"
        case .suspected: "暂无响应"
        case .lost: "已失去连接"
        case .completed: "已完成"
        case .failed: "执行失败"
        case .stopped: "已停止"
        case .idle: "空闲"
        case .unknown: "状态未知"
        }
    }
}
