import Foundation

/// Runtime Registry 持久化：把已发现的 Runtime 快照写入 `~/.pocketnotch/runtimes/`。
///
/// 作用：PocketNotch 重启后能恢复「启动前已存在 / 已感知」的 Session 与 Runtime（设计文档第 16 章）。
/// PocketNotch 作为观察层不主动启动 Agent，但可以在冷启动发现后，把结果登记到 Registry，
/// 供下次启动快速重建，避免每次都全量扫描。
public protocol RuntimeRegistryStoring: Sendable {
    func loadAll() -> [StoredRuntimeRecord]
    func save(_ record: StoredRuntimeRecord)
    func remove(runtimeId: String)
}

/// 持久化到磁盘的 Runtime 记录。
public struct StoredRuntimeRecord: Codable, Sendable {
    public let runtimeId: String
    public let sessionId: String?
    public let agentId: String
    public let pid: Int32?
    public let commandLine: String?
    public let startedAt: Date
    public let lastProbeAt: Date?

    public init(
        runtimeId: String,
        sessionId: String?,
        agentId: String,
        pid: Int32?,
        commandLine: String?,
        startedAt: Date,
        lastProbeAt: Date?
    ) {
        self.runtimeId = runtimeId
        self.sessionId = sessionId
        self.agentId = agentId
        self.pid = pid
        self.commandLine = commandLine
        self.startedAt = startedAt
        self.lastProbeAt = lastProbeAt
    }
}

/// 基于文件系统的 Runtime Registry 实现。
public final class FileRuntimeRegistry: RuntimeRegistryStoring, @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pocketnotch", isDirectory: true)
            .appendingPathComponent("runtimes", isDirectory: true)
        self.directory = base
    }

    public func loadAll() -> [StoredRuntimeRecord] {
        lock.lock(); defer { lock.unlock() }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(StoredRuntimeRecord.self, from: data)
            }
    }

    public func save(_ record: StoredRuntimeRecord) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = directory.appendingPathComponent("\(record.runtimeId).json")
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }

    public func remove(runtimeId: String) {
        lock.lock(); defer { lock.unlock() }
        let url = directory.appendingPathComponent("\(runtimeId).json")
        try? FileManager.default.removeItem(at: url)
    }
}
