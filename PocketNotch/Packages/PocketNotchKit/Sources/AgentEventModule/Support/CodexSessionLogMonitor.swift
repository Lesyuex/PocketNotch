import Foundation
import os

/// Incrementally reconciles Codex turn state from its durable rollout logs.
/// Hooks remain the fast path; this monitor supplies start-up truth and missed terminal events.
final class CodexSessionLogMonitor: @unchecked Sendable {
    typealias EventHandler = @Sendable ([String: Any]) -> Void

    private struct FileState {
        var offset: UInt64 = 0
        var partialLine = Data()
        var sessionID: String?
        var fileNumber: NSNumber?
    }

    private struct TurnRecord {
        let turnID: String
        let timestamp: String?
    }

    private let sessionsDirectory: URL
    private let pollInterval: TimeInterval
    private let discoveryInterval: TimeInterval
    private let freshnessWindow: TimeInterval
    private let now: () -> Date
    private let eventHandler: EventHandler
    private let queue = DispatchQueue(label: "pocketnotch.agent.codex-session-log", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var states: [URL: FileState] = [:]
    private var trackedSessionIDs: Set<String> = []
    private var filesBySessionID: [String: URL] = [:]
    private var needsDiscovery = false
    private var lastDiscoveryAt: Date?
    private var isStarted = false
    private let logger = Logger(subsystem: "PocketNotch", category: "CodexSessionLogMonitor")

    init(
        sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        pollInterval: TimeInterval = 2,
        discoveryInterval: TimeInterval = 15,
        /// `reconcile` 只把「日志仍近期在写入」的未收尾 turn 视为运行证据，
        /// 更早的日志说明 codex 进程早已退出（陈旧会话不得在启动时复活成 running）。
        freshnessWindow: TimeInterval = 2 * 60,
        now: @escaping @Sendable () -> Date = { Date() },
        eventHandler: @escaping EventHandler
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.pollInterval = pollInterval
        self.discoveryInterval = discoveryInterval
        self.freshnessWindow = freshnessWindow
        self.now = now
        self.eventHandler = eventHandler
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isStarted = true
            self.startTimerIfNeeded()
        }
    }

    func stop() {
        queue.sync {
            isStarted = false
            timer?.cancel()
            timer = nil
            states.removeAll()
            trackedSessionIDs.removeAll()
            filesBySessionID.removeAll()
            needsDiscovery = false
            lastDiscoveryAt = nil
        }
    }

    func track(sessionID: String) {
        guard !sessionID.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            if self.trackedSessionIDs.insert(sessionID).inserted {
                self.needsDiscovery = true
                self.startTimerIfNeeded()
            }
        }
    }

    func observe(_ event: AgentEvent) {
        guard AgentAdapterFactory.canonicalID(event.agent) == "codex" else { return }
        switch event.type {
        case .completed, .failed, .sessionEnd:
            queue.async { [weak self] in self?.untrack(sessionID: event.sessionId) }
        default:
            track(sessionID: event.sessionId)
        }
    }

    /// Synchronous test seam and manual reconciliation entry point.
    func scanNow() {
        queue.sync { scan(forceDiscovery: true) }
    }

    private func scan(forceDiscovery: Bool = false) {
        guard !trackedSessionIDs.isEmpty else { return }
        if needsDiscovery && shouldDiscover(force: forceDiscovery) {
            discoverTrackedFiles()
            needsDiscovery = false
            lastDiscoveryAt = Date()
        }
        for sessionID in trackedSessionIDs {
            guard let url = filesBySessionID[sessionID] else {
                needsDiscovery = true
                continue
            }
            process(url, reconcileExistingState: states[url] == nil)
        }
    }

    private func startTimerIfNeeded() {
        guard isStarted, timer == nil, !trackedSessionIDs.isEmpty else { return }
        scan()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + pollInterval,
            repeating: pollInterval,
            leeway: .milliseconds(500)
        )
        timer.setEventHandler { [weak self] in self?.scan() }
        self.timer = timer
        timer.resume()
    }

    private func shouldDiscover(force: Bool) -> Bool {
        guard !force, let lastDiscoveryAt else { return true }
        return Date().timeIntervalSince(lastDiscoveryAt) >= discoveryInterval
    }

    private func discoverTrackedFiles() {
        let unresolved = trackedSessionIDs.filter { filesBySessionID[$0] == nil }
        guard !unresolved.isEmpty else { return }
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in enumerator {
            guard let url = item as? URL,
                  url.lastPathComponent.hasPrefix("rollout-"),
                  url.pathExtension == "jsonl",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            for sessionID in unresolved where url.lastPathComponent.contains(sessionID) {
                filesBySessionID[sessionID] = url
            }
        }
    }

    private func process(_ url: URL, reconcileExistingState: Bool) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value else { return }

        let fileNumber = attributes[.systemFileNumber] as? NSNumber
        var state = states[url] ?? FileState()
        var shouldReconcile = reconcileExistingState
        if size < state.offset || (state.fileNumber != nil && state.fileNumber != fileNumber) {
            state = FileState()
            shouldReconcile = true
        }
        state.fileNumber = fileNumber
        guard size > state.offset else {
            states[url] = state
            return
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: state.offset)
            let newData = try handle.readToEnd() ?? Data()
            state.offset += UInt64(newData.count)
            state.partialLine.append(newData)

            let lines = completeLines(from: &state.partialLine)
            if shouldReconcile {
                reconcile(lines: lines, state: &state)
            } else {
                for line in lines {
                    process(line: line, state: &state, emitImmediately: true)
                }
            }
            states[url] = state
        } catch {
            states[url] = state
        }
    }

    private func completeLines(from data: inout Data) -> [Data] {
        var lines: [Data] = []
        var start = data.startIndex
        while let newline = data[start...].firstIndex(of: 0x0A) {
            if newline > start {
                lines.append(data[start..<newline])
            }
            start = data.index(after: newline)
        }
        data = start < data.endIndex ? Data(data[start...]) : Data()
        return lines
    }

    private func reconcile(lines: [Data], state: inout FileState) {
        var activeTurns: [String: TurnRecord] = [:]
        var order: [String] = []
        var latestTerminal: (turnID: String, event: String, timestamp: String?)?
        var latestRecordDate: Date?

        for line in lines {
            guard let record = decodedRecord(line) else { continue }
            if let timestamp = record["timestamp"] as? String, let date = parseTimestamp(timestamp) {
                latestRecordDate = max(latestRecordDate ?? .distantPast, date)
            }
            updateSessionID(from: record, state: &state)
            guard record["type"] as? String == "event_msg",
                  let payload = record["payload"] as? [String: Any],
                  let type = payload["type"] as? String,
                  let turnID = payload["turn_id"] as? String else { continue }

            if type == "task_started" {
                activeTurns[turnID] = TurnRecord(turnID: turnID, timestamp: record["timestamp"] as? String)
                order.removeAll { $0 == turnID }
                order.append(turnID)
            } else if type == "task_complete" {
                activeTurns.removeValue(forKey: turnID)
                order.removeAll { $0 == turnID }
                let error = payload["error"]
                latestTerminal = (
                    turnID,
                    error == nil || error is NSNull ? "completed" : "failed",
                    record["timestamp"] as? String
                )
            } else if type == "turn_aborted" || type == "turn_cancelled" {
                // 被中止/取消的 turn 不是活跃任务，不得据此补发 agent_start。
                activeTurns.removeValue(forKey: turnID)
                order.removeAll { $0 == turnID }
            }
        }

        guard let sessionID = state.sessionID else { return }
        // 陈旧日志（很久没有新写入）说明 codex 进程早已退出：
        // 既不复活成 running，也不再追踪，避免重启后反复触发。
        let isStale = latestRecordDate.map { now().timeIntervalSince($0) > freshnessWindow } ?? true
        let latestString = latestRecordDate.map { Self.iso($0) } ?? "nil"
        logger.info("reconcile session=\(sessionID, privacy: .public) stale=\(isStale) latest=\(latestString, privacy: .public) activeTurns=\(activeTurns.count)")
        if isStale {
            logger.info("SKIP stale session=\(sessionID, privacy: .public) lastWrite=\(latestString, privacy: .public) untrack")
            untrack(sessionID: sessionID)
        } else if let turnID = order.last, let turn = activeTurns[turnID] {
            logger.info("EMIT agent_start session=\(sessionID, privacy: .public) turn=\(turn.turnID, privacy: .public)")
            eventHandler(eventPayload(sessionID: sessionID, turnID: turn.turnID, event: "agent_start", timestamp: turn.timestamp))
        } else if let latestTerminal {
            logger.info("EMIT \(latestTerminal.event, privacy: .public) session=\(sessionID, privacy: .public) turn=\(latestTerminal.turnID, privacy: .public)")
            eventHandler(eventPayload(
                sessionID: sessionID,
                turnID: latestTerminal.turnID,
                event: latestTerminal.event,
                timestamp: latestTerminal.timestamp
            ))
            // 文件末尾是 task_complete/failed 且没有活跃的 turn，说明 rollout 已结束。
            // 立即 untrack 该 session，避免后续轮询重复发出 agent_start 事件。
            untrack(sessionID: sessionID)
        }
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// 解析 rollout 记录的 ISO8601 时间戳（兼容带/不带毫秒的格式）。
    private func parseTimestamp(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    private func untrack(sessionID: String) {
        trackedSessionIDs.remove(sessionID)
        if trackedSessionIDs.isEmpty {
            timer?.cancel()
            timer = nil
        }
        if let url = filesBySessionID.removeValue(forKey: sessionID) {
            states.removeValue(forKey: url)
        }
    }

    private func process(line: Data, state: inout FileState, emitImmediately: Bool) {
        guard let record = decodedRecord(line) else { return }
        updateSessionID(from: record, state: &state)
        guard emitImmediately,
              let sessionID = state.sessionID,
              record["type"] as? String == "event_msg",
              let payload = record["payload"] as? [String: Any],
              let type = payload["type"] as? String,
              let turnID = payload["turn_id"] as? String else { return }

        let event: String
        switch type {
        case "task_started":
            event = "agent_start"
        case "task_complete":
            let error = payload["error"]
            event = error == nil || error is NSNull ? "completed" : "failed"
        default:
            return
        }
        eventHandler(eventPayload(
            sessionID: sessionID,
            turnID: turnID,
            event: event,
            timestamp: record["timestamp"] as? String
        ))
    }

    private func decodedRecord(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func updateSessionID(from record: [String: Any], state: inout FileState) {
        guard record["type"] as? String == "session_meta",
              let payload = record["payload"] as? [String: Any],
              let sessionID = payload["id"] as? String,
              !sessionID.isEmpty else { return }
        state.sessionID = sessionID
    }

    private func eventPayload(
        sessionID: String,
        turnID: String,
        event: String,
        timestamp: String?
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "id": "codex-rollout:\(turnID):\(event)",
            "agent": "codex",
            "sessionId": sessionID,
            "event": event,
            "source": "rollout",
        ]
        if let timestamp { payload["timestamp"] = timestamp }
        return payload
    }
}
