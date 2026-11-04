import AppKit
import Combine
import PocketNotchCore
import PocketNotchShared
import QuartzCore
import SwiftUI

@MainActor
public final class LockScreenMusicWidgetController {
    private let viewModel: NowPlayingViewModel
    private let settings: MediaMonitoringSettings
    private var window: LockScreenMusicPanel?
    private let presenter = LockScreenMusicWidgetPresenter()
    private let screenLockController: ScreenLockController
    private var lockStateCancellable: AnyCancellable?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var mediaCancellable: AnyCancellable?
    private var spaceReassertTask: Task<Void, Never>?
    private var orderOutTask: Task<Void, Never>?
    private var isStarted = false
    private var isScreenLocked = false
    private var isScreenAwake = true
    private var targetDisplayIdentifier: String?

    init(
        viewModel: NowPlayingViewModel,
        settings: MediaMonitoringSettings,
        screenLockController: ScreenLockController
    ) {
        self.viewModel = viewModel
        self.settings = settings
        self.screenLockController = screenLockController
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        observeLockState()
        observeMediaState()
        updateVisibility()
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false

        lockStateCancellable = nil

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
        workspaceObservers.removeAll()

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }

        mediaCancellable = nil
        spaceReassertTask?.cancel()
        spaceReassertTask = nil
        hide(immediately: true)
    }

    private func observeLockState() {
        lockStateCancellable = screenLockController.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isScreenLocked = phase == .locked
                    if self.isScreenLocked {
                        self.updateVisibility()
                    } else {
                        self.hide(immediately: true)
                    }
                }
            }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
        ]
        workspaceObservers = names.map { name in
            workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    self?.handleWorkspaceNotification(notification.name)
                }
            }
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateVisibility()
            }
        }
    }

    private func observeMediaState() {
        mediaCancellable = Publishers.CombineLatest(
            viewModel.infoPublisher,
            settings.$isLockScreenMusicEnabled
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.updateVisibility()
            }
        }
    }

    private func handleWorkspaceNotification(_ name: NSNotification.Name) {
        switch name {
        case NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification:
            isScreenAwake = false
            hide(immediately: true)
        case NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification:
            isScreenAwake = true
            updateVisibility()
        default:
            break
        }
    }

    private func updateVisibility() {
        PocketNotchLog.media.debug(
            "Lock screen widget visibility: started=\(self.isStarted, privacy: .public) locked=\(self.isScreenLocked, privacy: .public) awake=\(self.isScreenAwake, privacy: .public) enabled=\(self.settings.isLockScreenMusicEnabled, privacy: .public) hasInfo=\(self.viewModel.info != nil, privacy: .public)"
        )
        guard isStarted,
              isScreenLocked,
              isScreenAwake,
              settings.isLockScreenMusicEnabled,
              viewModel.info != nil else {
            hide()
            return
        }
        schedulePresentation()
    }

    private func schedulePresentation() {
        orderOutTask?.cancel()
        orderOutTask = nil

        presentNow()
    }

    private func presentNow() {
        guard isStarted,
              isScreenLocked,
              isScreenAwake,
              settings.isLockScreenMusicEnabled,
              viewModel.info != nil else { return }

        let window = makeWindowIfNeeded()
        guard positionWindow() else {
            hide(immediately: true)
            return
        }

        PocketNotchLog.media.info(
            "Lock screen widget presenting: window=\(window.windowNumber, privacy: .public) visible=\(window.isVisible, privacy: .public)"
        )

        let wasDelegated = LockScreenSpaceBridge.shared.delegateWindow(window)
        window.alphaValue = 1
        window.orderFrontRegardless()
        window.displayIfNeeded()
        presenter.isPresented = true

        viewModel.setLockScreenSpectrumConsumerActive(true)
        if !wasDelegated {
            _ = LockScreenSpaceBridge.shared.delegateWindow(window)
        }
        spaceReassertTask?.cancel()
        spaceReassertTask = Task { [weak self, weak window] in
            for delay in Self.spaceReassertDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, let window,
                      self.isScreenLocked, self.isScreenAwake else { return }
                _ = LockScreenSpaceBridge.shared.delegateWindow(window)
            }
            self?.spaceReassertTask = nil
        }
    }

    private func hide(immediately: Bool = false) {
        spaceReassertTask?.cancel()
        spaceReassertTask = nil
        orderOutTask?.cancel()
        presenter.isPresented = false
        viewModel.setLockScreenSpectrumConsumerActive(false)

        guard let window else { return }
        if immediately {
            hideWindow(window)
            return
        }

        guard window.isVisible else {
            hideWindow(window)
            return
        }

        animateWindowOut(window, immediately: false)

        orderOutTask = Task { [weak self, weak window] in
            // Release the content after the fade; retain the delegated panel.
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled, let window else { return }
            self?.hideWindow(window)
        }
    }

    private func animateWindowOut(_ window: NSWindow, immediately: Bool) {
        guard !immediately,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            window.alphaValue = 0
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.33,
                1.0,
                0.68,
                1.0
            )
            window.animator().alphaValue = 0
        }
    }

    @discardableResult
    private func positionWindow() -> Bool {
        guard let window,
              let screen = targetScreen() else {
            return false
        }
        targetDisplayIdentifier = screen.pocketnotchDisplayIdentifier
        window.setFrame(
            LockScreenMusicWidgetLayout.frame(
                in: screen.frame,
                widgetSize: LockScreenMusicWidgetDesign.size,
                backingScaleFactor: screen.backingScaleFactor
            ),
            display: false
        )
        return true
    }

    private func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        if let targetDisplayIdentifier,
           let existing = screens.first(where: {
               $0.pocketnotchDisplayIdentifier == targetDisplayIdentifier
           }) {
            return existing
        }

        // Prefer the physical notch display, then the current main display,
        // and finally a deterministic built-in/first-screen fallback.
        return NotchPositioner().targetScreen()
            ?? NSScreen.main
            ?? screens.first(where: { $0.isBuiltInDisplay })
            ?? screens[0]
    }

    private func makeWindowIfNeeded() -> LockScreenMusicPanel {
        let size = LockScreenMusicWidgetDesign.size
        let panel = window ?? LockScreenMusicPanel(contentRect: NSRect(origin: .zero, size: size))
        if panel.contentView != nil, window != nil {
            return panel
        }
        // 跟随系统深浅色外观，让 SwiftUI 材质随系统模式切换（浅色/深色）。
        panel.appearance = NSApp.effectiveAppearance

        let hostingView = NSHostingView(
            rootView: NowPlayingLockScreenView(
                viewModel: viewModel,
                presenter: presenter,
                settings: settings
            )
        )
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        // 需要 layer-backed 以保证 SwiftUI 渲染正确。
        hostingView.wantsLayer = true
        panel.contentView = hostingView

        window = panel
        return panel
    }

    private func hideWindow(_ panel: LockScreenMusicPanel) {
        guard window === panel else { return }
        panel.orderOut(nil)
        panel.contentView = nil
        orderOutTask = nil
    }

    private static let spaceReassertDelays: [Duration] = [
        .milliseconds(120), .milliseconds(300), .milliseconds(600),
        .milliseconds(1_000), .milliseconds(1_600), .milliseconds(2_200)
    ]
}

@MainActor
final class LockScreenMusicWidgetPresenter: ObservableObject {
    @Published var isPresented = false
}

enum LockScreenMusicWidgetLayout {
    static func frame(
        in screenFrame: CGRect,
        widgetSize: CGSize,
        backingScaleFactor: CGFloat
    ) -> CGRect {
        let scale = max(backingScaleFactor, 1)
        // Move toward the login avatar from the original 43% placement by
        // half the previous gap. NSScreen coordinates use a bottom origin.
        let preferredCenterY = screenFrame.minY + screenFrame.height * 0.395
        let minimumY = screenFrame.minY + 48
        let maximumY = screenFrame.maxY - widgetSize.height - 120
        let rawY = min(
            max(preferredCenterY - widgetSize.height / 2, minimumY),
            max(maximumY, minimumY)
        )
        let rawX = screenFrame.midX - widgetSize.width / 2

        return CGRect(
            x: (rawX * scale).rounded() / scale,
            y: (rawY * scale).rounded() / scale,
            width: (widgetSize.width * scale).rounded(.up) / scale,
            height: (widgetSize.height * scale).rounded(.up) / scale
        )
    }
}

private final class LockScreenMusicPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        canBecomeVisibleWithoutLogin = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        collectionBehavior = [
            .canJoinAllSpaces, .canJoinAllApplications,
            .stationary, .fullScreenAuxiliary
        ]
        isReleasedWhenClosed = false
        // 参与窗口服务合成，让玻璃能采样窗口背后内容从而显示折射。
        sharingType = .readOnly
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
