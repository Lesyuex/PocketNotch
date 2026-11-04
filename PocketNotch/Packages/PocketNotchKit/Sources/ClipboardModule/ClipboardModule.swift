import PocketNotchCore
import SwiftUI

/// 剪贴板模块：「此刻」页显示紧凑剪贴卡，独立「剪贴板」标签页横向陈列全部历史。
/// 轮询系统剪贴板收藏最近 10 条文本/链接/图片，点选即可复制回剪贴板；
/// 标签页切换由「此刻」页剪贴卡标题区的激活按钮手动发起。
public struct ClipboardModule: PocketNotchModule {
    public let id = "clipboard"
    public let title: LocalizedStringKey = "module.clipboard.title"
    public let priority = 45

    @MainActor private let store: ClipboardStore

    @MainActor
    public init(expandedTabRequest: ExpandedTabRequestController) {
        self.store = ClipboardStore(expansionRequest: expandedTabRequest)
    }

    public var showsInExpandedPage: Bool { true }
    public var expandedIslandTab: ExpandedIslandTab { .clipboard }

    public func expandedView() -> AnyView {
        AnyView(ClipboardExpandedView(store: store))
    }

    /// 「此刻」页剪贴板小卡：紧凑陈列最近内容，标题区带「打开剪贴板标签」按钮。
    @MainActor
    public func nowPageTrailingAccessoryView() -> AnyView? {
        AnyView(NowClipboardCardView(store: store))
    }

    public func activate() {
        Task { @MainActor in store.start() }
    }

    public func deactivate() {
        Task { @MainActor in store.stop() }
    }
}