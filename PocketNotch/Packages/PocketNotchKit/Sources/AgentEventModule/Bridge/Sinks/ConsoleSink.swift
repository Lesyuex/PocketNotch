import Foundation

/// 控制台输出 sink（Phase 1 调试用途）。
public struct ConsoleSink: EventSink {
    private let printer: @Sendable (String) -> Void

    public init(printer: (@Sendable (String) -> Void)? = nil) {
        self.printer = printer ?? { print($0) }
    }

    public func handle(_ event: AgentEvent) {
        var line = "[\(Self.timeString(event.timestamp))] [\(event.agent)] \(event.type.rawValue)"
        let context: [String] = [
            event.action.map { "tool:\($0)" },
            event.file.map { "file:\($0)" },
            event.command.map { "cmd:\($0)" },
        ].compactMap { $0 }
        if !context.isEmpty { line += " " + context.joined(separator: " ") }
        if let message = event.message { line += "\n    \(message)" }
        printer("PocketNotch[Agent-\(event.sessionId.prefix(6))] \(line)")
    }

    private static func timeString(_ date: Date) -> String {
        Self.hhmmssFormatter.string(from: date)
    }

    private static let hhmmssFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}