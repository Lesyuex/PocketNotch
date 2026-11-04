import PocketNotchCore
import SwiftUI

public struct ApplicationsModule: PocketNotchModule {
    public let id = "applications"
    public let title: LocalizedStringKey = "module.applications.title"
    public let priority = 40

    public init() {}

    public var showsInExpandedPage: Bool { true }

    public var expandedIslandTab: ExpandedIslandTab { .applications }

    public var expandedPagePreferredContentHeight: CGFloat? {
        ApplicationPageLayout.contentHeight
    }

    public func expandedView() -> AnyView {
        AnyView(ApplicationLauncherView())
    }

    public func activate() {}
    public func deactivate() {}
}
