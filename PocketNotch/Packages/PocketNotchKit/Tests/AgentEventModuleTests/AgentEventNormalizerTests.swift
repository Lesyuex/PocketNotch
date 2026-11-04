import XCTest
@testable import AgentEventModule

final class AgentEventNormalizerTests: XCTestCase {
    func testToolStartDefaultPayload() throws {
        let event = try AgentEventNormalizer.normalize(agentID: "claude", payload: [
            "agent": "claude",
            "sessionId": "abc123",
            "event": "tool_start",
            "tool": "Edit",
            "file": "UserView.swift",
            "source_app": "vscode",
            "source_bundle_id": "com.microsoft.VSCode",
            "timestamp": NSNumber(value: 1720000000),
        ])

        XCTAssertEqual(event.type, .toolStart)
        XCTAssertEqual(event.action, "Edit")
        XCTAssertEqual(event.file, "UserView.swift")
        XCTAssertEqual(event.sessionId, "abc123")
        XCTAssertEqual(event.agent, "claude")
        XCTAssertEqual(event.sourceApplication, "vscode")
        XCTAssertEqual(event.sourceBundleIdentifier, "com.microsoft.VSCode")
        XCTAssertEqual(event.timestamp, Date(timeIntervalSince1970: 1720000000))
        XCTAssertFalse(event.id.isEmpty)
    }

    func testCamelCaseEventNameMaps() {
        let event = try! AgentEventNormalizer.normalize(agentID: "codex", payload: [
            "agent": "codex",
            "sessionId": "s1",
            "event": "commandStart",
            "command": "swift build",
        ])
        XCTAssertEqual(event.type, .commandStart)
        XCTAssertEqual(event.command, "swift build")
    }

    func testEventTypeParsingAcceptsSnakeAndKebab() {
        let cases: [(String, EventType)] = [
            ("session_start", .sessionStart),
            ("SESSION_START", .sessionStart),
            ("session_end", .sessionEnd),
            ("thinking", .thinking),
            ("tool_end", .toolEnd),
            ("waiting-approval", .waitingApproval),
            ("completed", .completed),
            ("failed", .failed),
            ("stop_requested", .stopRequested),
        ]
        for (raw, expected) in cases {
            let event = try! AgentEventNormalizer.normalize(agentID: "cli", payload: ["sessionId": "x", "event": raw])
            XCTAssertEqual(event.type, expected, "raw=\(raw)")
        }
    }

    func testUnknownEventTypeThrows() {
        XCTAssertThrowsError(
            try AgentEventNormalizer.normalize(agentID: "a", payload: ["event": "BOGUS"])
        )
    }

    func testMissingSessionIdGetsGenerated() {
        let event = try! AgentEventNormalizer.normalize(agentID: "a", payload: ["event": "thinking"])
        XCTAssertFalse(event.sessionId.isEmpty)
        XCTAssertEqual(event.agent, "a")
    }

    func testIsoTimestampParsed() {
        let iso = "2026-07-04T01:46:40Z"
        let event = try! AgentEventNormalizer.normalize(agentID: "a", payload: [
            "sessionId": "s", "event": "thinking",
            "timestamp": iso,
        ])
        XCTAssertEqual(event.timestamp, ISO8601DateFormatter().date(from: iso))
    }
}
