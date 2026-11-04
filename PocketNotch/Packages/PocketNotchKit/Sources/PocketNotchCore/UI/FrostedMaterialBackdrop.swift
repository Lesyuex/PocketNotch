import AppKit
import SwiftUI

/// 毛玻璃背板的背后取样基准层：`NSVisualEffectView` 系统材质负责「背后取样 +
/// 磨砂合成」，实时跟随背后窗口内容，观感即 macOS 原生毛玻璃。
/// （历史上尝试过 layer CIFilter 与私有 backdrop 半径接管，均无效或被系统忽略；
/// 现在只用材质本来的样子。）
///
/// `covered` = 被黑盖板完全遮住（收起/常驻态）。此刻把系统材质切到 `.inactive`，
/// 暂停背后取样与模糊合成——材质视图仍在视图树里（不拆树、不闪帧），
/// 只在展开才重新 `active`。旧实现 `state` 恒为 `.active`，导致毛玻璃在纯黑
/// 收起态也持续取样，无论音乐状态都产生每秒的常驻采样开销。
public struct FrostedMaterialBackdrop: NSViewRepresentable {
    public let covered: Bool

    public init(covered: Bool = false) {
        self.covered = covered
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = covered ? .inactive : .active
        view.wantsLayer = true
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        let nextState: NSVisualEffectView.State = covered ? .inactive : .active
        guard view.state != nextState else { return }
        view.state = nextState
    }
}