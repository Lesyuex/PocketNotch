import AgentEventModule
import AppKit
import Combine
import Foundation
import PocketNotchCore
import MediaModule
import StockModule
import SwiftUI
import WeatherModule

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private enum Layout {
        static let width: CGFloat = 704
        static let fixedHeight: CGFloat = 666
    }

    init(
        languageSettings: AppLanguageSettings,
        themeSettings: AppThemeSettings,
        menuBarSettings: MenuBarSettings,
        launchAtLoginSettings: LaunchAtLoginSettings,
        appearanceSettings: IslandAppearanceSettings,
        interactionSettings: NotchInteractionSettings,
        expandedTabSettings: ExpandedTabSettings,
        displaySettings: NotchDisplaySettings,
        notificationSettings: IslandNotificationSettings,
        monitoringSettings: MediaMonitoringSettings,
        weatherSettings: WeatherMonitoringSettings,
        stockSettings: StockSettings,
        residentSettings: CompactResidentSettings,
        registry: ModuleRegistry,
        agentController: AgentActivityController,
        onDisplaySelectionChange: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        let wallpaperPreview = SettingsWallpaperPreviewModel()
        let rootView = SettingsRootView(
            languageSettings: languageSettings,
            themeSettings: themeSettings,
            menuBarSettings: menuBarSettings,
            launchAtLoginSettings: launchAtLoginSettings,
            appearanceSettings: appearanceSettings,
            interactionSettings: interactionSettings,
            expandedTabSettings: expandedTabSettings,
            displaySettings: displaySettings,
            notificationSettings: notificationSettings,
            monitoringSettings: monitoringSettings,
            weatherSettings: weatherSettings,
            stockSettings: stockSettings,
            residentSettings: residentSettings,
            registry: registry,
            wallpaperPreview: wallpaperPreview,
            agentController: agentController,
            onDisplaySelectionChange: onDisplaySelectionChange
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = ""
        window.titleVisibility = .hidden
        window.styleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
            .fullSizeContentView,
        ]
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        let initialScreen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NotchPositioner().targetScreen() ?? NSScreen.main
        window.setFrame(Self.defaultWindowFrame(for: initialScreen), display: false)
        window.contentMinSize = NSSize(width: Layout.width, height: Layout.fixedHeight)
        window.contentMaxSize = NSSize(width: Layout.width, height: Layout.fixedHeight)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        self.wallpaperPreview = wallpaperPreview
        self.onClose = onClose
        self.themeSettings = themeSettings
        super.init(window: window)
        observeThemeChanges(themeSettings, window: window)
        applyTheme(themeSettings.theme, window: window)
        window.delegate = self
    }

    private var themeSettings: AppThemeSettings?
    private var themeCancellable: AnyCancellable?
    private var systemThemeCancellable: AnyCancellable?

    /// 设置窗口外观统一按 themeSettings.resolvedColorScheme 解析成具体深浅，
    /// 避免依赖被强制外观污染的 effectiveAppearance 或 nil 跟随在 macOS 上的不稳定行为。
    private func applyTheme(_ theme: AppTheme, window: NSWindow?) {
        guard let window, let themeSettings else { return }
        themeSettings.refreshSystemColorScheme()
        let appearanceName: NSAppearance.Name = themeSettings.resolvedColorScheme == .dark
            ? .darkAqua
            : .aqua
        window.appearance = NSAppearance(named: appearanceName)
        window.backgroundColor = .clear

        if theme == .system {
            if systemThemeCancellable == nil {
                systemThemeCancellable = DistributedNotificationCenter.default()
                    .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
                    .sink { [weak self] _ in
                        self?.applyTheme(self?.themeSettings?.theme ?? .system, window: self?.window)
                    }
            }
        } else {
            systemThemeCancellable = nil
        }
    }

    private func observeThemeChanges(_ themeSettings: AppThemeSettings, window: NSWindow) {
        themeCancellable = themeSettings.$theme
            .removeDuplicates()
            .sink { [weak self] theme in
                self?.applyTheme(theme, window: window)
            }
    }

    private let wallpaperPreview: SettingsWallpaperPreviewModel
    private let onClose: () -> Void

    /// 标记嵌套的 NSVisualEffectView 待重绘并触发窗口刷新，促使材质重新采样
    /// behindWindow 背景，缓解重新成为 key 时的露白闪帧。
    private func refreshVisualEffectViews(in view: NSView?) {
        guard let view else { return }
        if view is NSVisualEffectView {
            view.needsDisplay = true
        }
        for subview in view.subviews {
            refreshVisualEffectViews(in: subview)
        }
        DispatchQueue.main.async { [weak window] in
            window?.displayIfNeeded()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard let window else { return }
        let screen = presentationScreen()
        NSApp.activate(ignoringOtherApps: true)
        window.setFrame(Self.defaultWindowFrame(for: screen), display: true)
        window.orderFrontRegardless()
        window.makeKey()
        wallpaperPreview.captureWallpaper(for: screen)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // aheadWindow 材质在窗口重新成为 key（台前调度/切 Space 回来）时会重新采样，
        // 强制其重绘，尽量抹掉那一下透空露白。
        refreshVisualEffectViews(in: window?.contentView)
    }

    func windowDidResignKey(_ notification: Notification) {}

    func windowWillClose(_ notification: Notification) {
        wallpaperPreview.reset()
        window?.contentViewController = nil
        PetPreviewView.releaseCachedResources()
        onClose()
    }

    func windowDidMiniaturize(_ notification: Notification) {}

    private static func defaultWindowFrame(for screen: NSScreen?) -> NSRect {
        guard let visibleFrame = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            return NSRect(
                x: 0,
                y: 0,
                width: Layout.width,
                height: Layout.fixedHeight
            )
        }

        let width = Layout.width
        let height = Layout.fixedHeight
        let x = width >= visibleFrame.width
            ? visibleFrame.minX
            : min(
                max(visibleFrame.midX - width / 2, visibleFrame.minX),
                visibleFrame.maxX - width
            )
        let y = height >= visibleFrame.height
            ? visibleFrame.minY
            : max(visibleFrame.midY - height / 2, visibleFrame.minY)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// 解析设置窗口本次打开时应归属的屏幕。
    /// LSUIElement 菜单栏应用下 NSScreen.main 不可靠，优先取鼠标所在屏幕，
    /// 再退回到刘海所在屏幕，保证预览壁纸与窗口实际落屏一致。
    private func presentationScreen() -> NSScreen? {
        let cursorPoint = NSEvent.mouseLocation
        if let screenUnderCursor = NSScreen.screens.first(where: {
            $0.frame.contains(cursorPoint)
        }) {
            return screenUnderCursor
        }
        return NotchPositioner().targetScreen() ?? NSScreen.main
    }
}
