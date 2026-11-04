import Foundation

protocol CodexAppServerRPC: AnyObject {
    func start() throws
    func notify(method: String, params: [String: Any]) throws
    func call(method: String, params: [String: Any]) throws -> [String: Any]
    func stop()
}

enum CodexHookAuthorizationError: LocalizedError {
    case executableNotFound
    case appServer(String)
    case missingHooks([String])
    case invalidResponse(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "找不到 Codex CLI"
        case .appServer(let message):
            return "Codex 授权服务失败：\(message)"
        case .missingHooks(let events):
            return "Codex 未返回完整的 Pocket Notch Hook：\(events.joined(separator: "、"))"
        case .invalidResponse(let field):
            return "Codex 授权响应缺少 \(field)"
        case .timedOut:
            return "Codex 授权服务响应超时"
        }
    }
}

/// Uses Codex's own app-server protocol to retrieve hook hashes and persist
/// trust. PocketNotch never computes or copies a trusted hash itself.
final class CodexHookAuthorizer: @unchecked Sendable {
    private struct ExpectedHook {
        let eventName: String
        let type: String
    }

    private static let expectedHooks = [
        ExpectedHook(eventName: "sessionStart", type: "session_start"),
        ExpectedHook(eventName: "sessionEnd", type: "session_end"),
        ExpectedHook(eventName: "userPromptSubmit", type: "agent_start"),
        ExpectedHook(eventName: "preToolUse", type: "tool_start"),
        ExpectedHook(eventName: "permissionRequest", type: "waiting_approval"),
        ExpectedHook(eventName: "postToolUse", type: "tool_end"),
        ExpectedHook(eventName: "stop", type: "stop_requested"),
    ]

    private let scriptURL: URL
    private let homeDirectory: URL
    private let rpc: CodexAppServerRPC

    init(
        scriptURL: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        workingDirectory: URL? = nil,
        executableURL: URL? = nil
    ) {
        self.scriptURL = scriptURL
        self.homeDirectory = homeDirectory
        self.rpc = CodexAppServerProcessRPC(
            executableURL: executableURL,
            workingDirectory: workingDirectory ?? homeDirectory
        )
    }

    init(scriptURL: URL, homeDirectory: URL, rpc: CodexAppServerRPC) {
        self.scriptURL = scriptURL
        self.homeDirectory = homeDirectory
        self.rpc = rpc
    }

    func authorize() async throws {
        try await Task.detached { [self] in
            try authorizeSynchronously()
        }.value
    }

    private func authorizeSynchronously() throws {
        try rpc.start()
        defer { rpc.stop() }

        _ = try rpc.call(method: "initialize", params: [
            "clientInfo": [
                "name": "pocketnotch",
                "title": "Pocket Notch",
                "version": "1.0",
            ],
            "capabilities": ["experimentalApi": false],
        ])
        try rpc.notify(method: "initialized", params: [:])

        let listResult = try rpc.call(method: "hooks/list", params: [
            "cwds": [homeDirectory.path],
        ])
        let trustedHooks = try matchingHooks(from: listResult)
        let edits = trustedHooks.map { hook in
            [
                "keyPath": "hooks.state.\"\(Self.escapeKeyPathSegment(hook.key))\".trusted_hash",
                "value": hook.currentHash,
                "mergeStrategy": "upsert",
            ] as [String: Any]
        }

        _ = try rpc.call(method: "config/batchWrite", params: [
            "edits": edits,
            "filePath": homeDirectory.appendingPathComponent(".codex/config.toml").path,
            "reloadUserConfig": true,
        ])
    }

    private func matchingHooks(from result: [String: Any]) throws -> [(key: String, currentHash: String)] {
        guard let entries = result["data"] as? [[String: Any]] else {
            throw CodexHookAuthorizationError.invalidResponse("data")
        }
        let hooks = entries.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
        let sourcePath = homeDirectory.appendingPathComponent(".codex/hooks.json").path

        var matches: [(key: String, currentHash: String)] = []
        var missingEvents: [String] = []
        for expected in Self.expectedHooks {
            let expectedCommand = "\"\(scriptURL.path)\" emit codex \(expected.type)"
            let candidates = hooks.filter { hook in
                hook["eventName"] as? String == expected.eventName
                    && hook["handlerType"] as? String == "command"
                    && hook["source"] as? String == "user"
                    && hook["sourcePath"] as? String == sourcePath
                    && hook["command"] as? String == expectedCommand
                    && hook["isManaged"] as? Bool == false
            }
            guard candidates.count == 1,
                  let key = candidates[0]["key"] as? String,
                  let currentHash = candidates[0]["currentHash"] as? String,
                  currentHash.hasPrefix("sha256:") else {
                missingEvents.append(expected.eventName)
                continue
            }
            matches.append((key, currentHash))
        }

        guard missingEvents.isEmpty else {
            throw CodexHookAuthorizationError.missingHooks(missingEvents)
        }
        return matches
    }

    private static func escapeKeyPathSegment(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private final class CodexAppServerProcessRPC: CodexAppServerRPC, @unchecked Sendable {
    private let explicitExecutableURL: URL?
    private let workingDirectory: URL
    private let timeout: TimeInterval
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private let stateLock = NSLock()

    private var readBuffer = Data()
    private var nextID = 1
    private var timeoutWorkItem: DispatchWorkItem?
    private var didTimeOut = false

    init(executableURL: URL?, workingDirectory: URL, timeout: TimeInterval = 10) {
        self.explicitExecutableURL = executableURL
        self.workingDirectory = workingDirectory
        self.timeout = timeout
    }

    func start() throws {
        guard let executableURL = explicitExecutableURL ?? Self.resolveCodexExecutable() else {
            throw CodexHookAuthorizationError.executableNotFound
        }
        if process?.isRunning == true {
            throw CodexHookAuthorizationError.appServer("授权服务已在运行")
        }

        // Process instances cannot be launched twice. Recreate the process and
        // pipes for every authorization attempt, including retries after a
        // previous attempt timed out or failed.
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
        readBuffer = Data()
        nextID = 1
        stateLock.withLock { didTimeOut = false }

        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.currentDirectoryURL = workingDirectory
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()

        let workItem = DispatchWorkItem { [weak self, weak process] in
            guard let self, let process else { return }
            let isCurrentAttempt = self.stateLock.withLock {
                guard self.process === process else { return false }
                self.didTimeOut = true
                return true
            }
            if isCurrentAttempt, process.isRunning {
                process.terminate()
            }
        }
        timeoutWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    func notify(method: String, params: [String: Any]) throws {
        try write(["method": method, "params": params])
    }

    func call(method: String, params: [String: Any]) throws -> [String: Any] {
        let id = nextID
        nextID += 1
        try write(["id": id, "method": method, "params": params])

        while let message = try readMessage() {
            guard (message["id"] as? NSNumber)?.intValue == id else { continue }
            if let error = message["error"] as? [String: Any] {
                let detail = error["message"] as? String ?? String(describing: error)
                throw CodexHookAuthorizationError.appServer(detail)
            }
            guard let result = message["result"] as? [String: Any] else {
                throw CodexHookAuthorizationError.invalidResponse("result")
            }
            return result
        }

        if stateLock.withLock({ didTimeOut }) {
            throw CodexHookAuthorizationError.timedOut
        }
        let stderr = errorPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        let detail = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        throw CodexHookAuthorizationError.appServer(detail?.isEmpty == false ? detail! : "连接已关闭")
    }

    func stop() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        try? inputPipe?.fileHandleForWriting.close()
        if let process {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            self.process = nil
        }
    }

    private func write(_ object: [String: Any]) throws {
        guard let inputPipe else {
            throw CodexHookAuthorizationError.appServer("授权服务未启动")
        }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try inputPipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func readMessage() throws -> [String: Any]? {
        guard let outputPipe else {
            throw CodexHookAuthorizationError.appServer("授权服务未启动")
        }
        while true {
            if let newline = readBuffer.firstIndex(of: 0x0A) {
                let line = readBuffer[..<newline]
                readBuffer.removeSubrange(...newline)
                guard !line.isEmpty else { continue }
                return try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            }

            let chunk = outputPipe.fileHandleForReading.availableData
            if chunk.isEmpty {
                return nil
            }
            readBuffer.append(chunk)
        }
    }

    private static func resolveCodexExecutable() -> URL? {
        var candidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex") }
        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex"),
        ])
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
