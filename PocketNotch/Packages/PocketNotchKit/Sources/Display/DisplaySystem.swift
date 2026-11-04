import Foundation
import Combine

/// Display 架构的装配门面。
///
/// 一次性创建并持有整套 Display 架构：
/// Activity Store · Agent Awareness · Notification System · Scheduler · Coordinator。
/// App 只需持有一个 `DisplaySystem` 实例，并通过它把业务状态喂进来。
@MainActor
public final class DisplaySystem: ObservableObject {
    public let activityStore: ActivityStore
    public let registry: AgentRegistry
    public let sessionStore: SessionStore
    public let awareness: AgentAwareness
    public let notificationQueue: NotificationQueue
    public let notificationStore: NotificationStore
    public let notificationCenter: NotificationCenter
    public let pipeline: AgentEventPipeline
    public let scheduler: DisplayScheduler
    public let coordinator: DisplayCoordinator
    private var isAgentMonitoringEnabled = false

    public init() {
        let activityStore = ActivityStore()
        let registry = AgentRegistry()
        let sessionStore = SessionStore()
        let awareness = AgentAwareness(sessionStore: sessionStore)
        let notificationQueue = NotificationQueue()
        let notificationStore = NotificationStore()
        let notificationCenter = NotificationCenter(
            queue: notificationQueue,
            store: notificationStore
        )
        let pipeline = AgentEventPipeline(
            awareness: awareness,
            notificationCenter: notificationCenter,
            registry: registry
        )
        let scheduler = DisplayScheduler(
            activityStore: activityStore,
            agentAwareness: awareness,
            notificationQueue: notificationQueue
        )
        let coordinator = DisplayCoordinator(scheduler: scheduler)

        self.activityStore = activityStore
        self.registry = registry
        self.sessionStore = sessionStore
        self.awareness = awareness
        self.notificationQueue = notificationQueue
        self.notificationStore = notificationStore
        self.notificationCenter = notificationCenter
        self.pipeline = pipeline
        self.scheduler = scheduler
        self.coordinator = coordinator
    }

    /// 启动所有 Agent 采集与生命周期管理。
    public func start(agentMonitoringEnabled: Bool = true) {
        setAgentMonitoringEnabled(agentMonitoringEnabled)
    }

    /// Agent 关闭时不保留进程扫描、watchdog 或 adapter 任务。
    public func setAgentMonitoringEnabled(_ enabled: Bool) {
        guard enabled != isAgentMonitoringEnabled else { return }
        isAgentMonitoringEnabled = enabled
        if enabled {
            pipeline.startAll()
            awareness.start()
        } else {
            pipeline.stopAll()
            awareness.stop()
            clearAgentState()
        }
    }

    /// 清除全部 Agent 感知状态（Agent 感知关闭时调用）。
    ///
    /// Agent 感知关闭时，残留的 Running Session 会让调度器持续产出 Agent 决策，
    /// 进而让常驻内容（媒体/股票/天气）一直被让位。清空后立即重算，
    /// 使决策回落到仍处于活跃的 Activity。
    public func clearAgentState() {
        awareness.clear()
        notificationQueue.clear()
        scheduler.recompute()
    }
}
