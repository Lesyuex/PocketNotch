import AppKit
import SwiftUI

/// 启动引导的 Liquid Glass 卡片弹窗：灵动功能选择。
@MainActor
final class LaunchPermissionCardWindowController: NSWindowController, NSWindowDelegate {
    private enum Layout {
        static let width: CGFloat = 335
        static let height: CGFloat = 500
    }

    private let onFinish: () -> Void
    private let onQuit: () -> Void
    private var didFinish = false

    init(
        featureCoordinator: PermissionCoordinator,
        onFinish: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onFinish = onFinish
        self.onQuit = onQuit
        let window = PermissionCardWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Layout.width,
                height: Layout.height
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        let rootView = LaunchPermissionCardView(
            featureCoordinator: featureCoordinator,
            onFinish: { [weak self] in
                self?.finish()
            },
            onQuit: { [weak self] in
                self?.quit()
            }
        )
        let hostingController = NSHostingController(rootView: rootView)
        window.contentViewController = hostingController
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: Layout.width, height: Layout.height))
        window.isReleasedWhenClosed = false
        window.animationBehavior = .documentWindow
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.orderFrontRegardless()
        window.makeKey()
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        window?.close()
        onFinish()
    }

    func quit() {
        onQuit()
    }

    func windowWillClose(_ notification: Notification) {
        guard !didFinish else { return }
        didFinish = true
        onFinish()
    }
}

/// 无边框窗口需覆盖 canBecomeKey / canBecomeMain 才能正常获取键盘焦点。
private final class PermissionCardWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}