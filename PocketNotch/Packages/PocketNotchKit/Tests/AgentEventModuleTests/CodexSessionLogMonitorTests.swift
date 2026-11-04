import Foundation
import XCTest
@testable import AgentEventModule

final class CodexSessionLogMonitorTests: XCTestCase {
    private final class EventRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [[String: Any]] = []

        var events: [[String: Any]] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func append(_ event: [String: Any]) {
            lock.lock()
            storage.append(event)
            lock.unlock()
        }

        func removeAll() {
            lock.lock()
            storage.removeAll()
            lock.unlock()
        }
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexSessionLogMonitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testUntrackedHistoricalTurnIsIgnored() throws {
        let file = try makeRollout(lines: [meta(), started("turn-1"), completed("turn-1")])
        let recorder = EventRecorder()
        let monitor = CodexSessionLogMonitor(sessionsDirectory: directory) { recorder.append($0) }

        monitor.scanNow()

        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testExistingRunningTurnRestoresStableSessionID() throws {
        _ = try makeRollout(sessionID: "session-before-pocketnotch", lines: [meta(sessionID: "session-before-pocketnotch"), started("turn-1")])
        let recorder = EventRecorder()
        let monitor = CodexSessionLogMonitor(sessionsDirectory: directory) { recorder.append($0) }
        monitor.track(sessionID: "session-before-pocketnotch")

        monitor.scanNow()

        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertEqual(recorder.events[0]["sessionId"] as? String, "session-before-pocketnotch")
        XCTAssertEqual(recorder.events[0]["event"] as? String, "agent_start")
    }

    func testAppendedCompletionUsesSameSessionIDAndEmitsOnce() throws {
        let file = try makeRollout(lines: [meta(), started("turn-1")])
        let recorder = EventRecorder()
        let monitor = CodexSessionLogMonitor(sessionsDirectory: directory) { recorder.append($0) }
        monitor.track(sessionID: "session-1")
        monitor.scanNow()
        recorder.removeAll()

        try append(completed("turn-1"), to: file)
        monitor.scanNow()
        monitor.scanNow()

        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertEqual(recorder.events[0]["sessionId"] as? String, "session-1")
        XCTAssertEqual(recorder.events[0]["event"] as? String, "completed")
        XCTAssertEqual(recorder.events[0]["source"] as? String, "rollout")
    }

    func testCompletionWithErrorEmitsFailed() throws {
        let file = try makeRollout(lines: [meta(), started("turn-1")])
        let recorder = EventRecorder()
        let monitor = CodexSessionLogMonitor(sessionsDirectory: directory) { recorder.append($0) }
        monitor.track(sessionID: "session-1")
        monitor.scanNow()
        recorder.removeAll()

        try append(completed("turn-1", error: ["message": "cancelled"]), to: file)
        monitor.scanNow()

        XCTAssertEqual(recorder.events.first?["event"] as? String, "failed")
    }

    func testPartialLineWaitsUntilNewlineArrives() throws {
        let file = try makeRollout(lines: [meta(), started("turn-1")])
        let recorder = EventRecorder()
        let monitor = CodexSessionLogMonitor(sessionsDirectory: directory) { recorder.append($0) }
        monitor.track(sessionID: "session-1")
        monitor.scanNow()
        recorder.removeAll()

        let data = try JSONSerialization.data(withJSONObject: completed("turn-1"))
        try appendData(data, to: file)
        monitor.scanNow()
        XCTAssertTrue(recorder.events.isEmpty)

        try appendData(Data("\n".utf8), to: file)
        monitor.scanNow()
        XCTAssertEqual(recorder.events.first?["event"] as? String, "completed")
    }

    func testNewRolloutAfterInitialScanEmitsStartAndCompletion() throws {
        let recorder = EventRecorder()
        let monitor = CodexSessionLogMonitor(sessionsDirectory: directory) { recorder.append($0) }
        monitor.track(sessionID: "session-1")
        monitor.scanNow()

        _ = try makeRollout(lines: [meta(), started("turn-new"), completed("turn-new")])
        monitor.scanNow()

        XCTAssertEqual(recorder.events.compactMap { $0["event"] as? String }, ["completed"])
    }

    func testHookEventAutomaticallyTracksItsSession() throws {
        _ = try makeRollout(lines: [meta(), started("turn-hook")])
        let recorder = EventRecorder()
        let monitor = CodexSessionLogMonitor(sessionsDirectory: directory) { recorder.append($0) }
        monitor.observe(AgentEvent(
            id: "hook-start",
            agent: "codex",
            sessionId: "session-1",
            type: .agentStart,
            timestamp: Date()
        ))

        monitor.scanNow()

        XCTAssertEqual(recorder.events.first?["sessionId"] as? String, "session-1")
        XCTAssertEqual(recorder.events.first?["event"] as? String, "agent_start")
    }

    func testTrackedHistoricalCompletedTurnReconcilesTerminalState() throws {
        _ = try makeRollout(lines: [meta(), started("turn-1"), completed("turn-1")])
        let recorder = EventRecorder()
        let monitor = CodexSessionLogMonitor(sessionsDirectory: directory) { recorder.append($0) }
        monitor.track(sessionID: "session-1")

        monitor.scanNow()

        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertEqual(recorder.events[0]["event"] as? String, "completed")
    }

    /// 陈旧日志（很久没有新写入）里的「未收尾 turn」不是运行证据：
    /// 重启后不得据此把已关闭的会话复活成 running。
    func testStaleRunningTurnIsNotResurrected() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        _ = try makeRollout(lines: [
            meta(),
            started("turn-old", at: now.addingTimeInterval(-3600)),
        ])
        let recorder = EventRecorder()
        let monitor = CodexSessionLogMonitor(sessionsDirectory: directory, now: { now }) { recorder.append($0) }
        monitor.track(sessionID: "session-1")

        monitor.scanNow()

        XCTAssertTrue(recorder.events.isEmpty)
    }

    /// 最近仍在写入的未收尾 turn 才视为运行证据。
    func testFreshRunningTurnEmitsStart() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        _ = try makeRollout(lines: [
            meta(),
            started("turn-fresh", at: now.addingTimeInterval(-10)),
        ])
        let recorder = EventRecorder()
        let monitor = CodexSessionLogMonitor(sessionsDirectory: directory, now: { now }) { recorder.append($0) }
        monitor.track(sessionID: "session-1")

        monitor.scanNow()

        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertEqual(recorder.events[0]["event"] as? String, "agent_start")
    }

    /// turn_aborted 的 turn 不是活跃任务，不得补发 agent_start。
    func testAbortedTurnIsNotTreatedAsActive() throws {
        _ = try makeRollout(lines: [meta(), started("turn-1"), aborted("turn-1")])
        let recorder = EventRecorder()
        let monitor = CodexSessionLogMonitor(sessionsDirectory: directory) { recorder.append($0) }
        monitor.track(sessionID: "session-1")

        monitor.scanNow()

        XCTAssertTrue(recorder.events.isEmpty)
    }

    private func makeRollout(sessionID: String = "session-1", lines: [[String: Any]]) throws -> URL {
        let file = directory.appendingPathComponent("rollout-test-\(sessionID).jsonl")
        let data = try lines.reduce(into: Data()) { result, line in
            result.append(try JSONSerialization.data(withJSONObject: line))
            result.append(Data("\n".utf8))
        }
        try data.write(to: file)
        return file
    }

    private func append(_ line: [String: Any], to file: URL) throws {
        var data = try JSONSerialization.data(withJSONObject: line)
        data.append(Data("\n".utf8))
        try appendData(data, to: file)
    }

    private func appendData(_ data: Data, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func meta(sessionID: String = "session-1") -> [String: Any] {
        ["type": "session_meta", "payload": ["id": sessionID]]
    }

    private func started(_ turnID: String, at date: Date = Date()) -> [String: Any] {
        [
            "timestamp": Self.iso(date),
            "type": "event_msg",
            "payload": ["type": "task_started", "turn_id": turnID],
        ]
    }

    private func completed(_ turnID: String, error: Any? = nil) -> [String: Any] {
        var payload: [String: Any] = ["type": "task_complete", "turn_id": turnID]
        if let error { payload["error"] = error }
        return [
            "timestamp": Self.iso(Date()),
            "type": "event_msg",
            "payload": payload,
        ]
    }

    private func aborted(_ turnID: String) -> [String: Any] {
        [
            "timestamp": Self.iso(Date()),
            "type": "event_msg",
            "payload": ["type": "turn_aborted", "turn_id": turnID],
        ]
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
