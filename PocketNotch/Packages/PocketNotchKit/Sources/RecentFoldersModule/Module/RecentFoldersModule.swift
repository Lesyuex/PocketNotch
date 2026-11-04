import SwiftUI
import PocketNotchCore

public struct RecentFoldersModule: PocketNotchModule {
    public let id = "recentFolders"
    public let title: LocalizedStringKey = "module.recentFolders.title"
    public let priority = 40

    @MainActor private let viewModel = RecentFoldersViewModel()

    public init() {}

    public var showsInExpandedPage: Bool { false }

    public var expandedIslandTab: ExpandedIslandTab { .folders }

    public func expandedView() -> AnyView {
        AnyView(RecentFoldersExpandedView(viewModel: viewModel))
    }

    /// 「此刻」页常用文件夹小卡：真实「最近使用的文件夹」前 4 个，锁定的固定在前。
    @MainActor
    public func nowPageFolderAccessoryView() -> AnyView? {
        AnyView(NowQuickStatsCardView(viewModel: viewModel))
    }

    public func activate() {
        Task { @MainActor in viewModel.reload() }
    }

    public func deactivate() {}
}