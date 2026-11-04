import PocketNotchCore
import SwiftUI

/// 待办事项模块：只向「此刻」页提供居中的待办卡片，不占独立标签页。
public struct TodoModule: PocketNotchModule {
    public let id = "todo"
    public let title: LocalizedStringKey = "module.todo.title"
    public let priority = 50

    @MainActor private let store = TodoStore()

    public init() {}

    public var showsInExpandedPage: Bool { true }

    public var expandedIslandTab: ExpandedIslandTab { .now }

    public func expandedView() -> AnyView {
        AnyView(Color.clear)
    }

    @MainActor
    public func nowPageCenterAccessoryView() -> AnyView? {
        AnyView(NowTodoCardView(store: store))
    }

    public func activate() {
        Task { @MainActor in await store.prepare() }
    }

    public func deactivate() {}
}