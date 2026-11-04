import XCTest
@testable import AgentEventModule

final class CodexHookAuthorizerTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/tmp/pocketnotch-codex-authorizer-home")
    private let script = URL(fileURLWithPath: "/tmp/PocketNotch Support/bin/agent-events.sh")

    func testAuthorizationUsesCodexHashesForOnlyPocketNotchHooks() async throws {
        let rpc = FakeCodexAppServerRPC(hooks: makeHooks() + [[
            "key": "/tmp/other:stop:0:0",
            "eventName": "stop",
            "handlerType": "command",
            "source": "user",
            "sourcePath": home.appendingPathComponent(".codex/hooks.json").path,
            "command": "/tmp/unrelated-hook.sh",
            "isManaged": false,
            "currentHash": "sha256:unrelated",
        ]])
        let authorizer = CodexHookAuthorizer(scriptURL: script, homeDirectory: home, rpc: rpc)

        try await authorizer.authorize()

        XCTAssertEqual(rpc.notifications.map(\.method), ["initialized"])
        let batch = try XCTUnwrap(rpc.calls.first { $0.method == "config/batchWrite" })
        let edits = try XCTUnwrap(batch.params["edits"] as? [[String: Any]])
        XCTAssertEqual(edits.count, 7)
        XCTAssertEqual(Set(edits.compactMap { $0["value"] as? String }), Set((1...7).map { "sha256:pocketnotch-\($0)" }))
        XCTAssertFalse(edits.contains { ($0["value"] as? String) == "sha256:unrelated" })
        XCTAssertTrue(edits.allSatisfy { ($0["keyPath"] as? String)?.hasPrefix("hooks.state.\"") == true })
        XCTAssertEqual(batch.params["reloadUserConfig"] as? Bool, true)
        XCTAssertEqual(
            batch.params["filePath"] as? String,
            home.appendingPathComponent(".codex/config.toml").path
        )
    }

    func testAuthorizationRejectsIncompletePocketNotchHookSet() async {
        let rpc = FakeCodexAppServerRPC(hooks: Array(makeHooks().dropLast()))
        let authorizer = CodexHookAuthorizer(scriptURL: script, homeDirectory: home, rpc: rpc)

        do {
            try await authorizer.authorize()
            XCTFail("authorization should reject an incomplete hook set")
        } catch let error as CodexHookAuthorizationError {
            guard case .missingHooks(let events) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(events, ["stop"])
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertFalse(rpc.calls.contains { $0.method == "config/batchWrite" })
    }

    func testProcessBackedAuthorizerCanRunTwice() async throws {
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PocketNotchCodexProcessTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)

        let home = testRoot.appendingPathComponent("home", isDirectory: true)
        let script = testRoot.appendingPathComponent("agent-events.sh")
        let executable = testRoot.appendingPathComponent("fake-codex")
        let hooksResult: [String: Any] = ["data": [[
            "cwd": home.path,
            "hooks": makeHooks(home: home, script: script),
            "warnings": [],
            "errors": [],
        ]]]
        let hooksJSON = try Self.jsonString(["id": 2, "result": hooksResult])
        let fakeServer = """
        #!/bin/sh
        while IFS= read -r line; do
          case "$line" in
            *initialize*) printf '%s\\n' '{"id":1,"result":{"codexHome":"/tmp","platformFamily":"unix","platformOs":"macos","userAgent":"test"}}' ;;
            *hooks*list*) printf '%s\\n' '\(hooksJSON)' ;;
            *config*batchWrite*) printf '%s\\n' '{"id":3,"result":{"status":"ok"}}' ;;
          esac
        done
        """
        try Data(fakeServer.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let authorizer = CodexHookAuthorizer(
            scriptURL: script,
            homeDirectory: home,
            workingDirectory: testRoot,
            executableURL: executable
        )
        try await authorizer.authorize()
        try await authorizer.authorize()
    }

    private func makeHooks() -> [[String: Any]] {
        makeHooks(home: home, script: script)
    }

    private func makeHooks(home: URL, script: URL) -> [[String: Any]] {
        let definitions = [
            ("sessionStart", "session_start"),
            ("sessionEnd", "session_end"),
            ("userPromptSubmit", "agent_start"),
            ("preToolUse", "tool_start"),
            ("permissionRequest", "waiting_approval"),
            ("postToolUse", "tool_end"),
            ("stop", "stop_requested"),
        ]
        return definitions.enumerated().map { index, definition in
            [
                "key": "\(home.path)/.codex/hooks.json:\(definition.0):\(index):0",
                "eventName": definition.0,
                "handlerType": "command",
                "source": "user",
                "sourcePath": home.appendingPathComponent(".codex/hooks.json").path,
                "command": "\"\(script.path)\" emit codex \(definition.1)",
                "isManaged": false,
                "currentHash": "sha256:pocketnotch-\(index + 1)",
            ]
        }
    }

    private static func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try XCTUnwrap(String(data: data, encoding: .utf8))
            .replacingOccurrences(of: "'", with: "'\\''")
    }
}

private final class FakeCodexAppServerRPC: CodexAppServerRPC {
    struct Invocation {
        let method: String
        let params: [String: Any]
    }

    private let hooks: [[String: Any]]
    private(set) var calls: [Invocation] = []
    private(set) var notifications: [Invocation] = []

    init(hooks: [[String: Any]]) {
        self.hooks = hooks
    }

    func start() throws {}

    func notify(method: String, params: [String: Any]) throws {
        notifications.append(Invocation(method: method, params: params))
    }

    func call(method: String, params: [String: Any]) throws -> [String: Any] {
        calls.append(Invocation(method: method, params: params))
        switch method {
        case "initialize":
            return ["codexHome": "/tmp/codex", "platformFamily": "unix", "platformOs": "macos", "userAgent": "test"]
        case "hooks/list":
            return ["data": [["cwd": "/tmp", "hooks": hooks, "warnings": [], "errors": []]]]
        case "config/batchWrite":
            return ["status": "ok"]
        default:
            return [:]
        }
    }

    func stop() {}
}
