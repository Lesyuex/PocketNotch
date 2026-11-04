import AppKit
import CoreGraphics
import PocketNotchShared

/// 无边框、置顶、不抢焦点的刘海面板。
public final class NotchWindow: NSPanel {
    private static let restingLevel = NSWindow.Level.screenSaver
    private static let lockScreenLevel = NSWindow.Level(
        rawValue: Int(CGShieldingWindowLevel())
    )
    private static let fileDragLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.draggingWindow)) - 1
    )

    private var isLockScreenPresentationActive = false
    private var frameSetCount = 0
    private var displayCount = 0
    private var constraintCount = 0

    public init(contentRect: NSRect, isHiddenInScreenCapture: Bool = true) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = Self.restingLevel
        canBecomeVisibleWithoutLogin = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = true
        // 窗口需要存在于其他 App 的全屏 Space，才能在系统菜单栏被唤出时同步出现。
        // 可见性由 NotchWindowController 绑定真实状态栏窗口；窗口本身始终
        // 保持贴顶和已排序，避免 orderOut/Space 迁移造成闪帧。
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
            .fullScreenDisallowsTiling,
            .canJoinAllApplications,
        ]
        // 窗口层后备（layer-backed），让高频旋转/频谱动画全程走 GPU 合成。
        contentView?.wantsLayer = true
        setHiddenInScreenCapture(isHiddenInScreenCapture)
    }

    public func setHiddenInScreenCapture(_ isHidden: Bool) {
        sharingType = isHidden ? .none : .readOnly
    }

    /// 记录自上次调用以来的 setFrame / display / 系统约束次数，判断系统事件是否引发额外布局。
    public func logChurnSinceLastReport(label: String) {
        PocketNotchLog.core.debug(
            "\(label, privacy: .public): setFrames=\(self.frameSetCount, privacy: .public) displays=\(self.displayCount, privacy: .public) systemConstraints=\(self.constraintCount, privacy: .public)"
        )
        frameSetCount = 0
        displayCount = 0
        constraintCount = 0
    }

    public func setFileDragPresentationActive(_ isActive: Bool) {
        guard !isLockScreenPresentationActive else { return }
        level = isActive ? Self.fileDragLevel : Self.restingLevel
    }

    /// 锁屏时把岛升到登录窗口之上；解锁后再落回普通置顶层。
    public func setLockScreenPresentationActive(_ isActive: Bool) {
        guard isActive != isLockScreenPresentationActive else { return }
        isLockScreenPresentationActive = isActive

        if isActive {
            resignKey()
            ignoresMouseEvents = true
            level = Self.lockScreenLevel
        } else {
            ignoresMouseEvents = false
            level = Self.restingLevel
        }
    }

    /// 非激活 Panel 只在 SwiftUI 控件请求输入时成为 key，不会激活 PocketNotch 或成为主窗口。
    public override var canBecomeKey: Bool { !isLockScreenPresentationActive }
    public override var canBecomeMain: Bool { false }

    /// 系统在应用切换、应用退出或 Space 变化后可能重新约束 Panel，并默认按
    /// visibleFrame 避让菜单栏。Island 必须覆盖菜单栏/刘海区域，因此所有系统级
    /// 约束都重新落回目标屏幕的完整 frame 顶部中心，禁止整块窗口突然上移或下沉。
    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let screen else { return frameRect }
        constraintCount += 1
        return NotchWindowLayout.pixelAlignedTopCenteredFrame(
            in: screen.frame,
            size: frameRect.size,
            backingScaleFactor: screen.backingScaleFactor
        )
    }

    public override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        frameSetCount += 1
        super.setFrame(frameRect, display: flag)
    }

    public override func display() {
        displayCount += 1
        super.display()
    }
}
