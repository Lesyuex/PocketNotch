import Foundation
import Network

/// 服务器错误。
public enum AgentServerError: LocalizedError, Equatable {
    case invalidPort(UInt16)
    public var errorDescription: String? {
        switch self {
        case .invalidPort(let port): return "invalid port: \(port)"
        }
    }
}

/// HTTP 请求处理结果。
public struct AgentHTTPResult {
    public let status: Int
    public let body: [String: Any]

    public init(status: Int, body: [String: Any]) {
        self.status = status
        self.body = body
    }
}

/// 保证 continuation 只恢复一次的占位标记，避免并发条件下双重 resume。
private final class ResumeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resolve(_ action: @Sendable () -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        action()
    }
}

/// 极简 loopback HTTP 服务器，只服务本地 Agent 上报。
///
/// 仅绑定回环地址，避免任何外部网络访问；只解析 HTTP/1.1 请求行、
/// 请求头与 Content-Length 长度内的 JSON body，不实现其它方法。
public final class LocalHTTPServer: @unchecked Sendable {
    public typealias Handler = @Sendable (String, [String: Any]?) -> AgentHTTPResult

    public private(set) var isRunning = false

    private let listener: NWListener
    private let handler: Handler
    private let flag: ResumeFlag
    private let queue = DispatchQueue(label: "pocketnotch.agent.http.server")
    private var connections: [NWConnection] = []

    /// - Parameters:
    ///   - port: 监听端口。传 0 表示由系统分配。
    ///   - handler: 收到完整请求后调用，返回响应。
    public init(port: UInt16, handler: @escaping Handler) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback
        guard let portEndpoint = NWEndpoint.Port(rawValue: port) else {
            throw AgentServerError.invalidPort(port)
        }
        listener = try NWListener(using: parameters, on: portEndpoint)
        self.flag = ResumeFlag()
        self.handler = handler
    }

    /// 开始监听，返回前等待到 `.ready` 状态，端口冲突或非法时会抛错。
    public func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isRunning = true
                    self.flag.resolve { continuation.resume() }
                case .failed(let error):
                    self.isRunning = false
                    self.flag.resolve { continuation.resume(throwing: error) }
                case .cancelled:
                    self.isRunning = false
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
        }
    }

    public func stop() {
        listener.cancel()
        isRunning = false
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
    }

    // MARK: - Connection handling

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            var accumulated = buffer
            if let data, !data.isEmpty {
                accumulated.append(data)
            }
            switch self.consume(connection, accumulated) {
            case .handled:
                break
            case .needMoreData:
                if isComplete || error != nil {
                    self.respond(connection, result: .init(status: 400, body: ["ok": false, "error": "incomplete request"]))
                } else {
                    self.receive(connection, buffer: accumulated)
                }
            }
        }
    }

    private enum ConsumeResult {
        case handled
        case needMoreData
    }

    private func consume(_ connection: NWConnection, _ data: Data) -> ConsumeResult {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator) else {
            return .needMoreData
        }
        let headerData = data.subdata(in: data.startIndex ..< headerRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8),
              let parsed = Self.parse(headers: headerText) else {
            respond(connection, result: .init(status: 400, body: ["ok": false, "error": "malformed request"]))
            return .handled
        }

        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + parsed.contentLength else {
            return .needMoreData
        }
        let bodyData = data.subdata(in: bodyStart ..< bodyStart + parsed.contentLength)
        let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]

        let result = handler(parsed.path, json)
        respond(connection, result: result)
        return .handled
    }

    private func respond(_ connection: NWConnection, result: AgentHTTPResult) {
        let bodyData = (try? JSONSerialization.data(withJSONObject: result.body)) ?? Data()
        var header = "HTTP/1.1 \(result.status) PocketNotch\r\n"
        header += "Content-Type: application/json\r\n"
        header += "Content-Length: \(bodyData.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var payload = header.data(using: .utf8) ?? Data()
        payload.append(bodyData)
        connection.send(content: payload, completion: .contentProcessed { [weak self, weak connection] _ in
            connection?.cancel()
            if let self, let connection {
                self.connections.removeAll { $0 === connection }
            }
        })
    }

    // MARK: - HTTP parsing

    private struct ParsedRequest {
        let path: String
        let contentLength: Int
    }

    private static func parse(headers text: String) -> ParsedRequest? {
        var lines = text.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst()
        let components = requestLine.split(separator: " ").map(String.init)
        guard components.count >= 2 else { return nil }
        let path = components[1]

        var contentLength = 0
        for line in lines {
            let pair = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if pair.count == 2, pair[0].lowercased() == "content-length",
               let length = Int(pair[1]) {
                contentLength = length
            }
        }
        return ParsedRequest(path: path, contentLength: contentLength)
    }
}