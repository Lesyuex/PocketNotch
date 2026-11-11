import AppKit
import Combine
import CoreGraphics
import SwiftUI
import PocketNotchCore
import PocketNotchShared
import MediaModule
import ShelfModule
import SystemStatsModule
import BrightnessModule
import WeatherModule
import StockModule
import ApplicationsModule
import AgentEventModule
import AgentSessionsModule
import RecentFoldersModule
import TodoModule
import ClipboardModule
import TimerModule
import Display

/// App 壳：只做生命周期、依赖注入、模块注册、菜单栏图标。无业务逻辑。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let registry = ModuleRegistry()
    // 开发版每次启动清空 UserDefaults（见 applicationDidFinishLaunching），
    // 因此所有设置对象必须懒加载，确保在清空之后再读取默认值。
    private lazy var notchInteractionSettings = NotchInteractionSettings()
    private lazy var expandedTabSettings = ExpandedTabSettings()
    private lazy var appLanguageSettings = AppLanguageSettings()
    private lazy var appThemeSettings = AppThemeSettings()
    private lazy var menuBarSettings = MenuBarSettings()
    private lazy var appUpdateChecker = AppUpdateChecker()
    private lazy var launchAtLoginSettings = LaunchAtLoginSettings()
    private lazy var notchDisplaySettings = NotchDisplaySettings()
    private lazy var notchViewModel = NotchViewModel(
        interactionSettings: notchInteractionSettings
    )
    private lazy var screenLockController = ScreenLockController()
    private lazy var islandAppearanceSettings = IslandAppearanceSettings()
    private lazy var islandNotificationSettings = IslandNotificationSettings()
    private lazy var mediaMonitoringSettings = MediaMonitoringSettings()
    private lazy var weatherMonitoringSettings = WeatherMonitoringSettings()
    private lazy var stockSettings = StockSettings()
    private lazy var residentSettings = CompactResidentSettings()
    private lazy var agentActivitySettings = AgentActivitySettings()
    private lazy var displaySystem = DisplaySystem()
    private lazy var volumeHUDController = VolumeHUDController(
        notificationSettings: islandNotificationSettings,
        notchViewModel: notchViewModel
    )
    private lazy var displayEventBridge = DisplayEventBridge(displaySystem: displaySystem)
    private lazy var agentActivityController = AgentActivityController(
        settings: agentActivitySettings,
        extraSinks: [displayEventBridge.makeEventSink()]
    )
    private lazy var expandedTabRequest = ExpandedTabRequestController()
    private var windowController: NotchWindowGroupController?
    private var lockScreenMusicWidgetController: LockScreenMusicWidgetController?
    private var settingsWindowController: SettingsWindowController?
    private var launchPermissionCardWindowController: LaunchPermissionCardWindowController?

    private static let setupPanelSeenKey = "app.setupPanelPresented"
    private var statusItem: NSStatusItem?
    private var updateMenuItem: NSMenuItem?
    private var updateRowView: UpdateRowView?
    private var updateCancellable: AnyCancellable?
    private var isExplicitlyQuitting = false
    private var activityFeedCancellable: AnyCancellable?
    private var agentDisplayCancellable: AnyCancellable?
    private var agentEnabledCancellable: AnyCancellable?
    private var languageCancellable: AnyCancellable?
    private var menuBarCancellable: AnyCancellable?
    private var volumeHUDCancellable: AnyCancellable?
    private var settingsObserver: NSObjectProtocol?
    private var displayReadinessObservers: [NSObjectProtocol] = []
    private var displayReadinessFallback: DispatchWorkItem?


    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // 默认保留用户设置；传入 `-reset-state-on-launch` 时回到全新状态，便于反复测试引导。
        if ProcessInfo.processInfo.arguments.contains("-reset-state-on-launch"),
           let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        #endif
        hideDockIcon()
        screenLockController.start()
        registerModules()
        if UserDefaults.standard.bool(forKey: Self.setupPanelSeenKey) {
            agentActivityController.synchronizeEnabledHooksAfterSoftwareUpdateIfNeeded()
        }
        setupStatusItem()
        appUpdateChecker.checkForUpdatesIfNeeded()
        setupNotchWindowWhenDisplayReady()
        setupVolumeHUD()
        observeLanguageChanges()

        observeSettingsOpenRequest()
        startActivityFeeding()
        agentActivityController.bindDisplayEvents(displayEventBridge.awarenessEvents())
        agentActivityController.bindDisplaySessions(displaySystem.sessionStore)
        registry.activateAll()
        displaySystem.start(agentMonitoringEnabled: agentActivitySettings.isEnabled)
        presentLaunchPermissionCardIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isExplicitlyQuitting else {
            return .terminateNow
        }

        if closeSettingsWindowIfNeeded() {
            return .terminateCancel
        }

        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowController?.hide()
        screenLockController.stop()
        lockScreenMusicWidgetController?.stop()
        registry.deactivateAll()
    }

    /// 把既有音乐/天气/股票模块的活动状态喂入 Display 架构的 ActivityStore。
    ///
    /// 设计文档第十七章：Activity 不应被 Agent 修改，三个系统互相不知道具体实现，
    /// 只通过 DisplayScheduler 协调。这里仅做状态搬运，不决定显示。
    private func startActivityFeeding() {
        feedActivities()
        activityFeedCancellable = residentSettings.objectWillChange
            .sink { [weak self] _ in
                self?.feedActivities()
            }
        startAgentDisplayBridging()
        startAgentStateCleanup()
    }

    /// 把「Agent 是否占用灵动岛」桥接到常驻内容仲裁：
    /// 当 Agent 的灵动工作展示在场时，让常驻内容（股票/媒体/天气）让位。
    ///
    /// 直接跟随 `agentPresentationPublisher`（Agent 灵动工作展示是否在场）。运行展示
    /// 由 SessionStore 中是否存在 `.running` 会话决定；完成、失败等反馈仍按自身时长结束。
    /// 展示在场 → 让位；最后一个活动会话结束且瞬时反馈消失 → 常驻恢复。
    /// 该订阅只做只读桥接，不产生任何副作用，也不会反向影响决策、避免死循环。
    private func startAgentDisplayBridging() {
        agentDisplayCancellable = agentActivityController
            .agentPresentationPublisher
            .removeDuplicates()
            .sink { [weak self] present in
                self?.residentSettings.setAgentDisplayActive(present)
            }
    }

    /// Agent 感知关闭时，清空 Display 架构里残留的 Agent 感知状态。
    ///
    /// 关闭监听只是停止接收新事件，Display 的 SessionStore 中仍保留已上报的
    /// Running Session，调度器会因此持续产出 Agent 决策，导致常驻内容
    /// （媒体/股票/天气）一直让位、音乐无法上岛。这里在关闭时主动清空并重算。
    private func startAgentStateCleanup() {
        agentEnabledCancellable = agentActivitySettings.$isEnabled
            .dropFirst()
            .sink { [weak self] isEnabled in
                self?.displaySystem.setAgentMonitoringEnabled(isEnabled)
            }
    }

    private func feedActivities() {
        let now = Date()
        let settings = residentSettings
        displaySystem.activityStore.update(ActivityContent(
            kind: .music,
            isActive: settings.isMediaCompactDisplayActive,
            updatedAt: now
        ))
        displaySystem.activityStore.update(ActivityContent(
            kind: .weather,
            isActive: settings.isWeatherMonitoringEnabled,
            updatedAt: now
        ))
        displaySystem.activityStore.update(ActivityContent(
            kind: .stock,
            isActive: settings.isStockCompactDisplayActive,
            updatedAt: now
        ))
    }

    private func registerModules() {
        registry.register(StockModule(settings: stockSettings, residentSettings: residentSettings))
        let mediaModule = MediaModule(
            monitoringSettings: mediaMonitoringSettings,
            notificationSettings: islandNotificationSettings,
            notchViewModel: notchViewModel,
            residentSettings: residentSettings
        )
        registry.register(mediaModule)
        let widgetController = mediaModule.makeLockScreenMusicWidgetController(
            screenLockController: screenLockController
        )
        widgetController.start()
        lockScreenMusicWidgetController = widgetController
        registry.register(WeatherModule(settings: weatherMonitoringSettings, residentSettings: residentSettings))
        registry.register(ShelfModule())
        registry.register(RecentFoldersModule())
        registry.register(ApplicationsModule())
        registry.register(TodoModule())
        registry.register(ClipboardModule(expandedTabRequest: expandedTabRequest))
        registry.register(TimerModule())
        registry.register(
            SystemStatsModule(
                notificationSettings: islandNotificationSettings,
                notchViewModel: notchViewModel
            )
        )
        registry.register(
            BrightnessModule(
                notificationSettings: islandNotificationSettings,
                notchViewModel: notchViewModel
            )
        )
        // registry.register(AgentActivityModule(controller: agentActivityController))
        // registry.register(AgentSessionsModule())
    }

    /// 冷启动时系统可能尚未完成显示器配置（刘海安全区/辅助区域暂为 0），此时立即建岛
    /// 会先按「无刘海」兜底几何渲染（264），随后才自愈到真实宽度（249）。
    /// 先等显示器就绪再建岛，让首帧几何直接正确；确实没有内置屏/没有刘海时按超时兜底建岛。
    private func setupNotchWindowWhenDisplayReady() {
        guard displayReadinessNeedsWait else {
            setupNotchWindow()
            return
        }

        let names: [Notification.Name] = [
            NSApplication.didChangeScreenParametersNotification,
            NSApplication.didBecomeActiveNotification,
        ]
        displayReadinessObservers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, self.hasReadyNotchDisplay else { return }
                self.clearDisplayReadinessWait()
                self.setupNotchWindow()
            }
        }

        let fallback = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.clearDisplayReadinessWait()
            self.setupNotchWindow()
        }
        displayReadinessFallback = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: fallback)
    }

    private var hasReadyNotchDisplay: Bool {
        NSScreen.screens.contains(where: { $0.hasNotch })
    }

    /// 只有「存在内置屏但暂时读不到刘海」才值得等；无内置屏（Mac mini/纯外接）无需等待。
    private var displayReadinessNeedsWait: Bool {
        let screens = NSScreen.screens
        guard screens.contains(where: { $0.isBuiltInDisplay }) else { return false }
        return !screens.contains(where: { $0.hasNotch })
    }

    private func clearDisplayReadinessWait() {
        for observer in displayReadinessObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        displayReadinessObservers = []
        displayReadinessFallback?.cancel()
        displayReadinessFallback = nil
    }

    private func setupNotchWindow() {
        guard windowController == nil else { return }
        let controller = NotchWindowGroupController(
            viewModel: notchViewModel,
            screenLockController: screenLockController,
            displaySettings: notchDisplaySettings,
            menuBarVisibilityProvider: { [weak self] screen in
                self?.isSystemMenuBarVisible(on: screen) ?? false
            }
        ) { [registry, islandAppearanceSettings, residentSettings, expandedTabSettings, expandedTabRequest, screenLockController, appLanguageSettings] displayViewModel in
            LocaleInjector(languageSettings: appLanguageSettings) {
                IslandRootView(
                    viewModel: displayViewModel,
                    registry: registry,
                    appearanceSettings: islandAppearanceSettings,
                    residentSettings: residentSettings,
                    expandedTabSettings: expandedTabSettings,
                    expandedTabRequest: expandedTabRequest,
                    screenLockController: screenLockController
                )
            }
        }
        controller.show()
        windowController = controller
    }

    /// 展开态的音量胶囊：与灵动岛双耳共用「音量调节」开关，收起时不开监听。
    private func setupVolumeHUD() {
        volumeHUDCancellable = islandNotificationSettings.$isVolumeAdjustmentEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard let self else { return }
                if isEnabled {
                    self.volumeHUDController.start()
                } else {
                    self.volumeHUDController.stop()
                }
            }
    }

    private func setupStatusItem() {
        guard menuBarSettings.showInMenuBar else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            updateMenuItem = nil
            updateRowView = nil
            return
        }

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let icon = NSImage(named: "MenuBarIcon") {
            icon.isTemplate = true
            icon.accessibilityDescription = "Pocket Notch"
            item.button?.image = icon
        }
        let menu = NSMenu()
        let settingsItem = NSMenuItem(
            title: appLanguageSettings.localizedString("menu.settings"),
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: appLanguageSettings.localizedString("menu.settings")
        )
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(
            title: appLanguageSettings.localizedString("menu.update"),
            action: #selector(openUpdatePage),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)
        updateMenuItem = updateItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: appLanguageSettings.localizedString("quit"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        let title = appLanguageSettings.localizedString("menu.update")
        let titleWidth = ceil((title as NSString).size(
            withAttributes: [.font: NSFont.menuFont(ofSize: 0)]
        ).width)
        let rowHeight = standardMenuRowHeight()
        let rowWidth = max(menu.size.width, 14 + titleWidth + 16 + 8 + 12)
        let rowView = UpdateRowView(
            frame: NSRect(x: 0, y: 0, width: rowWidth, height: rowHeight)
        )
        rowView.title = title
        updateItem.view = rowView
        updateRowView = rowView

        menu.delegate = self
        item.menu = menu
        statusItem = item

        updateCancellable = appUpdateChecker.$availableUpdate
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyUpdateState()
            }
        applyUpdateState()
    }

    private func applyUpdateState() {
        updateRowView?.isUpdateAvailable = appUpdateChecker.availableUpdate != nil
    }

    private func standardMenuRowHeight() -> CGFloat {
        let singleItemMenu = NSMenu()
        singleItemMenu.addItem(NSMenuItem(title: "A", action: nil, keyEquivalent: ""))
        let twoItemMenu = NSMenu()
        twoItemMenu.addItem(NSMenuItem(title: "A", action: nil, keyEquivalent: ""))
        twoItemMenu.addItem(NSMenuItem(title: "B", action: nil, keyEquivalent: ""))
        return max(twoItemMenu.size.height - singleItemMenu.size.height, 16)
    }

    @objc private func openUpdatePage() {
        let url = appUpdateChecker.availableUpdate?.releaseURL
            ?? AppUpdateChecker.releasesPageURL
        NSWorkspace.shared.open(url)
        appUpdateChecker.checkForUpdatesIfNeeded(force: true)
    }


    private func observeSettingsOpenRequest() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .openSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showSettings()
        }
    }

    /// AppKit 会在全屏菜单栏隐藏后继续把状态项窗口报告为可见，并保留旧 frame。
    /// 通过 windowNumber 查询 WindowServer 的实际合成状态，才能区分隐藏菜单栏留下的
    /// 顶部触发条和已经真正滑入屏幕的菜单栏。
    private func isSystemMenuBarVisible(on screen: NSScreen) -> Bool {
        guard let screenNumber = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
              ] as? NSNumber,
              let windowInfo = CGWindowListCopyWindowInfo(
                [.optionAll, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]] else { return false }

        let displayBounds = CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
        guard let compositedFrame = systemMenuBarCompositedFrame(
            displayBounds: displayBounds,
            windowInfo: windowInfo
        ) else {
            return false
        }

        let visibleHeight = compositedFrame.intersection(displayBounds).height
        return visibleHeight / compositedFrame.height >= 0.9
    }

    private func systemMenuBarCompositedFrame(
        displayBounds: CGRect,
        windowInfo: [[String: Any]]
    ) -> CGRect? {
        let menuBarLayer = Int(CGWindowLevelForKey(.mainMenuWindow))

        return windowInfo.compactMap { info -> CGRect? in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue
                    == menuBarLayer,
                  (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0) > 0,
                  let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(
                    dictionaryRepresentation: boundsDictionary as CFDictionary
                  ),
                  frame.height > 0,
                  frame.height <= 80,
                  frame.intersection(displayBounds).width / displayBounds.width >= 0.9
            else { return nil }
            return frame
        }.min { lhs, rhs in
            abs(lhs.width - displayBounds.width) < abs(rhs.width - displayBounds.width)
        }
    }

    private func observeLanguageChanges() {
        languageCancellable = appLanguageSettings.$selectedLanguage
            .dropFirst()
            .sink { [weak self] _ in
                self?.setupStatusItem()
            }

        menuBarCancellable = menuBarSettings.$showInMenuBar
            .dropFirst()
            .sink { [weak self] show in
                self?.statusItem?.button?.isHidden = !show
            }
    }

    @objc func showSettings() {
        showDockIcon()
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                languageSettings: appLanguageSettings,
                themeSettings: appThemeSettings,
menuBarSettings: menuBarSettings,
                launchAtLoginSettings: launchAtLoginSettings,
                appearanceSettings: islandAppearanceSettings,
                interactionSettings: notchInteractionSettings,
                expandedTabSettings: expandedTabSettings,
                displaySettings: notchDisplaySettings,
                notificationSettings: islandNotificationSettings,
                monitoringSettings: mediaMonitoringSettings,
                weatherSettings: weatherMonitoringSettings,
                stockSettings: stockSettings,
                residentSettings: residentSettings,
                registry: registry,
                agentController: agentActivityController,
                onDisplaySelectionChange: { [weak self] in
                    self?.windowController?.refreshDisplaySelection()
                },
                onClose: { [weak self] in
                    self?.settingsWindowDidClose()
                }
            )
        }
        settingsWindowController?.present()
    }

    @objc private func quit() {
        isExplicitlyQuitting = true
        NSApp.terminate(nil)
    }

    /// 启动时弹出引导卡片（灵动功能选择）。
    /// 首次启动时展示；卡片完成即进入 App。
    /// 权限不再在启动时校验/申请，改为在岛上真正用到对应功能时才按需申请。
    private func presentLaunchPermissionCardIfNeeded() {
        guard launchPermissionCardWindowController == nil else { return }
        #if DEBUG
        // 开发期每次启动都弹，便于反复测试引导流程。
        let shouldPresent = true
        #else
        let shouldPresent = !UserDefaults.standard.bool(forKey: Self.setupPanelSeenKey)
        #endif
        guard shouldPresent else { return }

        let featureCoordinator = makePermissionCoordinator(resetsAgentHooks: true)
        let controller = LaunchPermissionCardWindowController(
            featureCoordinator: featureCoordinator,
            onFinish: { [weak self] in
                self?.launchPermissionCardDidClose()
            },
            onQuit: { [weak self] in
                self?.quit()
            }
        )
        launchPermissionCardWindowController = controller
        controller.present()
    }

    private func launchPermissionCardDidClose() {
        guard launchPermissionCardWindowController != nil else { return }
        launchPermissionCardWindowController = nil
        UserDefaults.standard.set(true, forKey: Self.setupPanelSeenKey)
        hideDockIcon()
    }

    private func makePermissionCoordinator(resetsAgentHooks: Bool = false) -> PermissionCoordinator {
        PermissionCoordinator(
            mediaSettings: mediaMonitoringSettings,
            weatherSettings: weatherMonitoringSettings,
            stockSettings: stockSettings,
            agentController: agentActivityController,
            resetsAgentHooks: resetsAgentHooks
        )
    }

    private func hideDockIcon() {
        NSApp.setActivationPolicy(.accessory)
    }

    private func showDockIcon() {
        NSApp.setActivationPolicy(.regular)
    }

    private func settingsWindowDidClose() {
        guard !isExplicitlyQuitting else {
            return
        }

        settingsWindowController = nil
        hideDockIcon()
    }

    private func closeSettingsWindowIfNeeded() -> Bool {
        guard let settingsWindow = settingsWindowController?.window,
              settingsWindow.isVisible || settingsWindow.isMiniaturized else {
            return false
        }

        settingsWindow.close()
        return true
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        updateRowView?.isHighlighted = false
        appUpdateChecker.checkForUpdatesIfNeeded(force: true)
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        updateRowView?.isHighlighted = item === updateMenuItem
    }
}

private final class UpdateRowView: NSView {
    var title: String = "" {
        didSet { titleLabel.stringValue = title }
    }

    var isUpdateAvailable = false {
        didSet { dotView.isHidden = !isUpdateAvailable }
    }

    var isHighlighted = false {
        didSet {
            titleLabel.textColor = isHighlighted ? .selectedMenuItemTextColor : .labelColor
        }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let dotView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleLabel.font = NSFont.menuFont(ofSize: 0)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        dotView.wantsLayer = true
        dotView.layer?.backgroundColor = NSColor.systemRed.cgColor
        dotView.layer?.cornerRadius = 4
        dotView.isHidden = true
        dotView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dotView)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 8),
            dotView.heightAnchor.constraint(equalToConstant: 8),
            dotView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        dotView.layer?.backgroundColor = NSColor.systemRed.cgColor
    }
}
