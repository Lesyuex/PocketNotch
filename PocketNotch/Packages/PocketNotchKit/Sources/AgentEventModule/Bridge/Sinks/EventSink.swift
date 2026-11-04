import Foundation

/// 事件输出目标。Phase 1 支持 Console 与 JSONL 文件，未来可替换为
/// State Manager / Activity Scheduler / PocketNotch UI 消费方。
public protocol EventSink: Sendable {
    func handle(_ event: AgentEvent)
}

/// 事件分发器：把统一事件分发给多个 sink。
public final class EventMulticaster: EventSink {
    private let sinks: [EventSink]

    public init(sinks: [EventSink]) {
        self.sinks = sinks
    }

    public func handle(_ event: AgentEvent) {
        for sink in sinks {
            sink.handle(event)
        }
    }
}