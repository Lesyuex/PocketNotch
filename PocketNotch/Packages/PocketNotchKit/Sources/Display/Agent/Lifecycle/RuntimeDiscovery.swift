import Foundation

/// 一次 Runtime 发现的结果：一个（可能是「启动前已存在」的）运行时进程。
public struct DiscoveredRuntime: Sendable, Hashable {
    public let agentId: String
    public let pid: Int32
    public let ppid: Int32
    public let commandLine: String
    public let startedAt: Date
    public let parentName: String?

    public init(agentId: String, pid: Int32, ppid: Int32, commandLine: String, startedAt: Date, parentName: String? = nil) {
        self.agentId = agentId
        self.pid = pid
        self.ppid = ppid
        self.commandLine = commandLine
        self.startedAt = startedAt
        self.parentName = parentName
    }
}

/// 冷启动 / 运行时的 Runtime 发现。
///
/// 设计文档第 16-18 章：PocketNotch 启动时不能只监听 Hook，还必须做
/// 「Subscribe → Discover → Reconcile → Probe → Ready」，以发现启动前已经运行的外部 Agent。
/// 主要来源是 `AgentProcessScanner`（生产实现为 `PythonAgentProcessScanner`），
/// Registry 快照作为辅助/增强。
public struct RuntimeDiscovery: Sendable {
    private let scanner: AgentProcessScanner
    private let registry: RuntimeRegistryStoring
    private let now: @Sendable () -> Date

    public init(
        scanner: AgentProcessScanner,
        registry: RuntimeRegistryStoring,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.scanner = scanner
        self.registry = registry
        self.now = now
    }

    /// 扫描当前正在运行的 Agent 进程。返回去重后的发现结果。
    public func scanRunningRuntimes() -> [DiscoveredRuntime] {
        // 进程表是事实来源；Registry 仅用于识别（本次发现不到但 Registry 里登记且仍在运行的进程）。
        var pidSeen: Set<Int32> = []
        var result: [DiscoveredRuntime] = []

        for detected in scanner.scan() {
            guard pidSeen.insert(detected.pid).inserted else { continue }
            result.append(DiscoveredRuntime(
                agentId: detected.agentId,
                pid: detected.pid,
                ppid: detected.ppid,
                commandLine: detected.commandLine,
                startedAt: detected.startedAt,
                parentName: detected.parentName
            ))
        }
        return result
    }

    /// 把发现的 Runtime 登记到 Registry（持久化，便于下次启动快速恢复）。
    public func persist(_ discovered: DiscoveredRuntime) {
        registry.save(StoredRuntimeRecord(
            runtimeId: runtimeID(for: discovered),
            sessionId: nil,
            agentId: discovered.agentId,
            pid: discovered.pid,
            commandLine: discovered.commandLine,
            startedAt: discovered.startedAt,
            lastProbeAt: now()
        ))
    }

    /// 生成稳定 Runtime id：agent-pid 复合，重启后保持一致以便对账。
    public func runtimeID(for discovered: DiscoveredRuntime) -> String {
        "\(discovered.agentId)-pid\(discovered.pid)"
    }
}
