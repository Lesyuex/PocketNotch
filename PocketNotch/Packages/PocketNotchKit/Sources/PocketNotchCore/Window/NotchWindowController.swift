import AppKit
import Combine
import CoreGraphics
import SwiftUI
import PocketNotchShared

/// 管理 NotchWindow 的生命周期与内容托管。
///
/// 重构后的窗口管理只在状态边界变化时调整 frame（展开/收起/屏幕切换），
/// 不再逐帧追踪 SwiftUI 布局变化，消除 GeometryReader ↔ setFrame 的振荡。
@MainActor
public final class NotchWindowController: NSObject, NSWindowDelegate {
    private let window: NotchWindow
    private var lockWindow: NotchWindow?
    private var lockWindowLayout: ResolvedCompactIslandLayout?
    private let lockIslandPresentationModel = LockScreenIslandPresentationModel()
    private let positioner: NotchPositioner
    private let viewModel: NotchViewModel
    private let screenLockController: ScreenLockController
    private let targetDisplayIdentifier: String
    private let makeContent: () -> AnyView
    private let menuBarVisibilityProvider: (NSScreen) -> Bool
    private let hostingView: PassthroughHostingView<AnyView>
    private let hostingContainerView: NSView
    private let contentSizeReporter = NotchContentSizeReporter()
    private let screenChangeDebouncer = Debouncer(interval: 0.3)
    private let externalLayoutDebouncer = Debouncer(interval: 0.08)
    private let sessionResumeDebouncer = Debouncer(interval: 0.18)
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var applicationObservers: [NSObjectProtocol] = []
    private var screenCaptureSettingsCancellable: AnyCancellable?
    private var layoutChangeCancellable: AnyCancellable?
    private var windowKeyingCancellable: AnyCancellable?
    private var screenLockCancellable: AnyCancellable?
    private var sessionSuspendTask: Task<Void, Never>?
    private var lockSpaceReassertTask: Task<Void, Never>?
    private var globalFileDragMonitor: Any?
    private var localFileDragMonitor: Any?
    private var globalMenuBarMouseMonitor: Any?
    private var localMenuBarMouseMonitor: Any?
    private var menuBarVisibilitySamplingTask: Task<Void, Never>?
    private var menuBarVisibilitySamplingDeadline = ContinuousClock.now
    private var isFileDragApproaching = false
    private var fileDragApproachSession = IslandFileDragApproachSession()

    private var screen: NSScreen?
    private var hiddenIslandSize: CGSize
    private var notchPhysicalWidth: CGFloat
    private var contentTopInset: CGFloat
    private var minimumWindowSize: CGSize
    private var isPresented = false
    private var isSessionActive = true
    private var isScreenAwake = true
    private var isLockScreenPresentationActive = false
    private var pendingContentReload: DispatchWorkItem?

    public init<Content: View>(
        screen: NSScreen,
        viewModel: NotchViewModel,
        screenLockController: ScreenLockController,
        menuBarVisibilityProvider: @escaping (NSScreen) -> Bool = { _ in true },
        @ViewBuilder content: @escaping () -> Content
    ) {
        let positioner = NotchPositioner()
        let hiddenIslandSize = positioner.hiddenIslandSize(on: screen)
        let notchPhysicalWidth = positioner.notchWidth(on: screen)
        let contentTopInset = positioner.contentTopInset(on: screen)
        self.positioner = positioner
        self.viewModel = viewModel
        self.screenLockController = screenLockController
        self.targetDisplayIdentifier = screen.pocketnotchDisplayIdentifier
        self.menuBarVisibilityProvider = menuBarVisibilityProvider
        self.screen = screen
        self.hiddenIslandSize = hiddenIslandSize
        self.notchPhysicalWidth = notchPhysicalWidth
        self.contentTopInset = contentTopInset
        self.makeContent = { AnyView(content()) }

        let expandedSize = Self.maximumExpandedSize(
            hiddenIslandSize: hiddenIslandSize,
            notchPhysicalWidth: notchPhysicalWidth,
            screenWidth: screen.frame.width
        )
        // 窗口始终按展开态最大尺寸预留，避免展开/收起时调整窗口大小。
        // SwiftUI 内容在固定画布内贴顶渲染，收起时只有背板缩小，窗口不变。
        let windowSize = expandedSize
        self.minimumWindowSize = expandedSize
        let frame: NSRect
        frame = positioner.frame(on: screen, size: windowSize)
        window = NotchWindow(
            contentRect: frame,
            isHiddenInScreenCapture: viewModel.interactionSettings.isHiddenInScreenCapture
        )
        let hostingView = PassthroughHostingView(
            rootView: Self.hostedRoot(
                AnyView(
                    content()
                        .environment(\.notchContentSizeReporter, contentSizeReporter)
                        .environment(\.notchContentTopInset, contentTopInset)
                        .environment(\.notchHiddenIslandSize, hiddenIslandSize)
                        .environment(\.notchRestingIslandSize, hiddenIslandSize)
                        .environment(\.notchPhysicalWidth, notchPhysicalWidth)
                )
            )
        )
        // 切断 NSHostingView 对窗口的反向尺寸更新，避免 SwiftUI/AppKit 约束递归。
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: windowSize)
        hostingView.autoresizingMask = []
        hostingView.interactiveContentSize = hiddenIslandSize

        let hostingContainerView = PassthroughContainerView(frame: NSRect(origin: .zero, size: windowSize))
        hostingContainerView.autoresizesSubviews = false
        hostingContainerView.addSubview(hostingView)

        self.hostingView = hostingView
        self.hostingContainerView = hostingContainerView
        window.contentView = hostingContainerView
        super.init()
        window.delegate = self

        layoutChangeCancellable = viewModel.layoutChangePublisher
            .sink { [weak self] in self?.handleViewModelLayoutChange() }

        windowKeyingCancellable = viewModel.isExpandedPublisher
            .removeDuplicates()
            .sink { [weak self] isExpanded in
                MainActor.assumeIsolated {
                    self?.updateWindowKeyState(isExpanded: isExpanded)
                }
            }

        contentSizeReporter.onLayoutChange = { [weak self] measurement in
            self?.handleContentLayoutChange(measurement)
        }

        screenCaptureSettingsCancellable = viewModel.interactionSettings.$isHiddenInScreenCapture
            .removeDuplicates()
            .sink { [weak self] isHidden in
                self?.window.setHiddenInScreenCapture(isHidden)
            }

        screenLockCancellable = screenLockController.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                MainActor.assumeIsolated {
                    self?.handleScreenLockPhase(phase)
                }
            }

        observeSystemLayoutChanges()
        observeFileDragApproach()
        observeMenuBarVisibility()
    }

    deinit {
        pendingContentReload?.cancel()
        sessionSuspendTask?.cancel()
        lockSpaceReassertTask?.cancel()
        screenCaptureSettingsCancellable?.cancel()
        layoutChangeCancellable?.cancel()
        windowKeyingCancellable?.cancel()
        screenLockCancellable?.cancel()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        workspaceObservers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        applicationObservers.forEach {
            NotificationCenter.default.removeObserver($0)
        }
        if let globalFileDragMonitor {
            NSEvent.removeMonitor(globalFileDragMonitor)
        }
        if let localFileDragMonitor {
            NSEvent.removeMonitor(localFileDragMonitor)
        }
        if let globalMenuBarMouseMonitor {
            NSEvent.removeMonitor(globalMenuBarMouseMonitor)
        }
        if let localMenuBarMouseMonitor {
            NSEvent.removeMonitor(localMenuBarMouseMonitor)
        }
        menuBarVisibilitySamplingTask?.cancel()
    }

    public func show() {
        isPresented = true
        guard (isSessionActive || isLockScreenPresentationActive), isScreenAwake else { return }
        if isLockScreenPresentationActive {
            presentLockScreenIfPossible()
            return
        }
        refreshWindowPresentation()
        sampleMenuBarVisibilityDuringTransition()
        updateWindowKeyState(isExpanded: viewModel.isExpanded)
    }

    public func hide() {
        isPresented = false
        menuBarVisibilitySamplingTask?.cancel()
        menuBarVisibilitySamplingTask = nil
        window.alphaValue = 0
        window.orderOut(nil)
        if let lockWindow {
            lockWindow.orderOut(nil)
        }
    }

    /// 显示器插拔、锁屏开屏、Space 切换、其他应用退出时恢复顶部锚点。
    private func observeSystemLayoutChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleScreenChange()
                self?.sampleMenuBarVisibilityDuringTransition()
                self?.screenChangeDebouncer.call {
                    MainActor.assumeIsolated {
                        self?.handleScreenChange()
                    }
                }
            }
        }

        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        let workspaceNames: [NSNotification.Name] = [
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ]
        workspaceObservers = workspaceNames.map { name in
            workspaceNotificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    self?.handleWorkspaceNotification(notification.name)
                }
            }
        }

        let applicationNames: [NSNotification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification
        ]
        applicationObservers = applicationNames.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isSessionActive, self.isScreenAwake else { return }
                    self.handleApplicationActivationChange()
                }
            }
        }
    }

    private func observeFileDragApproach() {
        let eventMask: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp
        ]
        globalFileDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) {
            [weak self] event in
            DispatchQueue.main.async {
                self?.handleFileDragEvent(event)
            }
        }
        localFileDragMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) {
            [weak self] event in
            self?.handleFileDragEvent(event)
            return event
        }
    }

    private func observeMenuBarVisibility() {
        globalMenuBarMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) {
            [weak self] _ in
            // 轮询已在跑时（鼠标持续移动的窗口期）不用再调度主队列；
            // 每次事件只重置 deadline，不排队进主循环。
            guard let self, self.menuBarVisibilitySamplingTask == nil else { return }
            DispatchQueue.main.async { [weak self] in
                self?.sampleMenuBarVisibilityDuringTransition()
            }
        }
        localMenuBarMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) {
            [weak self] event in
            self?.sampleMenuBarVisibilityDuringTransition()
            return event
        }
    }

    /// 菜单栏的自动出现/收起没有公开通知。鼠标或 Space 事件发生后短时间采样
    /// App 壳提供的状态栏窗口可见性，跟随真实菜单栏状态而不是鼠标坐标。
    ///
    /// 注意采样体本身昂贵（`CGWindowListCopyWindowInfo` 枚举全屏窗口），
    /// 所以固定 250ms 步进：即使鼠标持续移动不断重置 2s 期限，也最多 4Hz，
    /// 不再逐事件跑满。
    private func sampleMenuBarVisibilityDuringTransition() {
        guard isPresented else { return }
        menuBarVisibilitySamplingDeadline = .now + .seconds(2)
        guard menuBarVisibilitySamplingTask == nil else { return }
        menuBarVisibilitySamplingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard ContinuousClock.now < self.menuBarVisibilitySamplingDeadline else {
                    self.menuBarVisibilitySamplingTask = nil
                    return
                }
                self.syncWindowWithMenuBarVisibility()
                try? await Task.sleep(for: .milliseconds(250))
            }
            self?.menuBarVisibilitySamplingTask = nil
        }
    }

    private func syncWindowWithMenuBarVisibility() {
        guard !isLockScreenPresentationActive,
              isPresented,
              (isSessionActive || isLockScreenPresentationActive),
              isScreenAwake,
              window.isVisible else { return }
        let targetAlpha: CGFloat
        if isLockScreenPresentationActive {
            targetAlpha = 1
        } else {
            targetAlpha = screen.map(menuBarVisibilityProvider) == true ? 1 : 0
        }
        guard window.alphaValue != targetAlpha else { return }
        window.alphaValue = targetAlpha
    }

    private func handleFileDragEvent(_ event: NSEvent) {
        guard isPresented, !isLockScreenPresentationActive else { return }
        guard !viewModel.interactionSettings.isMinimalModeEnabled else {
            updateFileDragApproach(false)
            return
        }
        let dragPasteboard = NSPasteboard(name: .drag)

        switch event.type {
        case .leftMouseDown:
            updateFileDragApproach(false)
            fileDragApproachSession.beginMouseSequence(
                pasteboardChangeCount: dragPasteboard.changeCount
            )
            return
        case .leftMouseUp:
            fileDragApproachSession.endMouseSequence()
            updateFileDragApproach(false)
            return
        case .leftMouseDragged:
            break
        default:
            return
        }

        let hasFileURLs = dragPasteboard.availableType(from: [.fileURL]) != nil
        guard fileDragApproachSession.isCurrentFileDrag(
            pasteboardChangeCount: dragPasteboard.changeCount,
            hasFileURLs: hasFileURLs
        ) else {
            updateFileDragApproach(false)
            return
        }

        if fileDragApproachRect.contains(NSEvent.mouseLocation) {
            updateFileDragApproach(true)
        }
    }

    private var fileDragApproachRect: NSRect {
        guard let screen else { return .zero }
        let width = min(max(hiddenIslandSize.width + 160, 420), minimumWindowSize.width)
        let depth = max(hiddenIslandSize.height + 80, 120)
        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - depth,
            width: width,
            height: depth
        )
    }

    private func updateFileDragApproach(_ isApproaching: Bool) {
        guard isApproaching != isFileDragApproaching else { return }
        isFileDragApproaching = isApproaching
        if isApproaching {
            viewModel.beginDragging()
        } else {
            viewModel.endDragging()
        }
    }

    private func handleContentLayoutChange(_ measurement: NotchContentLayoutMeasurement) {
        // 内容布局变化不再触发逐帧 frame 更新。
        // 展开态始终使用最大预留命中区，避免动态高度动画的中间测量值把标签栏
        // 临时裁出可点击区域；收起态继续跟随实际 compact 画布。
        hostingView.interactiveContentSize = viewModel.isExpanded
            ? minimumWindowSize
            : measurement.interactiveSize
    }

    private func handleScreenChange() {
        let resolvedScreen = resolvedTargetScreen()
        let resolvedHiddenIslandSize = resolvedScreen.map { positioner.hiddenIslandSize(on: $0) }
            ?? NotchPositioner.fallbackHiddenIslandSize
        let resolvedNotchPhysicalWidth = resolvedScreen.map { positioner.notchWidth(on: $0) } ?? 0
        let resolvedContentTopInset = resolvedScreen.map { positioner.contentTopInset(on: $0) } ?? 0
        let shouldReloadContent = !Self.screensEquivalent(resolvedScreen, screen)
            || resolvedHiddenIslandSize != hiddenIslandSize
            || resolvedNotchPhysicalWidth != notchPhysicalWidth
            || resolvedContentTopInset != contentTopInset

        screen = resolvedScreen
        hiddenIslandSize = resolvedHiddenIslandSize
        notchPhysicalWidth = resolvedNotchPhysicalWidth
        contentTopInset = resolvedContentTopInset
        minimumWindowSize = Self.maximumExpandedSize(
            hiddenIslandSize: hiddenIslandSize,
            notchPhysicalWidth: notchPhysicalWidth,
            screenWidth: screen?.frame.width ?? 0
        )

        // 内容重建从激活关键路径移出：先只做必要的 frame 更新，HostingView 根视图
        // 重置于下一轮 RunLoop 延后执行，避免在应用切换瞬间同步重建 SwiftUI 树。
        if shouldReloadContent {
            scheduleContentReload()
        }

        applyFrameNow()
        if isLockScreenPresentationActive {
            presentLockScreenIfPossible()
        }
    }

    /// 把 HostingView 根视图重建延后到下一轮 RunLoop，合并同一次事件批里的多次触发。
    private func scheduleContentReload() {
        pendingContentReload?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hostingView.rootView = Self.hostedRoot(
                    AnyView(
                        self.makeContent()
                            .environment(\.notchContentSizeReporter, self.contentSizeReporter)
                            .environment(\.notchContentTopInset, self.contentTopInset)
                            .environment(\.notchHiddenIslandSize, self.hiddenIslandSize)
                            .environment(\.notchRestingIslandSize, self.hiddenIslandSize)
                            .environment(\.notchPhysicalWidth, self.notchPhysicalWidth)
                    )
                )
            }
        }
        pendingContentReload = item
        DispatchQueue.main.async(execute: item)
    }

    private func restoreWindowPlacement() {
        let targetScreen = resolvedTargetScreen()
        if !Self.screensEquivalent(targetScreen, screen) {
            handleScreenChange()
        } else {
            applyFrameNow()
        }

        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.applyFrameNow()
            }
        }
        externalLayoutDebouncer.call { [weak self] in
            MainActor.assumeIsolated {
                self?.applyFrameNow()
            }
        }
    }

    /// 应用激活/失活是切应用瞬间的最高频事件。关键路径上只同步做必要的 frame 更新，
    /// 完整恢复（屏幕比对 + 可能的 HostingView 重建）延后到下一轮 RunLoop，
    /// 避免 NSScreen 查询与 SwiftUI 树重建在切换瞬间占住主线程。
    private func handleApplicationActivationChange() {
        applyFrameNow()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isSessionActive, self.isScreenAwake else { return }
                self.restoreWindowPlacement()
                self.logWindowChurn("app-active-change")
            }
        }
    }

    private static func screensEquivalent(_ lhs: NSScreen?, _ rhs: NSScreen?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return lhs.pocketnotchDisplayIdentifier == rhs.pocketnotchDisplayIdentifier
            && lhs.frame == rhs.frame
            && lhs.backingScaleFactor == rhs.backingScaleFactor
    }

    /// 在系统事件（应用切换、Space 变化等）后输出窗口布局活动摘要，判断是否发生额外布局。
    private func logWindowChurn(_ label: String) {
        window.logChurnSinceLastReport(label: label)
        if let container = hostingContainerView as? PassthroughContainerView {
            PocketNotchLog.core.debug(
                "\(label, privacy: .public): containerLayouts=\(container.layoutCount, privacy: .public) updates=\(container.updateConstraintsCount, privacy: .public) layoutSubtree=\(container.layoutSubtreeIfNeededCount, privacy: .public)"
            )
            container.resetChurnCounters()
        }
    }

    private func resolvedTargetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.pocketnotchDisplayIdentifier == targetDisplayIdentifier }
    }

    private func handleWorkspaceNotification(_ name: NSNotification.Name) {
        switch name {
        case NSWorkspace.sessionDidResignActiveNotification:
            scheduleSessionSuspendAfterLockGrace()
        case NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification:
            isScreenAwake = false
            suspendForSessionTransition(sessionBecameInactive: false)
        case NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification:
            isScreenAwake = true
            if isLockScreenPresentationActive {
                presentLockScreenIfPossible()
            } else {
                prepareForSessionResume()
                resumeAfterSessionTransitionIfPossible()
            }
        case NSWorkspace.sessionDidBecomeActiveNotification:
            isSessionActive = true
            guard !isLockScreenPresentationActive else { return }
            prepareForSessionResume()
            resumeAfterSessionTransitionIfPossible()
        case NSWorkspace.activeSpaceDidChangeNotification:
            guard (isSessionActive || isLockScreenPresentationActive), isScreenAwake else { return }
            // 窗口始终存在于目标 Space，只把透明度同步到系统菜单栏的真实状态。
            handleScreenChange()
            if isLockScreenPresentationActive {
                presentLockScreenIfPossible()
            } else if shouldPresentWindow {
                window.orderFront(nil)
            }
            sampleMenuBarVisibilityDuringTransition()
            logWindowChurn("activeSpaceDidChange")
        case NSWorkspace.didActivateApplicationNotification:
            guard (isSessionActive || isLockScreenPresentationActive), isScreenAwake else { return }
            sampleMenuBarVisibilityDuringTransition()
            logWindowChurn("didActivateApplication")
        default:
            guard (isSessionActive || isLockScreenPresentationActive), isScreenAwake else { return }
            restoreWindowPlacement()
            logWindowChurn("workspace-\(name.rawValue)")
            refreshWindowPresentation()
        }
    }

    private func handleScreenLockPhase(_ phase: ScreenLockPhase) {
        switch phase {
        case .locked:
            beginLockScreenPresentation()
        case .unlocking:
            beginUnlockScreenPresentation()
        case .unlocked:
            endLockScreenPresentation()
        }
    }

    private func beginLockScreenPresentation() {
        guard !isLockScreenPresentationActive else {
            presentLockScreenIfPossible()
            return
        }
        sessionSuspendTask?.cancel()
        sessionSuspendTask = nil
        sessionResumeDebouncer.cancel()
        isLockScreenPresentationActive = true
        isSessionActive = false
        viewModel.suspendInteraction()
        presentLockScreenIfPossible()
        lockIslandPresentationModel.beginEntrance()
        window.alphaValue = 0
        window.orderOut(nil)
    }

    private func beginUnlockScreenPresentation() {
        guard isLockScreenPresentationActive else { return }
        lockSpaceReassertTask?.cancel()
        lockSpaceReassertTask = nil
        if let lockWindow {
            lockWindow.alphaValue = 1
            lockWindow.displayIfNeeded()
            lockWindow.orderFrontRegardless()
        }
    }

    private func endLockScreenPresentation() {
        guard isLockScreenPresentationActive else { return }
        sessionSuspendTask?.cancel()
        sessionSuspendTask = nil
        lockSpaceReassertTask?.cancel()
        lockSpaceReassertTask = nil
        let shouldHandoffToDesktop = isPresented && isScreenAwake
        if shouldHandoffToDesktop {
            window.alphaValue = 0
            window.orderFrontRegardless()
        }
        isLockScreenPresentationActive = false
        isSessionActive = true
        restoreWindowPlacement()
        sampleMenuBarVisibilityDuringTransition()

        guard shouldHandoffToDesktop else {
            refreshWindowPresentation()
            lockWindow?.orderOut(nil)
            viewModel.resumeInteraction()
            return
        }

        applyFrameNow()
        hostingContainerView.layoutSubtreeIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        // 等一轮 RunLoop，让桌面 SwiftUI 树先提交 `.unlocked` 下的真实灵动态内容，
        // 再原子切换窗口。后续形变由桌面岛自身的 SwiftUI transition 接管，
        // 避免两个不同 Space 的窗口同时改透明度造成闪帧。
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.completeUnlockWindowHandoff()
            }
        }
    }

    private func completeUnlockWindowHandoff() {
        guard !isLockScreenPresentationActive,
              screenLockController.phase == .unlocked,
              shouldPresentWindow else { return }

        hostingContainerView.layoutSubtreeIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let desktopAlpha: CGFloat = screen.map(menuBarVisibilityProvider) == true ? 1 : 0

        // 桌面窗口已在锁屏窗口下方完成布局。先同步显示桌面窗口，再移除锁屏窗口，
        // 整个 RunLoop 内不存在两个窗口都透明的中间帧。
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            window.alphaValue = desktopAlpha
        }
        lockWindow?.orderOut(nil)
        viewModel.resumeInteraction()
    }

    private func presentLockScreenIfPossible() {
        guard isPresented, isScreenAwake else {
            concealWindow()
            return
        }
        guard let screen = resolvedTargetScreen() else { return }
        let lockWindow = makeLockWindowIfNeeded(on: screen)
        let layout = lockIslandLayout(on: screen)
        let frame = positioner.frame(
            on: screen,
            size: CGSize(width: layout.islandWidth, height: layout.islandHeight)
        )
        lockWindow.setFrame(frame, display: false)
        lockWindow.setLockScreenPresentationActive(true)
        lockWindow.alphaValue = 0
        lockWindow.displayIfNeeded()
        let wasDelegated = LockScreenSpaceBridge.shared.delegateWindow(lockWindow)
        lockWindow.orderFrontRegardless()
        lockWindow.alphaValue = 1
        if !wasDelegated {
            _ = LockScreenSpaceBridge.shared.delegateWindow(lockWindow)
        }
        lockSpaceReassertTask?.cancel()
        lockSpaceReassertTask = Task { [weak self] in
            for delay in Self.lockSpaceReassertDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self,
                      self.isLockScreenPresentationActive,
                      self.isScreenAwake else { return }
                guard let lockWindow = self.lockWindow else { return }
                _ = LockScreenSpaceBridge.shared.delegateWindow(lockWindow)
            }
            self?.lockSpaceReassertTask = nil
        }
    }

    private func makeLockWindowIfNeeded(on screen: NSScreen) -> NotchWindow {
        let layout = lockIslandLayout(on: screen)
        if let lockWindow {
            if lockWindowLayout != layout {
                updateLockWindowContent(lockWindow, layout: layout)
            }
            return lockWindow
        }
        let frame = positioner.frame(
            on: screen,
            size: CGSize(width: layout.islandWidth, height: layout.islandHeight)
        )
        let lockWindow = NotchWindow(contentRect: frame)
        updateLockWindowContent(lockWindow, layout: layout)
        self.lockWindow = lockWindow
        return lockWindow
    }

    private func updateLockWindowContent(
        _ lockWindow: NotchWindow,
        layout: ResolvedCompactIslandLayout
    ) {
        let size = CGSize(width: layout.islandWidth, height: layout.islandHeight)
        let hostingView = NSHostingView(
            rootView: LockScreenIslandView(
                screenLockController: screenLockController,
                presentationModel: lockIslandPresentationModel,
                layout: layout
            )
        )
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: size)
        lockWindow.contentView = hostingView
        lockWindowLayout = layout
    }

    private func lockIslandLayout(on screen: NSScreen) -> ResolvedCompactIslandLayout {
        let hiddenSize = positioner.hiddenIslandSize(on: screen)
        return ResolvedCompactIslandLayout.resolve(
            contentHeight: IslandAppearanceConstraints.defaultCompactHeight,
            minimumIslandHeight: hiddenSize.height,
            notchPhysicalWidth: positioner.notchWidth(on: screen)
        )
    }

    /// 会话失活可能先于锁屏通知到达。先留一小段锁屏宽限，避免普通速切用户时
    /// 岛先消失再出现在锁屏上；宽限内没有锁屏事件才按会话切换隐藏。
    private func scheduleSessionSuspendAfterLockGrace() {
        guard !isLockScreenPresentationActive else { return }
        sessionSuspendTask?.cancel()
        sessionSuspendTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, let self else { return }
            guard !self.isLockScreenPresentationActive else {
                self.sessionSuspendTask = nil
                return
            }
            self.sessionSuspendTask = nil
            self.suspendForSessionTransition(sessionBecameInactive: true)
        }
    }

    private func suspendForSessionTransition(sessionBecameInactive: Bool) {
        if sessionBecameInactive {
            isSessionActive = false
        }
        sessionResumeDebouncer.cancel()

        // 休眠或用户会话切换时先移出窗口，再重置 SwiftUI 状态，避免系统重新约束
        // NSPanel 的过程中留下展开态收回或顶部锚点偏移的闪帧。
        window.alphaValue = 0
        window.orderOut(nil)
        if let lockWindow {
            lockWindow.orderOut(nil)
        }
        viewModel.suspendInteraction()
    }

    private func prepareForSessionResume() {
        window.alphaValue = 0
        restoreWindowPlacement()
    }

    private func resumeAfterSessionTransitionIfPossible() {
        guard isSessionActive, isScreenAwake, !isLockScreenPresentationActive else { return }
        sessionResumeDebouncer.call { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      self.isSessionActive,
                      self.isScreenAwake else { return }
                self.restoreWindowPlacement()
                self.refreshWindowPresentation()
                // 窗口已在正确 frame 上可见后才恢复 Hover。updateNSView 会重置旧的
                // publishedIsInside，并用当前 compact 命中区重新采样静止鼠标。
                self.viewModel.resumeInteraction()
            }
        }
    }

    private func presentWindowAtRestoredPlacement(
        forceVisible: Bool = false,
        raiseRegardless: Bool = false
    ) {
        guard shouldPresentWindow else { return }
        window.alphaValue = 0
        restoreWindowPlacement()
        if raiseRegardless {
            window.orderFrontRegardless()
        } else {
            window.orderFront(nil)
        }
        applyFrameNow()
        hostingContainerView.layoutSubtreeIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let menuBarVisible = screen.map(menuBarVisibilityProvider) == true
        window.alphaValue = forceVisible || menuBarVisible ? 1 : 0
    }

    private var shouldPresentWindow: Bool {
        isPresented
            && isScreenAwake
            && (isSessionActive || isLockScreenPresentationActive)
    }

    private func refreshWindowPresentation() {
        if isLockScreenPresentationActive {
            presentLockScreenIfPossible()
            return
        }
        if shouldPresentWindow {
            if !window.isVisible {
                presentWindowAtRestoredPlacement(
                    forceVisible: isLockScreenPresentationActive,
                    raiseRegardless: isLockScreenPresentationActive
                )
            } else {
                syncWindowWithMenuBarVisibility()
            }
        } else {
            concealWindow()
        }
    }

    private func concealWindow() {
        updateFileDragApproach(false)
        window.alphaValue = 0
        window.orderOut(nil)
        if let lockWindow {
            lockWindow.orderOut(nil)
        }
    }

    private static let lockSpaceReassertDelays: [Duration] = [
        .milliseconds(120), .milliseconds(300), .milliseconds(600),
        .milliseconds(1_000), .milliseconds(1_600), .milliseconds(2_200)
    ]

    private func handleViewModelLayoutChange() {
        // 展开状态先于 SwiftUI 的尺寸上报变化，立即开放最大预留命中区。
        hostingView.interactiveContentSize = viewModel.isExpanded
            ? minimumWindowSize
            : hiddenIslandSize
        window.setFileDragPresentationActive(viewModel.state == .dragging)
        applyFrameNow()
    }

    /// 展开态先使面板成为 key：非激活面板中，首次点击会被 AppKit 吞掉用于「激活窗口」，
    /// 导致展开内容（如标签按钮）第一次点击无响应；主动 makeKey 后所有控件直接接收第一击。
    private func updateWindowKeyState(isExpanded: Bool) {
        guard shouldPresentWindow, !isLockScreenPresentationActive else { return }
        if isExpanded, viewModel.state != .dragging {
            window.makeKey()
        } else if !isExpanded {
            window.resignKey()
        }
    }

    /// SwiftUI 内容高度先变化、NSPanel frame 随后才更新。两次布局之间 HostingView
    /// 仍持有旧高度；显式顶对齐可避免根内容按默认中心对齐而让 Island 瞬间下沉/上跳。
    private static func hostedRoot(_ content: AnyView) -> AnyView {
        AnyView(
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        )
    }

    private func applyFrameNow() {
        let resolvedSize = minimumWindowSize
        let frame: NSRect
        if let screen {
            frame = positioner.frame(on: screen, size: resolvedSize)
        } else {
            frame = NSRect(
                x: window.frame.midX - resolvedSize.width / 2,
                y: window.frame.maxY - resolvedSize.height,
                width: resolvedSize.width,
                height: resolvedSize.height
            )
        }

        let backingScaleFactor = screen?.backingScaleFactor ?? window.backingScaleFactor
        if NotchWindowLayout.framesDiffer(
            window.frame,
            frame,
            backingScaleFactor: backingScaleFactor
        ) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                window.setFrame(frame, display: false, animate: false)
            }
        }
        normalizeHostingFrames(to: window.frame.size)
    }

    /// 把两层宿主坐标系归一到零点，避免外部布局变化导致的内部坐标偏移。
    private func normalizeHostingFrames(to size: CGSize) {
        let normalizedRect = NSRect(origin: .zero, size: size)
        guard hostingContainerView.frame != normalizedRect
            || hostingContainerView.bounds != normalizedRect
            || hostingView.frame != normalizedRect
            || hostingView.bounds != normalizedRect else {
            return
        }

        hostingContainerView.frame = normalizedRect
        hostingContainerView.bounds = normalizedRect
        hostingView.frame = normalizedRect
        hostingView.bounds = normalizedRect
    }

    private static func maximumExpandedSize(
        hiddenIslandSize: CGSize,
        notchPhysicalWidth: CGFloat,
        screenWidth: CGFloat
    ) -> CGSize {
        let measuredNotchHeight = notchPhysicalWidth > 0 ? hiddenIslandSize.height : 0
        let maximumRestingHeight = IslandAppearanceConstraints.maximumRestingHeight(
            physicalNotchHeight: measuredNotchHeight
        )
        let restingMetrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: hiddenIslandSize,
            notchPhysicalWidth: notchPhysicalWidth,
            expandedModuleCount: 1,
            showsCompactContent: false,
            preferredRestingHeight: maximumRestingHeight,
            preferredRestingWidth: IslandAppearanceConstraints.defaultCompactBodyWidth(
                physicalNotchWidth: notchPhysicalWidth
            )
        )
        let compactMetrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: hiddenIslandSize,
            notchPhysicalWidth: notchPhysicalWidth,
            expandedModuleCount: 1,
            preferredRestingHeight: maximumRestingHeight,
            preferredCompactOuterInset: IslandAppearanceConstraints.maximumCompactOuterInset,
            preferredCompactVerticalInset: IslandAppearanceConstraints.maximumCompactVerticalInset,
            preferredEarHeight: IslandAppearanceConstraints.maximumEarHeight,
            preferredCompactWidth: IslandAppearanceConstraints.maximumCompactWidth,
            preferredExpandedContentHeight: IslandLayoutToken.maximumExpandedContentHeight
        )
        let expandedSize = IslandBackgroundPath.size(for: .expanded, metrics: compactMetrics)
        let restingSize = IslandBackgroundPath.size(for: .hidden, metrics: restingMetrics)
        let compactSize = IslandBackgroundPath.size(for: .hidden, metrics: compactMetrics)
        let rootExpandedWidth = max(expandedSize.width, max(restingSize.width, compactSize.width))
        let expandedWidthCap = max(screenWidth - PocketNotchTheme.islandHoverOutset * 2, 1)
        return CGSize(
            width: min(rootExpandedWidth, expandedWidthCap) + PocketNotchTheme.islandHoverOutset * 2,
            height: max(expandedSize.height, max(restingSize.height, compactSize.height))
                + PocketNotchTheme.islandHoverOutset
        )
    }

    // MARK: - NSWindowDelegate

    // 不实现 windowDidResize/windowDidMove/windowDidUpdate/windowWillMove，
    // 避免应用激活和设置窗口出现时把正常的系统约束误判为全屏过渡。
}

struct NotchWindowLayout {
    static func pixelAlignedTopCenteredFrame(
        in screenFrame: CGRect,
        size: CGSize,
        backingScaleFactor: CGFloat
    ) -> CGRect {
        let scale = max(backingScaleFactor, 1)
        let centerTwiceInPixels = Int((screenFrame.midX * scale * 2).rounded())
        var widthInPixels = max(Int(ceil(size.width * scale)), 1)

        if (centerTwiceInPixels - widthInPixels) % 2 != 0 {
            widthInPixels += 1
        }

        let topInPixels = Int((screenFrame.maxY * scale).rounded())
        let heightInPixels = max(Int(ceil(size.height * scale)), 1)
        let x = CGFloat(centerTwiceInPixels - widthInPixels) / (2 * scale)
        let y = CGFloat(topInPixels - heightInPixels) / scale

        return CGRect(
            x: x,
            y: y,
            width: CGFloat(widthInPixels) / scale,
            height: CGFloat(heightInPixels) / scale
        )
    }

    static func framesDiffer(
        _ lhs: CGRect,
        _ rhs: CGRect,
        backingScaleFactor: CGFloat
    ) -> Bool {
        let pixelTolerance = 0.25 / max(backingScaleFactor, 1)
        return abs(lhs.midX - rhs.midX) > pixelTolerance
            || abs(lhs.maxY - rhs.maxY) > pixelTolerance
            || abs(lhs.width - rhs.width) > pixelTolerance
            || abs(lhs.height - rhs.height) > pixelTolerance
    }

    static func sizeByReplacingIslandCanvas(
        in totalSize: CGSize,
        currentIslandCanvasSize: CGSize,
        replacementIslandCanvasSize: CGSize
    ) -> CGSize {
        let supplementalHeight = max(totalSize.height - currentIslandCanvasSize.height, 0)
        return CGSize(
            width: max(totalSize.width, replacementIslandCanvasSize.width),
            height: replacementIslandCanvasSize.height + supplementalHeight
        )
    }

    static func maximum(_ measuredSize: CGSize, _ reservedSize: CGSize?) -> CGSize {
        guard let reservedSize else { return measuredSize }
        return CGSize(
            width: max(measuredSize.width, reservedSize.width),
            height: max(measuredSize.height, reservedSize.height)
        )
    }
}

struct IslandFileDragApproachSession {
    private var pasteboardChangeCountAtMouseDown: Int?

    mutating func beginMouseSequence(pasteboardChangeCount: Int) {
        pasteboardChangeCountAtMouseDown = pasteboardChangeCount
    }

    mutating func endMouseSequence() {
        pasteboardChangeCountAtMouseDown = nil
    }

    func isCurrentFileDrag(
        pasteboardChangeCount: Int,
        hasFileURLs: Bool
    ) -> Bool {
        guard let pasteboardChangeCountAtMouseDown else { return false }
        return hasFileURLs && pasteboardChangeCount != pasteboardChangeCountAtMouseDown
    }
}

private final class PassthroughContainerView: NSView {
    private(set) var layoutCount = 0
    private(set) var updateConstraintsCount = 0
    private(set) var layoutSubtreeIfNeededCount = 0

    override func layout() {
        layoutCount += 1
        super.layout()
    }

    override func updateConstraints() {
        updateConstraintsCount += 1
        super.updateConstraints()
    }

    override func layoutSubtreeIfNeeded() {
        layoutSubtreeIfNeededCount += 1
        super.layoutSubtreeIfNeeded()
    }

    func resetChurnCounters() {
        layoutCount = 0
        updateConstraintsCount = 0
        layoutSubtreeIfNeededCount = 0
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }
}

private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    var interactiveContentSize: CGSize = .zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveContentRect.contains(point) else { return nil }
        return super.hitTest(point)
    }

    private var interactiveContentRect: NSRect {
        let width = min(max(interactiveContentSize.width, 0), bounds.width)
        let height = min(max(interactiveContentSize.height, 0), bounds.height)
        // hitTest 交付的 point 使用非翻转坐标系（原点在左下，y 顶部为最大）。
        // 必须按底部原点把命中矩形锚定到视图顶部，覆盖岛屿所在的热区；
        // 否则顶部点击的 point 会落进 `bounds.minY` 计算的错误位置而被拦截。
        let originY = bounds.maxY - height
        return NSRect(
            x: bounds.midX - width / 2,
            y: originY,
            width: width,
            height: height
        )
    }
}
