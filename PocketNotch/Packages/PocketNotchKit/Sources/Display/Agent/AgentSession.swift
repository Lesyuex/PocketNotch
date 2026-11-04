import Foundation

/// 一次 Agent 会话的可变状态。由 `SessionStore` 统一维护。
///
/// Session 与 Runtime 分离（设计文档第 4 章）：
/// - `Session` 表示一次 Agent 工作会话，可以长期存在。
/// - `Runtime` 表示当前承载 Session 的实际运行实例（PID、命令、启动时间、健康）。
/// 一次 Session 在其生命周期内可能经历多个 Runtime（崩溃重启）。这里仅持有当前 Runtime 的关联。
public struct AgentSession: Identifiable, Hashable, Sendable {
    public let id: String
    public let agentId: String
    public private(set) var state: SessionState
    public private(set) var pid: Int32?
    /// 最后一条 Hook 事件时间（语义事件）。`lastActivityAt` 是综合活动信号时间（Hook/进程/输出…）。
    public private(set) var lastHookEventAt: Date?
    public private(set) var lastActivityAt: Date?
    public private(set) var stopRequested: Bool
    public private(set) var lastEventID: String?
    public private(set) var generation: Int
    public let createdAt: Date
    /// 当前承载该 Session 的 Runtime id（可空：仅通过 Hook 感知、尚未发现主进程时）。
    public private(set) var currentRuntimeId: String?
    /// PocketNotch 首次感知（attach）到该 Session 的时间。与 `startedAt`（Agent 真实启动）分开。
    public private(set) var attachedAt: Date?
    public private(set) var updatedAt: Date

    public init(
        id: String,
        agentId: String,
        state: SessionState = .idle,
        pid: Int32? = nil,
        lastHookEventAt: Date? = nil,
        lastActivityAt: Date? = nil,
        stopRequested: Bool = false,
        lastEventID: String? = nil,
        generation: Int = 0,
        createdAt: Date,
        currentRuntimeId: String? = nil,
        attachedAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.agentId = agentId
        self.state = state
        self.pid = pid
        self.lastHookEventAt = lastHookEventAt
        self.lastActivityAt = lastActivityAt
        self.stopRequested = stopRequested
        self.lastEventID = lastEventID
        self.generation = generation
        self.createdAt = createdAt
        self.currentRuntimeId = currentRuntimeId
        self.attachedAt = attachedAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public mutating func updateState(_ newState: SessionState, at date: Date) {
        if newState != state {
            state = newState
        }
        updatedAt = date
    }

    /// 记录一次 Hook 事件活动。它会同时更新 Hook 事件时间与综合活动时间。
    public mutating func markActivity(at date: Date, eventID: String?) {
        lastHookEventAt = date
        lastActivityAt = date
        lastEventID = eventID
        updatedAt = date
        setAttachedIfNeeded(at: date)
    }

    /// 记录一次非 Hook 的活动信号（进程 CPU/IO、输出、心跳）。只推进综合活动时间。
    public mutating func markRuntimeActivity(at date: Date) {
        lastActivityAt = date
        updatedAt = date
    }

    public mutating func updatePID(_ pid: Int32?, at date: Date) {
        self.pid = pid
        updatedAt = date
    }

    /// 关联/解除当前 Runtime。关联时同时推进活动时间。
    public mutating func attachRuntime(_ runtimeId: String?, at date: Date) {
        currentRuntimeId = runtimeId
        updatedAt = date
        setAttachedIfNeeded(at: date)
    }

    public mutating func setStopRequested(_ stopRequested: Bool, at date: Date) {
        self.stopRequested = stopRequested
        updatedAt = date
    }

    /// 重新开启一个终态 Session（同 sessionId 再次运行）。清空运行时状态，保留 generation。
    public mutating func reopen(at date: Date) {
        generation += 1
        stopRequested = false
        pid = nil
        lastHookEventAt = nil
        lastActivityAt = nil
        lastEventID = nil
        currentRuntimeId = nil
        attachedAt = nil
        updatedAt = date
    }

    private mutating func setAttachedIfNeeded(at date: Date) {
        if attachedAt == nil {
            attachedAt = date
        }
    }
}
