import Foundation
import Combine

/// 显示调度器——整个系统的核心。
///
/// 职责（设计文档第十二、十九、二十章）：
/// 根据 Activity、Agent、Notification 的当前状态，生成 PocketNotch 此刻应展示的内容。
///
/// 输入：`ActivityStore`、`AgentAwareness`、`NotificationQueue`。
/// 输出：`DisplayDecision`。
///
/// 铁律：Scheduler 不负责业务判断——这里不出现
/// `if claude.running` / `if codex.running` / `if music.isPlaying`。
/// 业务状态由各自的 Store / System 提供，Scheduler 只处理 Candidate → Policy → Decision。
@MainActor
public final class DisplayScheduler: ObservableObject {
    public let activityStore: ActivityStore
    public let agentAwareness: AgentAwareness
    public let notificationQueue: NotificationQueue
    public let policy: DisplayPolicy

    @Published public private(set) var currentDecision: DisplayDecision?

    /// 轮换状态：当 Agent / Activity 池有多个候选时，按 tick 递增取模轮换。
    private var rotationCounter = 0

    public init(
        activityStore: ActivityStore,
        agentAwareness: AgentAwareness,
        notificationQueue: NotificationQueue,
        policy: DisplayPolicy = CategoryDisplayPolicy()
    ) {
        self.activityStore = activityStore
        self.agentAwareness = agentAwareness
        self.notificationQueue = notificationQueue
        self.policy = policy

        // 订阅三个来源的变化，任一变化都触发重新计算 Display。
        activityStore.$activities
            .combineLatest(agentAwareness.$displayStates, notificationQueue.$activeNotifications)
            .sink { [weak self] _, _, _ in
                Task { @MainActor [weak self] in
                    self?.recompute()
                }
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Public API

    /// 重新计算当前 DisplayDecision（由状态变化自动触发，也可手动调用）。
    public func recompute() {
        currentDecision = resolve()
    }

    /// 显式推进轮换（供外部定时器或 UI 触发）。
    public func advanceRotation() {
        rotationCounter &+= 1
        recompute()
    }

    // MARK: - Resolution

    /// 把三个来源聚合为一个候选集，交给 Policy 决策。
    func candidates() -> [DisplayCandidate] {
        var result: [DisplayCandidate] = []

        // Activity 候选
        for activity in activityStore.activeActivities {
            result.append(DisplayCandidate(
                id: "activity-\(activity.kind.rawValue)",
                source: .activity,
                isActive: activity.isActive,
                updatedAt: activity.updatedAt
            ))
        }

        // Agent 候选：Agent Display Pool（仅含 Running Session 的 Agent）。
        for agent in agentAwareness.activeAgents() {
            result.append(DisplayCandidate(
                id: "agent-\(agent.agentId)",
                source: .agent,
                isActive: true,
                updatedAt: agent.updatedAt
            ))
        }

        // Notification 候选：队首通知。
        if let notification = notificationQueue.peek() {
            // 所有瞬时通知都必须抢占常驻内容；通知结束后由 Scheduler 重新计算，
            // 因而恢复通知期间最新的 Agent / Activity 状态。
            result.append(DisplayCandidate(
                id: "notification-\(notification.id.uuidString)",
                source: .notification,
                isActive: true,
                updatedAt: notification.createdAt
            ))
        }

        return result
    }

    private func resolve() -> DisplayDecision? {
        let candidates = candidates()
        let group = policy.selectGroup(from: candidates)
        guard !group.isEmpty else { return nil }

        // 在赢家组内用轮换索引挑选当前展示项（组内含多个 Agent / Activity 时轮换）。
        let index = pooledIndex(for: group.count)
        let selected = group[index]

        // 依据选中的 Candidate id 反查内容。
        switch selected.source {
        case .activity:
            let kind = selected.id.replacingOccurrences(of: "activity-", with: "")
            if let activity = activityStore.snapshot(ActivityKind(rawValue: kind) ?? .music) {
                return DisplayDecision(content: .activity(activity))
            }
        case .agent:
            let agentId = selected.id.replacingOccurrences(of: "agent-", with: "")
            if let agent = agentAwareness.displayState(for: agentId) {
                return DisplayDecision(content: .agent(agent))
            }
        case .notification:
            if let notification = notificationQueue.peek() {
                return DisplayDecision(content: .notification(notification))
            }
        }
        return nil
    }

    /// 当前轮换点：池内第 index 项（供扩展轮换策略）。
    func pooledIndex(for count: Int) -> Int {
        guard count > 0 else { return 0 }
        return rotationCounter % count
    }
}
