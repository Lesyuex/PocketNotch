import AppKit
import Combine
import SwiftUI
import PocketNotchShared

/// 根据显示偏好为每块目标屏幕维护一个灵动刘海窗口。
@MainActor
public final class NotchWindowGroupController {
    private let viewModel: NotchViewModel
    private let screenLockController: ScreenLockController
    private let displaySettings: NotchDisplaySettings
    private let makeContent: (NotchViewModel) -> AnyView
    private let menuBarVisibilityProvider: (NSScreen) -> Bool
    private let positioner = NotchPositioner()
    private var controllers: [String: NotchWindowController] = [:]
    private var displaySettingsCancellable: AnyCancellable?
    private var screenObserver: NSObjectProtocol?
    private var isPresented = false

    public init<Content: View>(
        viewModel: NotchViewModel,
        screenLockController: ScreenLockController,
        displaySettings: NotchDisplaySettings,
        menuBarVisibilityProvider: @escaping (NSScreen) -> Bool = { _ in true },
        @ViewBuilder content: @escaping (NotchViewModel) -> Content
    ) {
        self.viewModel = viewModel
        self.screenLockController = screenLockController
        self.displaySettings = displaySettings
        self.menuBarVisibilityProvider = menuBarVisibilityProvider
        self.makeContent = { AnyView(content($0)) }

        displaySettingsCancellable = displaySettings.$mode
            .combineLatest(displaySettings.$selectedDisplayIdentifier)
            .sink { [weak self] _ in
                self?.reconcileControllers()
            }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reconcileControllers()
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    public func show() {
        isPresented = true
        reconcileControllers()
    }

    public func hide() {
        isPresented = false
        reconcileControllers()
    }

    public func refreshDisplaySelection() {
        reconcileControllers()
    }

    private func reconcileControllers() {
        let connectedScreens = NSScreen.screens
        let connectedIdentifiers = Set(connectedScreens.map(\.pocketnotchDisplayIdentifier))
        let targetScreens = resolvedTargetScreens(from: connectedScreens)
        let targetIdentifiers = Set(targetScreens.map(\.pocketnotchDisplayIdentifier))

        let obsoleteIdentifiers = controllers.keys.filter { !connectedIdentifiers.contains($0) }
        for identifier in obsoleteIdentifiers {
            controllers.removeValue(forKey: identifier)?.hide()
            viewModel.removeDisplayViewModel(for: identifier)
        }

        for screen in connectedScreens {
            let identifier = screen.pocketnotchDisplayIdentifier
            guard controllers[identifier] == nil else { continue }
            let displayViewModel = viewModel.displayViewModel(for: identifier)

            let controller = NotchWindowController(
                screen: screen,
                viewModel: displayViewModel,
                screenLockController: screenLockController,
                menuBarVisibilityProvider: menuBarVisibilityProvider
            ) { [makeContent, displayViewModel] in
                makeContent(displayViewModel)
            }
            controllers[identifier] = controller
        }

        for (identifier, controller) in controllers {
            let shouldShow = isPresented && (
                displaySettings.mode == .all
                    || targetIdentifiers.contains(identifier)
            )
            if shouldShow {
                controller.show()
            } else {
                controller.hide()
            }
        }
    }

    private func resolvedTargetScreens(from screens: [NSScreen]) -> [NSScreen] {
        guard !screens.isEmpty else { return [] }

        if displaySettings.mode == .all {
            return screens
        }

        if let identifier = displaySettings.selectedDisplayIdentifier,
           let selectedScreen = screens.first(where: {
               $0.pocketnotchDisplayIdentifier == identifier
           }) {
            return [selectedScreen]
        }

        return [positioner.targetScreen() ?? screens[0]]
    }
}
