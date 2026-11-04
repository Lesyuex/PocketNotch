import SwiftUI

struct CompactIslandContentVisiblePreferenceKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct CompactIslandPreferredWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 瞬时通知视图上报：需要隐藏常驻模块内容，避免通知内容与常驻内容视觉叠加。
/// 与 `CompactIslandPreferredWidthPreferenceKey` 解耦——不改变岛宽的临时内容
/// （如耳机连接提示）同样需要让常驻封面/旋律退场。
struct CompactIslandSuppressesResidentContentPreferenceKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

public extension View {
    /// 由功能模块告知岛容器当前是否需要进入 compact 状态并显示两侧内容。
    func compactIslandContentVisible(_ visible: Bool) -> some View {
        preference(key: CompactIslandContentVisiblePreferenceKey.self, value: visible)
    }

    /// 由临时内容上报完整展示所需的最小 Island 宽度；内容消失后自动恢复用户设置。
    func compactIslandPreferredWidth(_ width: CGFloat?) -> some View {
        preference(
            key: CompactIslandPreferredWidthPreferenceKey.self,
            value: width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 0
        )
    }

    /// 由瞬时通知视图上报是否应隐藏常驻模块内容（不改变岛宽，但覆盖常驻区域）。
    func compactIslandSuppressesResidentContent(_ suppress: Bool) -> some View {
        preference(
            key: CompactIslandSuppressesResidentContentPreferenceKey.self,
            value: suppress
        )
    }
}
