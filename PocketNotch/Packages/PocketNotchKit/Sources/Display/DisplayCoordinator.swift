import Foundation
import Combine

/// 显示协调器——所有内容最终只能通过它进入 PocketNotch。
///
/// 设计文档第二章核心原则：
/// 禁止 `MusicManager → PocketNotch`、`AgentManager → PocketNotch`、`NotificationManager → PocketNotch`。
/// 所有业务模块把状态喂给各自的 Store / System，统一流入 `DisplayScheduler`，
/// 由 `DisplayCoordinator` 把最终 `DisplayDecision` 交给 PocketNotch 渲染层。
@MainActor
public final class DisplayCoordinator: ObservableObject {
    public let scheduler: DisplayScheduler
    /// 暴露给渲染层的最终决策。UI 只消费它，不直接触碰业务模块。
    @Published public private(set) var decision: DisplayDecision?

    private var cancellables = Set<AnyCancellable>()

    public init(scheduler: DisplayScheduler) {
        self.scheduler = scheduler
        scheduler.$currentDecision
            .sink { [weak self] decision in
                self?.decision = decision
            }
            .store(in: &cancellables)
    }

    /// 触发一次重新计算并推送到渲染层。
    public func refresh() {
        scheduler.recompute()
    }

    // MARK: - 渲染层门控（单一决策原则）

    /// 渲染层据此判断「此刻是否应展示指定来源的内容」。
    ///
    /// 设计文档原则 5/6：只有 DisplayCoordinator 决定 PocketNotch 当前显示什么。
    /// 渲染层（上岛 UI / 通知槽）在绘制前调用本方法，只有与当前决策匹配的来源才允许展示，
    /// 从而避免 Agent 运行内容与瞬时通知等不同来源相互重叠。
    /// 例如：`shouldShow(.notification)` 为 true 时才渲染通知槽，否则隐藏。
    public func shouldShow(_ source: DisplaySource) -> Bool {
        decision?.source == source
    }

    /// 当前决策所对应的来源。无决策时返回 nil。
    public var currentSource: DisplaySource? {
        decision?.source
    }

    /// 当前是否有任何内容被调度展示。
    public var hasActiveDecision: Bool {
        decision != nil
    }
}