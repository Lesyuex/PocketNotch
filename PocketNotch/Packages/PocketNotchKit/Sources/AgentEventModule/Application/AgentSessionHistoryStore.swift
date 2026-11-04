import Combine
import Foundation

enum AgentHistorySessionStatus: Equatable {
    case started
    case active
    case waitingApproval
    case completed
    case failed
    case closed
    case unknown
}

struct AgentHistorySession: Identifiable, Sendable, Equatable {
    static let staleInterval: TimeInterval = 15 * 60

    let id: String
    let agentID: String
    let sessionID: String
    let events: [AgentEvent]

    var startTime: Date { events.first?.timestamp ?? .distantPast }
    var lastTransitionAt: Date { events.last?.timestamp ?? startTime }
    var sourceApplication: String? {
        events.reversed().lazy.compactMap(\.sourceApplication).first
    }
    var sourceBundleIdentifier: String? {
        events.reversed().lazy.compactMap(\.sourceBundleIdentifier).first
    }
    var latestPrompt: String? {
        events.reversed().lazy
            .filter { $0.type == .agentStart }
            .compactMap { event in
                guard let message = event.message else { return nil }
                let prompt = message
                    .split(whereSeparator: \.isNewline)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return prompt.isEmpty ? nil : prompt
            }
            .first
    }

    func status(
        at date: Date,
        staleAfter: TimeInterval = AgentHistorySession.staleInterval
    ) -> AgentHistorySessionStatus {
        guard let latestEvent = events.last else { return .unknown }

        switch latestEvent.type {
        case .sessionEnd:
            return .closed
        case .completed:
            return .completed
        case .failed:
            return .failed
        default:
            break
        }

        guard date.timeIntervalSince(lastTransitionAt) <= staleAfter else {
            return .unknown
        }

        switch latestEvent.type {
        case .sessionStart:
            return .started
        case .waitingApproval:
            return .waitingApproval
        default:
            return .active
        }
    }
}

enum AgentSessionHistoryReader {
    private struct SessionKey: Hashable {
        let agentID: String
        let sessionID: String
    }

    static func load(
        from fileURL: URL,
        maximumBytes: UInt64 = 4 * 1_024 * 1_024,
        maximumEvents: Int = 4_000,
        maximumSessions: Int = 200
    ) throws -> [AgentHistorySession] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }

        let data = try trailingData(from: fileURL, maximumBytes: maximumBytes)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let events = data.split(separator: 0x0A, omittingEmptySubsequences: true)
            .suffix(maximumEvents)
            .compactMap { try? decoder.decode(AgentEvent.self, from: Data($0)) }

        var grouped: [SessionKey: [AgentEvent]] = [:]
        for event in events {
            let agentID = AgentAdapterFactory.canonicalID(event.agent)
            let key = SessionKey(agentID: agentID, sessionID: event.sessionId)
            grouped[key, default: []].append(event)
        }

        return grouped.map { key, events in
            let sortedEvents = events.sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp { return lhs.id < rhs.id }
                return lhs.timestamp < rhs.timestamp
            }
            return AgentHistorySession(
                id: "\(key.agentID):\(key.sessionID)",
                agentID: key.agentID,
                sessionID: key.sessionID,
                events: sortedEvents
            )
        }
        .sorted { lhs, rhs in
            if lhs.lastTransitionAt == rhs.lastTransitionAt { return lhs.id < rhs.id }
            return lhs.lastTransitionAt > rhs.lastTransitionAt
        }
        .prefix(maximumSessions)
        .map { $0 }
    }

    private static func trailingData(from fileURL: URL, maximumBytes: UInt64) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        let startOffset = fileSize > maximumBytes ? fileSize - maximumBytes : 0
        try handle.seek(toOffset: startOffset)
        var data = try handle.readToEnd() ?? Data()

        // A tail read can begin in the middle of a JSON line; discard only that fragment.
        if startOffset > 0, let newline = data.firstIndex(of: 0x0A) {
            data = Data(data[data.index(after: newline)...])
        }
        return data
    }
}

@MainActor
final class AgentSessionHistoryStore: ObservableObject {
    @Published private(set) var sessions: [AgentHistorySession] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let fileURL: URL
    private var loadTask: Task<Void, Never>?

    init(fileURL: URL = AgentEventBridge.defaultPath) {
        self.fileURL = fileURL
    }

    deinit {
        loadTask?.cancel()
    }

    func reload() {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        let fileURL = fileURL

        loadTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { try AgentSessionHistoryReader.load(from: fileURL) }
            }.value
            guard !Task.isCancelled, let self else { return }

            switch result {
            case let .success(sessions):
                self.sessions = sessions
                self.errorMessage = nil
            case let .failure(error):
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }
}
