import Foundation
import Combine

/// 事件驱动的门面：把外部（既有 AgentEventModule 桥接、测试、或其它来源）
/// 归一化后的事件统一注入 Display 架构。
///
/// 设计文档第五章：所有 Agent Adapter 最终统一转换成 PocketNotch 自己的事件模型，
/// 然后交给 AgentAwareness（更新 SessionState）与 NotificationCenter（创建通知）。
@MainActor
public final class AgentEventPipeline: ObservableObject {
    public let awareness: AgentAwareness
    public let notificationCenter: NotificationCenter

    private let registry: AgentRegistry
    private var eventTasks: [Task<Void, Never>] = []

    public init(
        awareness: AgentAwareness,
        notificationCenter: NotificationCenter,
        registry: AgentRegistry
    ) {
        self.awareness = awareness
        self.notificationCenter = notificationCenter
        self.registry = registry

        // AgentAwareness 的事件回调：同步产出一条通知（反馈），保持两套状态解耦。
        awareness.onEvent = { [weak self] event in
            guard let self else { return }
            guard !event.isStateOnly else { return }

            // 抑制冗余通知：sessionRunning 表示「Agent 正在持续运行」，
            // 运行状态已经由 Agent 的运行展示本身表达，若再额外产生瞬时通知，
            // 会与运行中的 Agent 内容重叠并不断堆积（Agent 运行时每个阶段都可能发 running 事件）。
            // agentStart 虽然在状态层映射为 sessionRunning，但语义上是一次用户任务启动，
            // 应产生一次临时反馈；思考、工具和命令等其它 running 事件仍保持静默。
            let isAgentStart = event.originType == "agentStart"
            guard event.type != .sessionRunning || isAgentStart else { return }

            let displayName = self.registry.adapter(for: event.agentId)?.displayName
            self.notificationCenter.receive(event, agentDisplayName: displayName)
        }
    }

    /// 手动注入一条归一化事件（阶段一验证数据流用）。
    public func ingest(_ event: AgentEvent) {
        awareness.ingest(event)
    }

    /// 启动所有已注册 Agent 的采集并订阅其事件流。
    public func startAll() {
        guard eventTasks.isEmpty else { return }
        registry.startAll()
        for adapter in registry.adapters {
            let stream = adapter.events()
            let task = Task { @MainActor [weak self] in
                for await event in stream {
                    guard let self else { break }
                    self.awareness.ingest(event)
                }
            }
            eventTasks.append(task)
        }
    }

    public func stopAll() {
        eventTasks.forEach { $0.cancel() }
        eventTasks.removeAll()
        registry.stopAll()
    }
}
