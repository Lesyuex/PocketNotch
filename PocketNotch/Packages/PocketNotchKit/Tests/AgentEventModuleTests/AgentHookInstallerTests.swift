import XCTest
@testable import AgentEventModule

final class AgentHookInstallerTests: XCTestCase {
    private var tempHome: URL!
    private var installer: AgentHookInstaller!
    private var scriptURL: URL!

    override func setUpWithError() throws {
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("PocketNotchAgentHookTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        scriptURL = tempHome.appendingPathComponent("agent-events.sh")
        try Data("#! /bin/sh\n".utf8).write(to: scriptURL)
        installer = AgentHookInstaller(port: 58421, scriptURL: scriptURL, homeDirectory: tempHome)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempHome)
    }

    func testClaudeInstallAddsMarkerAndRestoresOnUninstall() throws {
        let configDir = tempHome.appendingPathComponent(".claude", isDirectory: true)
        let config = configDir.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let original = #"{"name":"before"}"#
        try original.data(using: .utf8)!.write(to: config)

        let result = installer.install(.claude)
        XCTAssertTrue(result.success, "install failed: \(result.message)")
        XCTAssertTrue(installer.isInstalled(.claude), "marker should exist")
        XCTAssertTrue(installer.hasManagedHook(.claude))
        let modified = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(modified.contains("__pocketnotch_agent_hooks__"))
        XCTAssertTrue(modified.contains("SessionStart"))
        XCTAssertTrue(modified.contains("\"hooks\""))
        XCTAssertFalse(modified.contains("CLAUDE_SESSION_ID"))

        let uninstallResult = installer.uninstall(.claude)
        XCTAssertTrue(uninstallResult.success, "uninstall failed: \(uninstallResult.message)")
        let restored = try String(contentsOf: config, encoding: .utf8)
        XCTAssertEqual(restored, original, "uninstall should restore original file")
        XCTAssertFalse(installer.hasManagedHook(.claude))
    }

    func testInstallCreatesConfigWhenMissing() {
        let result = installer.install(.claude)
        XCTAssertTrue(result.success, "install failed: \(result.message)")
        let config = tempHome.appendingPathComponent(".claude/settings.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: config.path))
    }

    func testClaudeInstallReplacesLegacyPocketNotchEventsAndPreservesOtherHooks() throws {
        let configDir = tempHome.appendingPathComponent(".claude", isDirectory: true)
        let config = configDir.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let legacyCommand = "\"\(scriptURL.path)\" emit claude completed"
        let existing: [String: Any] = [
            "hooks": [
                "completed": [["type": "command", "command": legacyCommand]],
                "SessionStart": [[
                    "hooks": [[
                        "type": "command",
                        "command": "'/other/hook.sh' Idle",
                    ]],
                ]],
            ],
        ]
        try JSONSerialization.data(withJSONObject: existing).write(to: config)

        XCTAssertFalse(installer.isInstalled(.claude))
        XCTAssertTrue(installer.hasManagedHook(.claude))

        let result = installer.install(.claude)
        XCTAssertTrue(result.success, "install failed: \(result.message)")
        XCTAssertTrue(installer.isInstalled(.claude))

        let data = try Data(contentsOf: config)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        XCTAssertNil(hooks["completed"])
        XCTAssertNotNil(hooks["SessionStart"])
        XCTAssertNotNil(hooks["SessionEnd"])
        XCTAssertNotNil(hooks["UserPromptSubmit"])
        XCTAssertNotNil(hooks["PreToolUse"])
        XCTAssertNotNil(hooks["PostToolUse"])
        XCTAssertNotNil(hooks["PreCompact"])
        XCTAssertNotNil(hooks["Stop"])

        let sessionGroups = try XCTUnwrap(hooks["SessionStart"] as? [[String: Any]])
        XCTAssertEqual(sessionGroups.count, 2)
        XCTAssertTrue(sessionGroups.contains { group in
            let handlers = group["hooks"] as? [[String: Any]] ?? []
            return handlers.contains { ($0["command"] as? String) == "'/other/hook.sh' Idle" }
        })
    }

    func testInstalledScriptDebugMarkerMatchesBuildConfiguration() throws {
        let target = tempHome.appendingPathComponent("bin/agent-events.sh")
        try AgentAppScript.installCurrentVersion(at: target)

        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(AgentAppScript.installedVersion(at: target), AgentAppScript.currentVersion)
#if DEBUG
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathExtension("debug").path))
#else
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathExtension("debug").path))
#endif
    }

    func testCodexEmitsValidJSONForScriptPathWithSpaces() throws {
        let scriptWithSpaces = tempHome.appendingPathComponent("Application Support/bin/agent-events.sh")
        try FileManager.default.createDirectory(at: scriptWithSpaces.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#! /bin/sh\n".utf8).write(to: scriptWithSpaces)
        installer = AgentHookInstaller(port: 58421, scriptURL: scriptWithSpaces, homeDirectory: tempHome)

        let config = tempHome.appendingPathComponent(".codex/hooks.json")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = #"{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"/existing/hook.sh"}]}]},"other":1}"#
        try Data(original.utf8).write(to: config)

        let result = installer.install(.codex)
        XCTAssertTrue(result.success, "install failed: \(result.message)")

        let data = try Data(contentsOf: config)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["__pocketnotch_agent_hooks__"], "Codex hooks.json rejects unknown top-level fields")
        // 用户已有 hooks 与新增事件组都是 SessionStart，注入后应保留用户那组（Merge，而非整体替换）
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        let sessionStart = try XCTUnwrap(hooks["SessionStart"] as? [[String: Any]])
        XCTAssertEqual(sessionStart.count, 2, "existing user hooks must be preserved alongside our group")
        let userGroup = sessionStart[0]
        let userHooks = try XCTUnwrap(userGroup["hooks"] as? [[String: Any]])
        XCTAssertEqual((userHooks.first!["command"] as? String), "/existing/hook.sh")
        // 新增的事件组已注入
        let entry = try XCTUnwrap(sessionStart[1])
        let hookList = try XCTUnwrap(entry["hooks"] as? [[String: Any]])
        let command = try XCTUnwrap(hookList.first!["command"] as? String)
        XCTAssertTrue(command.contains("Application Support"), "path with space must be quoted: \(command)")
        // 原有无关顶层字段保留
        XCTAssertEqual((object["other"] as? Int), 1)

        let permissionGroups = try XCTUnwrap(hooks["PermissionRequest"] as? [[String: Any]])
        let permissionHandlers = try XCTUnwrap(permissionGroups.first?["hooks"] as? [[String: Any]])
        let permissionCommand = try XCTUnwrap(permissionHandlers.first?["command"] as? String)
        XCTAssertTrue(permissionCommand.contains("emit codex waiting_approval"))

        let stopGroups = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        let stopHandlers = try XCTUnwrap(stopGroups.first?["hooks"] as? [[String: Any]])
        let stopCommand = try XCTUnwrap(stopHandlers.first?["command"] as? String)
        XCTAssertTrue(stopCommand.contains("emit codex stop_requested"))
    }

    func testCodexDetectsInstalledCommandWithoutMarker() throws {
        let config = tempHome.appendingPathComponent(".codex/hooks.json")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        let command = "\"\(scriptURL.path)\" emit codex agent_start"
        let group: [[String: Any]] = [[
            "hooks": [["type": "command", "command": command]],
        ]]
        let object: [String: Any] = [
            "hooks": [
                "SessionStart": group,
                "SessionEnd": group,
                "UserPromptSubmit": group,
                "PreToolUse": group,
                "PermissionRequest": group,
                "PostToolUse": group,
                "Stop": group,
            ],
        ]
        try JSONSerialization.data(withJSONObject: object).write(to: config)

        XCTAssertTrue(installer.isInstalled(.codex))
        let status = try XCTUnwrap(installer.detectStatuses().first { $0.agent == .codex })
        XCTAssertTrue(status.needsAuthorization)
    }

    func testCodexReportsAuthorizedWhenAllHookTrustEntriesExist() throws {
        XCTAssertTrue(installer.install(.codex).success)
        let config = tempHome.appendingPathComponent(".codex/config.toml")
        let hooksPath = tempHome.appendingPathComponent(".codex/hooks.json").path
        let sections = [
            "session_start",
            "session_end",
            "user_prompt_submit",
            "pre_tool_use",
            "permission_request",
            "post_tool_use",
            "stop",
        ]
            .map { event in
                "[hooks.state.\"\(hooksPath):\(event):0:0\"]\ntrusted_hash = \"sha256:test\""
            }
            .joined(separator: "\n\n")
        try Data(sections.utf8).write(to: config)

        let status = try XCTUnwrap(installer.detectStatuses().first { $0.agent == .codex })
        XCTAssertTrue(status.isInstalled)
        XCTAssertFalse(status.needsAuthorization)
    }

    func testCodexReinstallReplacesExistingPocketNotchGroups() throws {
        XCTAssertTrue(installer.install(.codex).success)
        XCTAssertTrue(installer.install(.codex).success)

        let config = tempHome.appendingPathComponent(".codex/hooks.json")
        let data = try Data(contentsOf: config)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        for event in [
            "SessionStart",
            "SessionEnd",
            "UserPromptSubmit",
            "PreToolUse",
            "PermissionRequest",
            "PostToolUse",
            "Stop",
        ] {
            let groups = try XCTUnwrap(hooks[event] as? [[String: Any]])
            XCTAssertEqual(groups.count, 1, "\(event) should contain one PocketNotch group after reinstall")
        }
    }
}
