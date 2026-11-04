import SwiftUI

/// SwiftUI 根内容的测量结果。窗口控制器需要单独知道 Island 画布尺寸，
/// 才能在展开前同步预留最终画布，同时保留下方通知所需的额外高度。
public struct NotchContentLayoutMeasurement: Equatable, Sendable {
    public var totalSize: CGSize
    public var islandCanvasSize: CGSize
    public var interactiveSize: CGSize
    public var usesExpandedIslandCanvas: Bool

    public init(
        totalSize: CGSize,
        islandCanvasSize: CGSize,
        interactiveSize: CGSize? = nil,
        usesExpandedIslandCanvas: Bool
    ) {
        self.totalSize = totalSize
        self.islandCanvasSize = islandCanvasSize
        self.interactiveSize = interactiveSize ?? islandCanvasSize
        self.usesExpandedIslandCanvas = usesExpandedIslandCanvas
    }
}

/// 容器把「Island 画布 + 下方通知槽」的布局测量上报给窗口控制器。
/// 用 class + 闭包回调而非 Binding，避免 SwiftUI 重渲染回环。
@MainActor
public final class NotchContentSizeReporter {
    public var onSizeChange: ((CGSize) -> Void)?
    public var onLayoutChange: ((NotchContentLayoutMeasurement) -> Void)?
    private var last = NotchContentLayoutMeasurement(
        totalSize: .zero,
        islandCanvasSize: .zero,
        usesExpandedIslandCanvas: false
    )

    public init() {}

    public func report(_ size: CGSize) {
        report(size, islandCanvasSize: size, usesExpandedIslandCanvas: false)
    }

    public func report(
        _ size: CGSize,
        islandCanvasSize: CGSize,
        interactiveSize: CGSize? = nil,
        usesExpandedIslandCanvas: Bool
    ) {
        guard size.width > 0, size.height > 0 else { return }
        guard islandCanvasSize.width > 0, islandCanvasSize.height > 0 else { return }
        let interactiveSize = interactiveSize ?? islandCanvasSize
        guard interactiveSize.width > 0, interactiveSize.height > 0 else { return }
        let measurement = NotchContentLayoutMeasurement(
            totalSize: size,
            islandCanvasSize: islandCanvasSize,
            interactiveSize: interactiveSize,
            usesExpandedIslandCanvas: usesExpandedIslandCanvas
        )
        let totalChanged = Self.differs(size, from: last.totalSize)
        let islandChanged = Self.differs(islandCanvasSize, from: last.islandCanvasSize)
        let interactionChanged = Self.differs(interactiveSize, from: last.interactiveSize)
        let geometryChanged = usesExpandedIslandCanvas != last.usesExpandedIslandCanvas
        guard totalChanged || islandChanged || interactionChanged || geometryChanged else { return }
        last = measurement
        if totalChanged {
            onSizeChange?(size)
        }
        onLayoutChange?(measurement)
    }

    private static func differs(_ lhs: CGSize, from rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) > 0.5 || abs(lhs.height - rhs.height) > 0.5
    }
}

private struct NotchContentSizeReporterKey: EnvironmentKey {
    static let defaultValue: NotchContentSizeReporter? = nil
}

private struct NotchContentTopInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct NotchHiddenIslandSizeKey: EnvironmentKey {
    static let defaultValue = IslandBackgroundMetrics.default.hiddenSize
}

/// 灵动态「耳朵」（左右耳内容槽）的实际内容尺寸。与岛高解耦：调高隐藏态岛高不会改变它，
/// 耳朵只由用户的「耳朵高度」设置决定。compact 内容（封面/图标/旋律条）用它做尺寸基准，
/// 未注入时回退到按 `notchHiddenIslandSize.height` 推导（兼容通知等无布局上下文的场景）。
private struct IslandCompactContentSizeKey: EnvironmentKey {
    static let defaultValue: CGSize? = nil
}

/// 隐藏态（resting/收起）岛的物理尺寸。与 `notchHiddenIslandSize` 不同：
/// 后者在 `IslandRootView` 内会被覆盖为灵动态 content 宽度供 compact 内容布局，
/// 本值保持窗口控制器注入的原始隐藏态尺寸，供扩大画布层（如展开页）计算左右区域。
private struct NotchRestingIslandSizeKey: EnvironmentKey {
    static let defaultValue = IslandBackgroundMetrics.default.hiddenSize
}

private struct NotchPhysicalWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 210
}

private struct IslandFileDragLocationKey: EnvironmentKey {
    static let defaultValue: CGPoint? = nil
}

private struct IslandCollapseActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

/// 展开内容打开 Popover 等独立窗口时，用它占住 Island，避免指针移出主窗口触发收起。
public struct IslandExpandedContentInteraction {
    public var begin: () -> Void
    public var end: () -> Void

    public init(begin: @escaping () -> Void, end: @escaping () -> Void) {
        self.begin = begin
        self.end = end
    }
}

private struct IslandExpandedContentInteractionKey: EnvironmentKey {
    static let defaultValue: IslandExpandedContentInteraction? = nil
}

public extension EnvironmentValues {
    var notchContentSizeReporter: NotchContentSizeReporter? {
        get { self[NotchContentSizeReporterKey.self] }
        set { self[NotchContentSizeReporterKey.self] = newValue }
    }

    var notchContentTopInset: CGFloat {
        get { self[NotchContentTopInsetKey.self] }
        set { self[NotchContentTopInsetKey.self] = newValue }
    }

    var notchHiddenIslandSize: CGSize {
        get { self[NotchHiddenIslandSizeKey.self] }
        set { self[NotchHiddenIslandSizeKey.self] = newValue }
    }

    var islandCompactContentSize: CGSize? {
        get { self[IslandCompactContentSizeKey.self] }
        set { self[IslandCompactContentSizeKey.self] = newValue }
    }

    var notchRestingIslandSize: CGSize {
        get { self[NotchRestingIslandSizeKey.self] }
        set { self[NotchRestingIslandSizeKey.self] = newValue }
    }

    var notchPhysicalWidth: CGFloat {
        get { self[NotchPhysicalWidthKey.self] }
        set { self[NotchPhysicalWidthKey.self] = newValue }
    }

    var islandFileDragLocation: CGPoint? {
        get { self[IslandFileDragLocationKey.self] }
        set { self[IslandFileDragLocationKey.self] = newValue }
    }

    var islandCollapseAction: (() -> Void)? {
        get { self[IslandCollapseActionKey.self] }
        set { self[IslandCollapseActionKey.self] = newValue }
    }

    var islandExpandedContentInteraction: IslandExpandedContentInteraction? {
        get { self[IslandExpandedContentInteractionKey.self] }
        set { self[IslandExpandedContentInteractionKey.self] = newValue }
    }
}
