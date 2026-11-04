import Foundation

/// Runtime 的实际健康程度。由 `HealthEvaluator` 综合多信号得出。
///
/// 设计文档第 6 章：不能只依赖 Hook。Runtime Health 至少观察 Hook / Process / PTY(输出) / Heartbeat / Activity。
public enum RuntimeHealthLevel: String, Codable, Sendable, Hashable {
    case unknown
    case alive
    case stale
    case dead
}

/// Runtime 健康信号读数。
///
/// - `lastHookAt`：最后一条语义 Hook 事件时间。
/// - `lastProcessActivityAt`：最后观测到进程 CPU/IO 有活动的时间。
/// - `lastHeartbeatAt`：最后一条显式心跳时间（可选，增强信号）。
/// - `lastOutputAt`：最后一条输出/PTY 数据时间（PocketNotch 不拥有 PTY 时可用 stdout 文件等近似）。
public struct RuntimeSignals: Sendable, Hashable {
    public var lastHookAt: Date?
    public var lastProcessActivityAt: Date?
    public var lastHeartbeatAt: Date?
    public var lastOutputAt: Date?

    public init(
        lastHookAt: Date? = nil,
        lastProcessActivityAt: Date? = nil,
        lastHeartbeatAt: Date? = nil,
        lastOutputAt: Date? = nil
    ) {
        self.lastHookAt = lastHookAt
        self.lastProcessActivityAt = lastProcessActivityAt
        self.lastHeartbeatAt = lastHeartbeatAt
        self.lastOutputAt = lastOutputAt
    }

    /// 综合活动时间：取所有已知信号中最近者。没有任何信号时为 nil。
    public var lastActivityAt: Date? {
        [lastHookAt, lastProcessActivityAt, lastHeartbeatAt, lastOutputAt]
            .compactMap { $0 }
            .max()
    }
}

/// Agent Runtime：当前承载某个 Session 的实际运行实例。
///
/// 与 `AgentSession`（长期工作会话）分离。一个 Session 在生命周期内可能有多个 Runtime。
/// PocketNotch 作为观察层不会启动 Runtime，而是通过 `RuntimeDiscovery`（进程扫描 / Registry）
/// 与 Hook 事件中的 pid 关联来识别它们。
public struct AgentRuntime: Identifiable, Hashable, Sendable {
    public let runtimeId: String
    public private(set) var sessionId: String?
    public let agentId: String

    public var id: String { runtimeId }
    public private(set) var pid: Int32?
    public private(set) var ppid: Int32?
    public private(set) var commandLine: String?
    public private(set) var workingDirectory: String?
    public private(set) var sourceApplication: String?
    public private(set) var startedAt: Date
    public private(set) var lastProbeAt: Date?
    public private(set) var endAt: Date?
    public private(set) var health: RuntimeHealthLevel
    public private(set) var signals: RuntimeSignals

    public init(
        runtimeId: String,
        sessionId: String?,
        agentId: String,
        pid: Int32? = nil,
        ppid: Int32? = nil,
        commandLine: String? = nil,
        workingDirectory: String? = nil,
        sourceApplication: String? = nil,
        startedAt: Date,
        lastProbeAt: Date? = nil,
        endAt: Date? = nil,
        health: RuntimeHealthLevel = .unknown,
        signals: RuntimeSignals = RuntimeSignals()
    ) {
        self.runtimeId = runtimeId
        self.sessionId = sessionId
        self.agentId = agentId
        self.pid = pid
        self.ppid = ppid
        self.commandLine = commandLine
        self.workingDirectory = workingDirectory
        self.sourceApplication = sourceApplication
        self.startedAt = startedAt
        self.lastProbeAt = lastProbeAt
        self.endAt = endAt
        self.health = health
        self.signals = signals
    }

    public mutating func asAlive(at date: Date, signals: RuntimeSignals? = nil) {
        health = .alive
        lastProbeAt = date
        endAt = nil
        if let signals {
            self.signals = signals
        }
    }

    public mutating func asStale(at date: Date) {
        health = .stale
        lastProbeAt = date
    }

    public mutating func asDead(at date: Date) {
        health = .dead
        lastProbeAt = date
        endAt = endAt ?? date
    }

    public mutating func bind(sessionId: String, pid: Int32?, at date: Date) {
        self.sessionId = sessionId
        self.pid = pid
        lastProbeAt = date
    }

    /// 进程是否仍被探测为存活。
    public var isProcessAlive: Bool { health != .dead }
}
