import Foundation

/// 内容来源类别。
public enum DisplaySource: String, Hashable, Sendable {
    case activity
    case agent
    case notification
}

/// 进入 DisplayScheduler 的调度候选。
///
/// 设计文档第二十章：Scheduler 只根据 Candidate 调度，不关心业务具体实现。
public struct DisplayCandidate: Identifiable, Hashable, Sendable {
    public let id: String
    public let source: DisplaySource
    public let isActive: Bool
    public let updatedAt: Date

    public init(id: String, source: DisplaySource, isActive: Bool, updatedAt: Date) {
        self.id = id
        self.source = source
        self.isActive = isActive
        self.updatedAt = updatedAt
    }
}

/// 三类内容在 Display 层的统一表示。
///
/// 设计文档第十三章：这只是 Display 层统一表示，不代表三种业务模型被合并；
/// 业务层依然保持独立（Agent 不与 Music/Weather/Stock 合并，Notification 与 Agent 状态解耦）。
public enum DisplayContent: Sendable {
    case activity(ActivityContent)
    case agent(AgentDisplayState)
    case notification(PocketNotchNotification)

    public var source: DisplaySource {
        switch self {
        case .activity: .activity
        case .agent: .agent
        case .notification: .notification
        }
    }
}

/// DisplayScheduler 的输出：此刻 PocketNotch 应该展示什么，以及它来自哪。
public struct DisplayDecision: Sendable {
    public let content: DisplayContent
    public let source: DisplaySource

    public init(content: DisplayContent) {
        self.content = content
        self.source = content.source
    }
}