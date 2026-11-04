import Darwin
import Foundation
import os.lock

/// 一次进程探测的结果。
public struct ProcessProbeResult: Sendable, Hashable {
    /// 进程当前是否存活（能通过 ps 确认）。
    public let isAlive: Bool
    /// 进程是否在过去一个探测窗口内有累计 CPU 增长（即在真正干活）。
    public let hasCPUActivity: Bool
    /// 本次采样到的累计 CPU 时间（秒）。用于两次比较判断活动。
    public let cumulativeCPUSeconds: TimeInterval?

    public init(isAlive: Bool, hasCPUActivity: Bool, cumulativeCPUSeconds: TimeInterval?) {
        self.isAlive = isAlive
        self.hasCPUActivity = hasCPUActivity
        self.cumulativeCPUSeconds = cumulativeCPUSeconds
    }

    public static let dead = ProcessProbeResult(
        isAlive: false,
        hasCPUActivity: false,
        cumulativeCPUSeconds: nil
    )
}

/// 冷启动发现的运行时进程快照。
public struct DetectedProcess: Sendable, Hashable {
    public let pid: Int32
    public let ppid: Int32
    public let agentId: String
    public let commandLine: String
    public let workingDirectory: String?
    public let startedAt: Date
    /// 顶级 .app 父进程的可执行名（由 Python 脚本追溯得到）；无时为 nil。
    public let parentName: String?

    public init(
        pid: Int32,
        ppid: Int32,
        agentId: String,
        commandLine: String,
        workingDirectory: String?,
        startedAt: Date,
        parentName: String? = nil
    ) {
        self.pid = pid
        self.ppid = ppid
        self.agentId = agentId
        self.commandLine = commandLine
        self.workingDirectory = workingDirectory
        self.startedAt = startedAt
        self.parentName = parentName
    }
}

/// 系统进程表命令抽象，便于测试替身。
///
/// 单 PID 探测走 libproc/kill，避免 watchdog 每轮为每个会话派生多个 ps 子进程。
/// 冷启动全表发现由 `PythonAgentProcessScanner` 调用 Python 脚本完成。
public protocol ProcessCommandProviding: Sendable {
    /// 探测指定 pid 的当前信息：返回 (累计CPU秒, 进程是否存活)。
    func probe(pid: Int32) -> (cpuSeconds: TimeInterval?, alive: Bool)
    /// 返回指定 pid 的可执行文件名（basename）；无法获取时返回 nil。
    func executableName(pid: Int32) -> String?
    /// 返回指定 pid 的父进程；无法获取时返回 nil。
    func parentPID(pid: Int32) -> Int32?
}

/// 单 PID 探测走 libproc/kill，避免 watchdog 每轮为每个会话派生多个 ps 子进程。
public struct SystemProcessCommand: ProcessCommandProviding, Sendable {
    public init() {}

    public func probe(pid: Int32) -> (cpuSeconds: TimeInterval?, alive: Bool) {
        guard pid > 0 else { return (nil, false) }
        return (cpuTime(pid: pid), isProcessAlive(pid: pid))
    }

    public func executableName(pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    public func parentPID(pid: Int32) -> Int32? {
        guard pid > 1 else { return nil }
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        guard result == Int32(size), info.pbi_ppid > 1 else { return nil }
        return Int32(info.pbi_ppid)
    }

    private func isProcessAlive(pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private func cpuTime(pid: Int32) -> TimeInterval? {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.stride
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(size))
        guard result == Int32(size) else { return nil }
        let nanoseconds = info.pti_total_user &+ info.pti_total_system
        return TimeInterval(nanoseconds) / 1_000_000_000
    }

}

/// 将 Hook 临时进程解析到承载该会话的 Agent 主进程。
public struct AgentProcessAncestryResolver: Sendable {
    private let processCommand: any ProcessCommandProviding

    public init(processCommand: any ProcessCommandProviding = SystemProcessCommand()) {
        self.processCommand = processCommand
    }

    public func resolve(
        agentId: String,
        pid: Int32?,
        parentPID: Int32?,
        maximumDepth: Int = 12
    ) -> Int32? {
        let expectedNames = AgentExecutableNames.names(for: agentId)
        guard !expectedNames.isEmpty else { return nil }

        for startPID in [pid, parentPID].compactMap({ $0 }) where startPID > 1 {
            var currentPID: Int32? = startPID
            var visited: Set<Int32> = []
            var depth = 0
            while let candidate = currentPID,
                  candidate > 1,
                  depth < maximumDepth,
                  visited.insert(candidate).inserted {
                if let name = processCommand.executableName(pid: candidate),
                   expectedNames.contains(name) {
                    return candidate
                }
                currentPID = processCommand.parentPID(pid: candidate)
                depth += 1
            }
        }
        return nil
    }
}

/// 对单个进程做持续探测，通过两次累计 CPU 比较判断其是否真的在忙。
/// 持有跨采样窗口的状态（CPU 增长比较），是 `HealthEvaluator` 的「Process 信号」来源。
/// 使用锁保护跨采样状态，并以 `@unchecked Sendable` 暴露给并发使用方。
public final class AgentProcessProbe: @unchecked Sendable {
    private let processCommand: ProcessCommandProviding
    private let lastCPU = OSAllocatedUnfairLock(initialState: [Int32: TimeInterval]())

    public init(processCommand: ProcessCommandProviding) {
        self.processCommand = processCommand
    }

    /// 探测单个进程。返回是否存活、以及相对上次采样的 CPU 增长。
    ///
    /// `expectedExecutables` 提供时额外校验可执行名：进程存活但可执行名不在集合内，
    /// 说明是 hook shell 退出后 pid 被复用到其它进程（pid recycling）造成的误报，
    /// 一律视为已死，避免把已关闭的会话误判为仍在运行。
    public func probe(pid: Int32, expectedExecutables: Set<String> = []) -> ProcessProbeResult {
        let (cpu, alive) = processCommand.probe(pid: pid)
        guard alive else {
            lastCPU.withLock { $0[pid] = nil }
            return .dead
        }
        if !expectedExecutables.isEmpty,
           let name = processCommand.executableName(pid: pid),
           !expectedExecutables.contains(name) {
            lastCPU.withLock { $0[pid] = nil }
            return .dead
        }
        let previous = lastCPU.withLock { samples -> TimeInterval? in
            let previous = samples[pid]
            if let cpu { samples[pid] = cpu }
            return previous
        }
        // 只有两次采样之间的 CPU 增长才算「正在干活」。首次采样无对照不算活动：
        // 否则任何有累计 CPU 的空闲进程（如闲置的 opencode TUI）都会被误判为活跃。
        let activity: Bool
        if let cpu, let previous {
            activity = cpu - previous > 0.0
        } else {
            activity = false
        }
        return ProcessProbeResult(
            isAlive: true,
            hasCPUActivity: activity,
            cumulativeCPUSeconds: cpu
        )
    }

    /// 直接探测存活（无 CPU 活动判断）。
    public func isAlive(pid: Int32) -> Bool {
        let (_, alive) = processCommand.probe(pid: pid)
        return alive
    }
}

/// Agent 的可执行名映射：供 pid 判活时的身份校验使用。
///
/// 只包含 PocketNotch 实际支持监听（Hook 可注入）的 Agent：claude / codex / gemini。
/// 冷启动进程扫描由 `PythonAgentProcessScanner` 调用 get_agent_sessions.py 完成，
/// 脚本白名单与此处保持一致。
public enum AgentExecutableNames {
    static let pairs: [(agentId: String, names: [String])] = [
        ("claude", ["claude", "claude-code"]),
        ("claude-code", ["claude", "claude-code"]),
        ("codex", ["codex"]),
        ("gemini", ["gemini"]),
    ]

    /// 给定 agentId 的合法可执行名集合；未知 agent 返回空集合（不校验）。
    public static func names(for agentId: String) -> Set<String> {
        Set(pairs.first(where: { $0.agentId == agentId })?.names ?? [])
    }
}

/// 冷启动 / 运行时的 Agent 进程扫描抽象。
///
/// 生产实现 `PythonAgentProcessScanner` 调用 get_agent_sessions.py 做整词匹配 +
/// 追溯顶级 .app 父进程；测试可用静态实现注入固定结果。
public protocol AgentProcessScanner: Sendable {
    func scan() -> [DetectedProcess]
}

/// 调用内置 Python 脚本扫描当前运行的 Agent 进程。
///
/// 脚本（get_agent_sessions.py）做整词匹配可执行名 + 追溯顶级 .app 父进程，
/// 与 AgentSessionsModule 展开态标签页共用同一份扫描逻辑。白名单只含
/// PocketNotch 实际支持监听的 Agent（claude / codex / gemini），与 AgentExecutableNames 对齐。
public struct PythonAgentProcessScanner: AgentProcessScanner {
    private let now: @Sendable () -> Date
    private let scriptPath: String

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
        self.scriptPath = Bundle.module.path(forResource: "get_agent_sessions", ofType: "py") ?? ""
    }

    public func scan() -> [DetectedProcess] {
        guard !scriptPath.isEmpty else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptPath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }
            return jsonArray.compactMap { dict -> DetectedProcess? in
                guard let pid = (dict["pid"] as? Int).map(Int32.init),
                      let agentId = dict["agent_name"] as? String else {
                    return nil
                }
                let ppid = (dict["parent_pid"] as? Int).map(Int32.init) ?? 0
                let commandLine = dict["session_name"] as? String ?? ""
                let parentName = dict["parent_name"] as? String
                return DetectedProcess(
                    pid: pid,
                    ppid: ppid,
                    agentId: agentId,
                    commandLine: commandLine,
                    workingDirectory: nil,
                    startedAt: now(),
                    parentName: parentName?.isEmpty == false ? parentName : nil
                )
            }
        } catch {
            return []
        }
    }
}
