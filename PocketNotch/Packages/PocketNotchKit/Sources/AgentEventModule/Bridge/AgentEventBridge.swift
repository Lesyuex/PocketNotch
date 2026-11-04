import Foundation

/// Agent Bridge：接收不同 Agent 的 Hook 事件，转为统一事件模型，
/// 记录会话并按 sink 分发。
///
/// 维护线程安全：所有可变状态统一在串行 `queue` 上访问。
public final class AgentEventBridge: @unchecked Sendable {
    public static let defaultPort: UInt16 = 58421

    private let queue = DispatchQueue(label: "pocketnotch.agent.bridge")
    private let port: UInt16
    private let sink: EventSink
    private let shouldAcceptEvent: @Sendable (AgentEvent) -> Bool
    private var server: LocalHTTPServer?
    private var sessions: [String: [AgentEvent]] = [:]
    private var eventCount = 0
    private var eventObserver: (@Sendable (AgentEvent) -> Void)?

    /// CLI Agent 上报消息。Phase 1 仅用于根路径健康检查。
    private let banner: [String: Any] = ["ok": true, "service": "PocketNotch Agent Bridge"]

    /// 默认输出：控制台 + Application Support 下的 JSON Lines 文件。
    public static var defaultPath: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("PocketNotch/agent-events.jsonl")
    }

    public init(
        port: UInt16 = AgentEventBridge.defaultPort,
        sinks: [EventSink],
        shouldAcceptEvent: @escaping @Sendable (AgentEvent) -> Bool = { _ in true }
    ) {
        self.port = port
        self.sink = EventMulticaster(sinks: sinks)
        self.shouldAcceptEvent = shouldAcceptEvent
    }

    /// 启动 HTTP 服务（端口冲突或监听失败时抛错）。重复调用安全。
    public func start() async throws {
        guard server?.isRunning != true else { return }
        let server = try LocalHTTPServer(port: port) { [weak self] path, body in
            guard let self else {
                return AgentHTTPResult(status: 500, body: ["ok": false, "error": "bridge unavailable"])
            }
            if path == "/" {
                return AgentHTTPResult(status: 200, body: self.banner)
            }
            guard path.contains("api/agent/event") || path.contains("api/event") else {
                return AgentHTTPResult(status: 404, body: ["ok": false, "error": "not found"])
            }
            return self.processEvent(body)
        }
        self.server = server
        try await server.start()
    }

    public func stop() {
        server?.stop()
        server = nil
    }

    public var isRunning: Bool { server?.isRunning ?? false }

    func setEventObserver(_ observer: @escaping @Sendable (AgentEvent) -> Void) {
        queue.sync { eventObserver = observer }
    }

    // MARK: - Event handling

    /// 接收并处理一条原始事件负载，返回归一化后的事件。
    @discardableResult
    public func ingest(_ payload: [String: Any]) throws -> AgentEvent {
        try queue.sync {
            let agentID = AgentAdapterFactory.canonicalID(payload["agent"] as? String)
            let adapter = AgentAdapterFactory.adapter(for: agentID)
            let event = try adapter.normalize(payload)
            if shouldAcceptEvent(event) {
                append(event)
            }
            return event
        }
    }

    /// 转成 HTTP 响应。
    private func processEvent(_ body: [String: Any]?) -> AgentHTTPResult {
        guard let body else {
            return AgentHTTPResult(status: 400, body: ["ok": false, "error": "missing body"])
        }
        do {
            let event = try ingest(body)
            return AgentHTTPResult(status: 200, body: [
                "ok": true,
                "id": event.id,
                "agent": event.agent,
                "sessionId": event.sessionId,
                "event": event.type.rawValue,
                "timestamp": event.timestamp.timeIntervalSince1970,
            ])
        } catch {
            return AgentHTTPResult(status: 200, body: ["ok": false, "error": "\(error)"])
        }
    }

    // MARK: - State (thread-safe accessors)

    public var clientCount: Int { eventCount }

    public func snapshotSessions() -> [AgentSession] {
        queue.sync { sessionList() }
    }

    /// 指定会话的事件快照（按时间序）。
    public func events(for sessionID: String) -> [AgentEvent] {
        queue.sync { sessions[sessionID] ?? [] }
    }

    // MARK: - Internals

    private func sessionList() -> [AgentSession] {
        sessions.map { key, events in
            AgentSession(
                id: key,
                agent: events.first?.agent ?? "unknown",
                events: events,
                startTime: events.first?.timestamp ?? Date()
            )
        }
    }

    private func append(_ event: AgentEvent) {
        sessions[event.sessionId, default: []].append(event)
        eventCount += 1
        sink.handle(event)
        eventObserver?(event)
    }
}
