import XCTest
@testable import AgentEventModule

final class AgentSessionHistoryStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var historyURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        historyURL = temporaryDirectory.appendingPathComponent("agent-events.jsonl")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testLoadGroupsCanonicalAgentsAndSortsSessionsByLatestEvent() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        try write([
            event(id: "1", agent: "Claude Code", sessionID: "shared", type: .sessionStart, date: base),
            event(id: "2", agent: "codex_cli", sessionID: "shared", type: .completed, date: base.addingTimeInterval(30)),
            event(id: "3", agent: "claude", sessionID: "shared", type: .toolStart, date: base.addingTimeInterval(20)),
        ])

        let sessions = try AgentSessionHistoryReader.load(from: historyURL)

        XCTAssertEqual(sessions.map(\.agentID), ["codex", "claude"])
        XCTAssertEqual(sessions.map(\.sessionID), ["shared", "shared"])
        XCTAssertEqual(sessions.last?.events.map(\.id), ["1", "3"])
    }

    func testLoadIgnoresMalformedLinesAndAppliesLimits() throws {
        let events = (0..<6).map { index in
            event(
                id: "\(index)",
                agent: index.isMultiple(of: 2) ? "codex" : "gemini",
                sessionID: "s\(index)",
                type: .thinking,
                date: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        try write(events, malformedPrefix: true)

        let sessions = try AgentSessionHistoryReader.load(
            from: historyURL,
            maximumEvents: 4,
            maximumSessions: 2
        )

        XCTAssertEqual(sessions.map(\.sessionID), ["s5", "s4"])
    }

    func testSessionUsesLatestAgentStartMessageAsPrompt() {
        let session = AgentHistorySession(
            id: "codex:s1",
            agentID: "codex",
            sessionID: "s1",
            events: [
                event(id: "1", agent: "codex", sessionID: "s1", type: .sessionStart, date: Date()),
                event(
                    id: "2",
                    agent: "codex",
                    sessionID: "s1",
                    type: .agentStart,
                    date: Date().addingTimeInterval(1),
                    message: "  第一行\n第二行  "
                ),
                event(
                    id: "3",
                    agent: "codex",
                    sessionID: "s1",
                    type: .agentStart,
                    date: Date().addingTimeInterval(2),
                    message: "后续提示词"
                ),
            ]
        )

        XCTAssertEqual(session.latestPrompt, "后续提示词")
    }

    func testLoadReturnsEmptyWhenFileDoesNotExist() throws {
        let sessions = try AgentSessionHistoryReader.load(from: historyURL)
        XCTAssertTrue(sessions.isEmpty)
    }

    func testSessionUsesLatestRecordedSourceApplication() {
        let session = AgentHistorySession(
            id: "codex:s1",
            agentID: "codex",
            sessionID: "s1",
            events: [
                event(
                    id: "1",
                    agent: "codex",
                    sessionID: "s1",
                    type: .sessionStart,
                    date: Date(),
                    sourceApplication: "Apple_Terminal",
                    sourceBundleIdentifier: "com.apple.Terminal"
                ),
                event(
                    id: "2",
                    agent: "codex",
                    sessionID: "s1",
                    type: .completed,
                    date: Date().addingTimeInterval(1)
                ),
            ]
        )

        XCTAssertEqual(session.sourceApplication, "Apple_Terminal")
        XCTAssertEqual(session.sourceBundleIdentifier, "com.apple.Terminal")
    }

    func testSessionStatusUsesExplicitAndInferredStates() {
        let now = Date(timeIntervalSince1970: 10_000)
        let active = historySession(type: .toolStart, date: now.addingTimeInterval(-60))
        let stale = historySession(type: .toolStart, date: now.addingTimeInterval(-901))
        let completed = historySession(type: .completed, date: now.addingTimeInterval(-10_000))
        let closed = historySession(type: .sessionEnd, date: now.addingTimeInterval(-10_000))

        XCTAssertEqual(active.status(at: now), .active)
        XCTAssertEqual(stale.status(at: now), .unknown)
        XCTAssertEqual(completed.status(at: now), .completed)
        XCTAssertEqual(closed.status(at: now), .closed)
    }

    private func historySession(type: EventType, date: Date) -> AgentHistorySession {
        AgentHistorySession(
            id: "codex:s",
            agentID: "codex",
            sessionID: "s",
            events: [event(id: "event", agent: "codex", sessionID: "s", type: type, date: date)]
        )
    }

    private func event(
        id: String,
        agent: String,
        sessionID: String,
        type: EventType,
        date: Date,
        message: String? = nil,
        sourceApplication: String? = nil,
        sourceBundleIdentifier: String? = nil
    ) -> AgentEvent {
        AgentEvent(
            id: id,
            agent: agent,
            sessionId: sessionID,
            type: type,
            message: message ?? "message \(id)",
            sourceApplication: sourceApplication,
            sourceBundleIdentifier: sourceBundleIdentifier,
            timestamp: date
        )
    }

    private func write(_ events: [AgentEvent], malformedPrefix: Bool = false) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = malformedPrefix ? Data("not-json\n".utf8) : Data()
        for event in events {
            data.append(try encoder.encode(event))
            data.append(0x0A)
        }
        try data.write(to: historyURL)
    }
}
