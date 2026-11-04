import SwiftUI
import PocketNotchCore

public struct AgentSessionsModule: PocketNotchModule {
    public let id = "agentSessions"
    public let title: LocalizedStringKey = "module.agentSessions.title"
    public let priority = 60

    public var showsInExpandedPage: Bool { true }
    public var expandedIslandTab: ExpandedIslandTab { .agentSessions }
    public var expandedPagePreferredContentHeight: CGFloat? { 300 }

    public func expandedView() -> AnyView {
        AnyView(AgentSessionsView())
    }

    public func activate() {}
    public func deactivate() {}

    public init() {}
}