import SwiftUI
import PocketNotchCore

/// Agent 活动采集模块。
///
/// 监听在用户显式开启后才启动（`controller.startIfEnabled()`）。
/// Codex 回调会通过 compact notification 短暂显示工作状态。
public struct AgentActivityModule: PocketNotchModule {
    public let id = "agentActivity"
    public let title: LocalizedStringKey = "module.agentActivity.title"
    public let priority = 4

    @MainActor private let controller: AgentActivityController
    @MainActor private let historyStore: AgentSessionHistoryStore

    @MainActor
    public init(controller: AgentActivityController) {
        self.controller = controller
        self.historyStore = AgentSessionHistoryStore()
    }

    public func compactNotificationLeadingView() -> AnyView {
        AnyView(AgentWorkingLeadingView(
            presentationController: controller.workingPresentationController,
            petController: controller.petController
        ))
    }

    public func compactNotificationTrailingView() -> AnyView {
        AnyView(AgentWorkingTrailingView(
            presentationController: controller.workingPresentationController
        ))
    }

    /// 临时优先级（同区互斥用）：数值越大越优先抢先显示。
    /// 等待授权 / 失败等瞬时反馈高于切歌（Media=20），Agent 运行态最低（10）。
    @MainActor
    public func transientVisualPriority() -> Int? {
        guard let state = controller.workingPresentationController.presentation?.petState else {
            return nil
        }
        switch state {
        case .waiting: return 30          // 等待授权：最高
        case .failed, .jumping: return 25 // 失败 / 完成：高
        case .running, .runningLeft, .runningRight, .review, .waving, .idle:
            return 10                     // Agent 运行/思考/启动：作为常驻性临时的最低档
        }
    }

    public var showsInExpandedPage: Bool { false }

    public var expandedIslandTab: ExpandedIslandTab { .ai }

    public var expandedPagePreferredContentHeight: CGFloat? { 280 }

    public func expandedView() -> AnyView {
        AnyView(AgentSessionHistoryView(
            store: historyStore,
            eventCounter: controller.eventCounter
        ))
    }

    public func activate() {
        Task { @MainActor in
            controller.startIfEnabled()
        }
    }

    public func deactivate() {
        Task { @MainActor in
            controller.stop()
        }
    }
}
