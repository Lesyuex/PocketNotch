import XCTest
@testable import AgentEventModule

final class RecordingSink: EventSink, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [AgentEvent] = []
    var events: [AgentEvent] {
        lock.lock(); defer { lock.unlock() }
        return _events
    }

    func handle(_ event: AgentEvent) {
        lock.lock(); defer { lock.unlock() }
        _events.append(event)
    }
}

final class AgentEventBridgeTests: XCTestCase {
    func testIngestBuildsSessionsAndDispatches() throws {
        let sink = RecordingSink()
        let bridge = AgentEventBridge(port: 0, sinks: [sink])

        try bridge.ingest(["agent": "claude", "sessionId": "s1", "event": "session_start"])
        try bridge.ingest(["agent": "claude", "sessionId": "s1", "event": "tool_start", "tool": "Edit", "file": "A.swift"])
        try bridge.ingest(["agent": "codex", "sessionId": "s2", "event": "command_start", "command": "swift build"])

        let sessions = bridge.snapshotSessions()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(bridge.clientCount, 3)
        XCTAssertEqual(bridge.events(for: "s1").count, 2)
        XCTAssertEqual(sink.events.count, 3)

        let codex = sessions.first { $0.id == "s2" }
        XCTAssertEqual(codex?.agent, "codex")
        XCTAssertEqual(codex?.events.first?.type, .commandStart)
    }

    func testIngestThrowsForUnknownTypeWithNoSideEffect() throws {
        let bridge = AgentEventBridge(port: 0, sinks: [])
        XCTAssertThrowsError(
            try bridge.ingest(["agent": "a", "sessionId": "s", "event": "boom"])
        )
        XCTAssertEqual(bridge.clientCount, 0)
    }

    func testDisabledAgentIsNormalizedButNotRecordedOrDispatched() throws {
        let sink = RecordingSink()
        let bridge = AgentEventBridge(
            port: 0,
            sinks: [sink],
            shouldAcceptEvent: { AgentAdapterFactory.canonicalID($0.agent) == "claude" }
        )

        try bridge.ingest(["agent": "codex", "sessionId": "s1", "event": "command_start"])

        XCTAssertEqual(bridge.clientCount, 0)
        XCTAssertTrue(bridge.snapshotSessions().isEmpty)
        XCTAssertTrue(sink.events.isEmpty)
    }
}

final class AgentEventHTTPTests: XCTestCase {
    func testHTTPPostRoundTrip() async throws {
        let sink = RecordingSink()
        let port = UInt16.random(in: 52000...57000)
        let bridge = AgentEventBridge(port: port, sinks: [sink])
        try await bridge.start()
        XCTAssertTrue(bridge.isRunning)

        let body: [String: Any] = [
            "agent": "claude",
            "sessionId": "http-s1",
            "event": "tool_end",
            "tool": "Write",
            "file": "Notes.md",
        ]
        let url = URL(string: "http://127.0.0.1:\(port)/api/agent/event")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["ok"] as? Bool, true)
        XCTAssertEqual(json?["event"] as? String, "toolEnd")

        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(sink.events.count, 1)
        XCTAssertEqual(sink.events.first?.type, .toolEnd)
        XCTAssertEqual(bridge.clientCount, 1)

        bridge.stop()
    }

    func testUnknownRouteReturns404() async throws {
        let port = UInt16.random(in: 57100...61999)
        let bridge = AgentEventBridge(port: port, sinks: [])
        try await bridge.start()

        let url = URL(string: "http://127.0.0.1:\(port)/api/other")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["event": "x"])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
        bridge.stop()
    }
}
