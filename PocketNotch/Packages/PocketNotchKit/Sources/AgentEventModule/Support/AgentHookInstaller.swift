import Foundation

/// 支持的 CLI Agent。
public enum AgentHookAgent: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case gemini

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex CLI"
        case .gemini: "Gemini CLI"
        }
    }

    /// 是否自动注入（Claude 稳定；Codex/Gemini 事件名随版本浮动，标注为最佳适配）。
    public var isStableSupport: Bool { self == .claude }

    fileprivate var binaryName: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        case .gemini: "gemini"
        }
    }

    fileprivate var configDirectory: String {
        switch self {
        case .claude: ".claude"
        case .codex: ".codex"
        case .gemini: ".gemini"
        }
    }

    fileprivate var configFileName: String {
        switch self {
        case .claude: "settings.json"
        case .codex: "hooks.json"
        case .gemini: "settings.json"
        }
    }

    func configURL(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent(configDirectory, isDirectory: true)
            .appendingPathComponent(configFileName)
    }
}

/// 某个 Agent 的 Hook 安装状态。
public struct AgentHookStatus: Identifiable, Sendable, Equatable {
    public let agent: AgentHookAgent
    public let isDetected: Bool
    public let isInstalled: Bool
    public let needsAuthorization: Bool
    public let note: String?

    public var id: String { agent.rawValue }
}

/// 安装/卸载结果。
public struct AgentHookResult: Sendable, Equatable {
    public let agent: AgentHookAgent
    public let success: Bool
    public let message: String
}

/// 负责把 PocketNotch 的 Hook 配置注入各 CLI 的本地配置文件。
///
/// 安全策略：
/// - 首次注入前把原始配置备份为 `<config>.pocketnotchbackup`，卸载时恢复备份。
/// - 已存在用户自己写的 `hooks` 配置时，Claude 采用数组追加；Codex/Gemini 无法安全合并则拒绝注入并提示。
public final class AgentHookInstaller: @unchecked Sendable {
    private let port: UInt16
    private let scriptURL: URL
    private let homeDirectory: URL

    public init(port: UInt16, scriptURL: URL, homeDirectory: URL? = nil) {
        self.port = port
        self.scriptURL = scriptURL
        self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
    }

private let markerKey = "__pocketnotch_agent_hooks__"

    private func configURL(_ agent: AgentHookAgent) -> URL {
        agent.configURL(homeDirectory: homeDirectory)
    }

    // MARK: - Detect

    public func detectStatuses() -> [AgentHookStatus] {
        AgentHookAgent.allCases.map { agent in
            let detected = isDetected(agent)
            let installed = isInstalled(agent)
            let needsAuthorization = agent == .codex && installed && !areCodexHooksTrusted()
            let note: String?
            if !detected {
                note = "未检测到 \(agent.displayName)（未安装或不在 PATH）"
            } else if agent == .claude && isClaudeHooksPresent(agent) && !isInstalled(agent) {
                note = "已有 hooks 配置，可安全追加"
            } else if needsAuthorization {
                note = "需要重新开启并完成授权"
            } else if !agent.isStableSupport && installed {
                note = "已开启（事件名以官方文档为准）"
            } else {
                note = nil
            }
            return AgentHookStatus(
                agent: agent,
                isDetected: detected,
                isInstalled: installed,
                needsAuthorization: needsAuthorization,
                note: note
            )
        }
    }

    public func isInstalled(_ agent: AgentHookAgent) -> Bool {
        if agent == .claude {
            return isClaudeInstalled(agent)
        }
        if agent == .codex {
            return isCodexInstalled(agent)
        }
        guard let data = try? Data(contentsOf: configURL(agent)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object[markerKey] != nil else {
            return false
        }
        return true
    }

    /// 是否存在 PocketNotch 管理的 Hook。用于软件更新时识别旧版已开启项，
    /// 不要求旧配置已经满足新版本的完整事件映射。
    public func hasManagedHook(_ agent: AgentHookAgent) -> Bool {
        guard let data = try? Data(contentsOf: configURL(agent)),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        return containsManagedHook(in: object)
    }

    // MARK: - Install / Uninstall

    public func install(_ agent: AgentHookAgent) -> AgentHookResult {
        do {
            try backupIfNeeded(agent)
            switch agent {
            case .claude: try injectClaude()
            case .codex: try injectCodex()
            case .gemini: try injectGemini()
            }
            return AgentHookResult(agent: agent, success: true, message: "已开启")
        } catch {
            return AgentHookResult(agent: agent, success: false, message: error.localizedDescription)
        }
    }

    public func uninstall(_ agent: AgentHookAgent) -> AgentHookResult {
        do {
            try restoreBackup(agent)
            return AgentHookResult(agent: agent, success: true, message: "已关闭并恢复原配置")
        } catch {
            return AgentHookResult(agent: agent, success: false, message: error.localizedDescription)
        }
    }

    // MARK: - Detection helpers

    private func isDetected(_ agent: AgentHookAgent) -> Bool {
        if binaryExists(agent.binaryName) { return true }
        return FileManager.default.fileExists(atPath: configURL(agent).path)
    }

    private func binaryExists(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return !data.isEmpty
        } catch {
            return false
        }
    }

    private func containsManagedHook(in value: Any) -> Bool {
        if let string = value as? String {
            return string.contains(scriptURL.path)
        }
        if let array = value as? [Any] {
            return array.contains(where: containsManagedHook)
        }
        if let dictionary = value as? [String: Any] {
            if dictionary[markerKey] != nil {
                return true
            }
            return dictionary.values.contains(where: containsManagedHook)
        }
        return false
    }

    private func isClaudeHooksPresent(_ agent: AgentHookAgent) -> Bool {
        guard let data = try? Data(contentsOf: configURL(agent)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["hooks"] != nil
    }

    private func isClaudeInstalled(_ agent: AgentHookAgent) -> Bool {
        guard let data = try? Data(contentsOf: configURL(agent)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = object["hooks"] as? [String: Any] else {
            return false
        }
        let requiredEvents = [
            "SessionStart",
            "SessionEnd",
            "UserPromptSubmit",
            "PreToolUse",
            "PostToolUse",
            "PreCompact",
            "Stop",
        ]
        return requiredEvents.allSatisfy { event in
            let groups = hooks[event] as? [[String: Any]] ?? []
            return groups
                .flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
                .contains { ($0["command"] as? String)?.contains(scriptURL.path) == true }
        }
    }

    private func isCodexInstalled(_ agent: AgentHookAgent) -> Bool {
        guard let data = try? Data(contentsOf: configURL(agent)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        guard let hooks = object["hooks"] as? [String: Any] else { return false }
        let requiredEvents = [
            "SessionStart",
            "SessionEnd",
            "UserPromptSubmit",
            "PreToolUse",
            "PermissionRequest",
            "PostToolUse",
            "Stop",
        ]
        return requiredEvents.allSatisfy { event in
            let groups = hooks[event] as? [[String: Any]] ?? []
            return groups
                .flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
                .contains { ($0["command"] as? String)?.contains(scriptURL.path) == true }
        }
    }

    private func areCodexHooksTrusted() -> Bool {
        guard let config = try? String(
            contentsOf: homeDirectory.appendingPathComponent(".codex/config.toml"),
            encoding: .utf8
        ), let identities = codexHookIdentities(), identities.count == 7 else {
            return false
        }
        return identities.allSatisfy { identity in
            let header = "[hooks.state.\"\(identity)\"]"
            guard let headerRange = config.range(of: header) else { return false }
            let remainder = config[headerRange.upperBound...]
            let sectionEnd = remainder.range(of: "\n[")?.lowerBound ?? remainder.endIndex
            return remainder[..<sectionEnd].contains("trusted_hash")
        }
    }

    private func codexHookIdentities() -> [String]? {
        let url = configURL(.codex)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = object["hooks"] as? [String: Any] else {
            return nil
        }

        let events = [
            (json: "SessionStart", state: "session_start"),
            (json: "SessionEnd", state: "session_end"),
            (json: "UserPromptSubmit", state: "user_prompt_submit"),
            (json: "PreToolUse", state: "pre_tool_use"),
            (json: "PermissionRequest", state: "permission_request"),
            (json: "PostToolUse", state: "post_tool_use"),
            (json: "Stop", state: "stop"),
        ]
        return events.compactMap { event in
            let groups = hooks[event.json] as? [[String: Any]] ?? []
            for (groupIndex, group) in groups.enumerated() {
                let handlers = group["hooks"] as? [[String: Any]] ?? []
                for (handlerIndex, handler) in handlers.enumerated() {
                    if (handler["command"] as? String)?.contains(scriptURL.path) == true {
                        return "\(url.path):\(event.state):\(groupIndex):\(handlerIndex)"
                    }
                }
            }
            return nil
        }
    }

    // MARK: - File plumbing

    private func backupIfNeeded(_ agent: AgentHookAgent) throws {
        let backupURL = configURL(agent).appendingPathExtension("pocketnotchbackup")
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        let dir = configURL(agent).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let original = (try? Data(contentsOf: configURL(agent))) ?? Data()
        try original.write(to: backupURL)
    }

    private func restoreBackup(_ agent: AgentHookAgent) throws {
        let backupURL = configURL(agent).appendingPathExtension("pocketnotchbackup")
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            try stripMarkers(agent)
            return
        }
        let backup = try Data(contentsOf: backupURL)
        if backup.isEmpty {
            if FileManager.default.fileExists(atPath: configURL(agent).path) {
                try FileManager.default.removeItem(at: configURL(agent))
            }
        } else {
            try backup.write(to: configURL(agent))
        }
        try FileManager.default.removeItem(at: backupURL)
    }

    private func stripMarkers(_ agent: AgentHookAgent) throws {
        switch agent {
        case .claude:
            guard let data = try? Data(contentsOf: configURL(agent)),
                  var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            object.removeValue(forKey: markerKey)
            if var hooks = object["hooks"] as? [String: Any] {
                removePocketNotchHookEntries(from: &hooks)
                if hooks.isEmpty {
                    object.removeValue(forKey: "hooks")
                } else {
                    object["hooks"] = hooks
                }
            }
            let output = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try output.write(to: configURL(agent))
        case .gemini:
            guard let data = try? Data(contentsOf: configURL(agent)),
                  var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            object.removeValue(forKey: markerKey)
            if let hooks = object["hooks"] as? [String: Any], hooks.isEmpty {
                object.removeValue(forKey: "hooks")
            }
            let output = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try output.write(to: configURL(agent))
        case .codex:
            guard let data = try? Data(contentsOf: configURL(agent)),
                  var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            object.removeValue(forKey: markerKey)
            if var hooks = object["hooks"] as? [String: Any] {
                for key in hooks.keys {
                    var entries = hooks[key] as? [[String: Any]] ?? []
                    entries.removeAll { entry in
                        guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
                        return hookList.contains { ($0["command"] as? String)?.contains(scriptURL.path) == true }
                    }
                    if entries.isEmpty {
                        hooks.removeValue(forKey: key)
                    } else {
                        hooks[key] = entries
                    }
                }
                if hooks.isEmpty {
                    object.removeValue(forKey: "hooks")
                } else {
                    object["hooks"] = hooks
                }
            }
            let output = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try output.write(to: configURL(agent))
        }
    }

    // MARK: - Claude (settings.json)

    private func injectClaude() throws {
        let url = configURL(.claude)
        let existing = (try? Data(contentsOf: url)).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        } ?? [:]

        var root = existing
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        // Remove PocketNotch entries from both the legacy flat format and the current
        // nested Claude format before writing the canonical event mapping.
        removePocketNotchHookEntries(from: &hooks)

        let eventCommands: [(String, String)] = [
            ("SessionStart", "session_start"),
            ("SessionEnd", "session_end"),
            ("UserPromptSubmit", "agent_start"),
            ("PreToolUse", "tool_start"),
            ("PostToolUse", "tool_end"),
            ("PreCompact", "thinking"),
            ("Stop", "stop_requested"),
        ]
        for (event, type) in eventCommands {
            let command = "\(scriptPathQuoted) emit claude \(type)"
            appendClaudeCommand(&hooks, event: event, command: command)
        }

        root["hooks"] = hooks
        root[markerKey] = true
        let output = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: url)
    }

    private func injectGemini() throws {
        let url = configURL(.gemini)
        let existing = (try? Data(contentsOf: url)).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        } ?? [:]

        var root = existing
        guard root["hooks"] == nil else {
            throw AgentHookError.unmergeable("已有 hooks 配置，请手动合并")
        }
        root["hooks"] = [
            "BeforeEdit": [hookDict("\(scriptPathQuoted) emit gemini tool_start --tool Edit")],
            "BeforeThink": [hookDict("\(scriptPathQuoted) emit gemini thinking")],
            "AfterTool": [hookDict("\(scriptPathQuoted) emit gemini tool_end")],
        ]
        root[markerKey] = true
        let output = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: url)
    }

    private func injectCodex() throws {
        let url = configURL(.codex)
        let existing = (try? Data(contentsOf: url)).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        } ?? [:]

        var root = existing
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for event in hooks.keys {
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries.removeAll { entry in
                let hookList = entry["hooks"] as? [[String: Any]] ?? []
                return hookList.contains { ($0["command"] as? String)?.contains(scriptURL.path) == true }
            }
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }

        let script = "\"\(scriptURL.path)\""
        let events: [(event: String, type: String, matcher: String?)] = [
            ("SessionStart", "session_start", "startup|resume"),
            ("SessionEnd", "session_end", nil),
            ("UserPromptSubmit", "agent_start", nil),
            ("PreToolUse", "tool_start", nil),
            ("PermissionRequest", "waiting_approval", nil),
            ("PostToolUse", "tool_end", nil),
            ("Stop", "stop_requested", nil),
        ]
        for (event, type, matcher) in events {
            var entry: [String: Any] = [
                "hooks": [[
                    "type": "command",
                    "command": "\(script) emit codex \(type)",
                    "timeout": 5,
                ] as [String: Any]],
            ]
            if let matcher {
                entry["matcher"] = matcher
            }
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries.append(entry)
            hooks[event] = entries
        }

        root["hooks"] = hooks
        root.removeValue(forKey: markerKey)
        let output = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: url)
    }

    // MARK: - Command builders

    private var scriptPathQuoted: String {
        "\"\(scriptURL.path)\""
    }

    private func hookCommand(agent: String, type: String, sessionVar: String, extra: String?) -> String {
        var args = "emit \(agent) \(type) --session \(sessionVar)"
        if let extra {
            args += " \(extra)"
        }
        return "\(scriptPathQuoted) \(args)"
    }

    private func hookDict(_ cmd: String) -> [String: String] {
        ["cmd": cmd, "matcher": "*"]
    }

    private func appendClaudeCommand(_ hooks: inout [String: Any], event: String, command: String) {
        var entries = hooks[event] as? [[String: Any]] ?? []
        entries.append([
            "hooks": [[
                "type": "command",
                "command": command,
            ] as [String: Any]],
        ])
        hooks[event] = entries
    }

    private func removePocketNotchHookEntries(from hooks: inout [String: Any]) {
        for event in hooks.keys {
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries.removeAll { entry in
                if (entry["command"] as? String)?.contains(scriptURL.path) == true {
                    return true
                }
                let hookList = entry["hooks"] as? [[String: Any]] ?? []
                return hookList.contains {
                    ($0["command"] as? String)?.contains(scriptURL.path) == true
                }
            }
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }
    }
}

enum AgentHookError: LocalizedError {
    case unmergeable(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unmergeable(let message): message
        case .writeFailed(let message): message
        }
    }
}
