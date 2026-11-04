import Combine
import Foundation
import Display

/// 把既有 `AgentEventModule.AgentEvent` 桥接为 `Display.AgentEvent` 并注入 Display 架构。
///
/// 这是「信息传递」的适配层：它不包含任何 UI 逻辑，只负责把 AgentEventModule 归一化后的
/// 事件转换成语义等价的 Display 事件，喂给 `DisplaySystem`（经 `AgentAwareness` 更新 Session，
/// 经 `NotificationCenter` 产生瞬时通知）。既有 Agent 采集管线（Bridge / Sink）无需改动。
///
/// 设计文档第五章：所有 Agent Adapter 最终统一转换成 PocketNotch 自己的事件模型。
@MainActor
public final class DisplayEventBridge {
    private let displaySystem: DisplaySystem
    private let processResolver: AgentProcessAncestryResolver

    public init(
        displaySystem: DisplaySystem,
        processCommand: any ProcessCommandProviding = SystemProcessCommand()
    ) {
        self.displaySystem = displaySystem
        self.processResolver = AgentProcessAncestryResolver(processCommand: processCommand)
    }

    /// 实现 `EventSink`，可直接追加到既有 `AgentEventBridge` 的 sinks 中。
    public func makeEventSink() -> any EventSink {
        DisplayBridgeSink(bridge: self)
    }

    /// 单条转换并注入。
    public func ingest(_ event: AgentEvent) {
        displaySystem.pipeline.ingest(convert(event))
    }

    /// 把既有事件映射为 Display 事件模型。
    func convert(_ event: AgentEvent) -> Display.AgentEvent {
        let agentId = AgentAdapterFactory.canonicalID(event.agent)
        let isStateOnly = event.source == .rollout
            && event.type != .completed
            && event.type != .failed
        let runtimePID = processResolver.resolve(
            agentId: agentId,
            pid: event.pid,
            parentPID: event.parentPID
        )
        return Display.AgentEvent(
            id: event.id,
            agentId: agentId,
            sessionId: event.sessionId,
            type: convert(event.type),
            timestamp: event.timestamp,
            pid: runtimePID,
            parentPID: nil,
            exitCode: event.exitCode,
            message: event.message,
            originType: event.type.rawValue,
            isStateOnly: isStateOnly
        )
    }

    func convert(_ type: EventType) -> Display.AgentEventType {
        switch type {
        case .sessionStart:
            return .sessionCreated
        case .agentStart, .thinking, .toolStart, .toolEnd, .commandStart, .commandEnd:
            return .sessionRunning
        case .sessionEnd:
            return .sessionEnded
        case .waitingApproval:
            return .sessionWaitingApproval
        case .completed:
            return .sessionCompleted
        case .failed:
            return .sessionFailed
        case .stopRequested:
            return .sessionStopRequested
        }
    }

    public func awarenessEvents() -> AnyPublisher<Display.AgentEvent, Never> {
        displaySystem.awareness.eventsPublisher
    }
}

private final class DisplayBridgeSink: EventSink {
    private let bridge: DisplayEventBridge

    init(bridge: DisplayEventBridge) {
        self.bridge = bridge
    }

    func handle(_ event: AgentEvent) {
        Task { @MainActor [bridge] in
            bridge.ingest(event)
        }
    }
}
