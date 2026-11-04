import XCTest
@testable import AgentEventModule

final class AgentAdapterTests: XCTestCase {
    func testClaudeAdapterMapsHookEnvelope() throws {
        let adapter = ClaudeAdapter()
        let event = try adapter.normalize([
            "agent": "claude",
            "hook_event_name": "post_tool_use",
            "session_id": "claude-s1",
            "tool_name": "Write",
            "file_path": "README.md",
        ])
        XCTAssertEqual(event.type, .toolEnd)
        XCTAssertEqual(event.action, "Write")
        XCTAssertEqual(event.file, "README.md")
        XCTAssertEqual(event.sessionId, "claude-s1")
    }

    func testClaudeAdapterMapsThinkingAndApproval() throws {
        let thinking = try ClaudeAdapter().normalize(["agent": "claude", "hook_event_name": "pre_compact", "session_id": "s"])
        XCTAssertEqual(thinking.type, .thinking)

        let approval = try ClaudeAdapter().normalize(["agent": "claude", "hook_event_name": "user_approval_prompt", "session_id": "s"])
        XCTAssertEqual(approval.type, .waitingApproval)

        let sessionEnd = try ClaudeAdapter().normalize([
            "agent": "claude",
            "hook_event_name": "session_end",
            "session_id": "s",
        ])
        XCTAssertEqual(sessionEnd.type, .sessionEnd)
    }

    func testCodexAdapterMapsPhaseAndCommand() throws {
        let adapter = CodexAdapter()
        let event = try adapter.normalize([
            "agent": "codex",
            "phase": "run_command",
            "session_id": "s1",
            "payload": ["command": "ls -la"],
        ])
        XCTAssertEqual(event.type, .commandStart)
        XCTAssertEqual(event.command, "ls -la")
    }

    func testCodexAdapterMapsStopPhaseToCompleted() throws {
        let adapter = CodexAdapter()
        let event = try adapter.normalize([
            "agent": "codex",
            "phase": "stop",
            "session_id": "s1",
        ])
        XCTAssertEqual(event.type, .completed)
    }

    func testGeminiAdapterMapsStep() throws {
        let adapter = GeminiAdapter()
        let event = try adapter.normalize([
            "agent": "gemini",
            "step": "reasoning",
            "session_id": "s1",
            "message": "planning next",
        ])
        XCTAssertEqual(event.type, .thinking)
        XCTAssertEqual(event.message, "planning next")
    }

    func testFactoryRoutesToSpecializedAdapter() {
        XCTAssertTrue(AgentAdapterFactory.adapter(for: "claude-code") is ClaudeAdapter)
        XCTAssertTrue(AgentAdapterFactory.adapter(for: "codex") is CodexAdapter)
        XCTAssertTrue(AgentAdapterFactory.adapter(for: "gemini") is GeminiAdapter)
        XCTAssertTrue(AgentAdapterFactory.adapter(for: "opencode") is GenericAdapter)
        XCTAssertTrue(AgentAdapterFactory.adapter(for: "qoder") is GenericAdapter)
        XCTAssertTrue(AgentAdapterFactory.adapter(for: "hermes") is GenericAdapter)
    }

    func testCanonicalIDNormalizesAliases() {
        XCTAssertEqual(AgentAdapterFactory.canonicalID("claude-code"), "claude")
        XCTAssertEqual(AgentAdapterFactory.canonicalID("codex_cli"), "codex")
        XCTAssertEqual(AgentAdapterFactory.canonicalID(nil), "unknown")
    }
}
