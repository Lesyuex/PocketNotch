import AppKit
import Observation

/// 展开页「即输即搜」共享状态。
///
/// 标签栏搜索框与对应模块内容共享同一实例：搜索框绑定 `text`，
/// 键盘监听把窗口内按键直接写入 `text`（搜索框无需获得焦点），
/// 模块视图按 `text` 过滤数据并通过 `onSubmit` 声明回车动作。
@Observable
public final class ExpandedIslandSearchModel {
    public var text = ""
    public var isVisible = false
    public var onSubmit: (() -> Void)?
    public private(set) weak var hostWindow: NSWindow?

    public init() {}

    func attach(window: NSWindow?) {
        hostWindow = window
    }

    public func reset() {
        text = ""
        onSubmit = nil
    }
}