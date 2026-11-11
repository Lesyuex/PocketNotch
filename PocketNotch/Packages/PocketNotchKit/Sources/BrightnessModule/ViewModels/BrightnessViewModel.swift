import Combine
import Foundation
import PocketNotchCore
import PocketNotchShared
import Observation

enum CompactBrightnessPresentationIdentity: Equatable {
    case none
    case brightness(UUID)
}

@Observable
@MainActor
public final class BrightnessViewModel {
    /// 展示时长与音量调节保持一致：约 1.3 秒后自动收起。
    nonisolated static let defaultDisplayDuration: Duration = .seconds(3)

    var brightnessPresentation: BrightnessSnapshot?

    var compactPresentationIdentity: CompactBrightnessPresentationIdentity {
        guard let brightnessPresentation else { return .none }
        return .brightness(brightnessPresentation.id)
    }

    private let brightnessService: any BrightnessProviding
    private var keyInterceptor: (any BrightnessKeyIntercepting)?
    let notificationSettings: IslandNotificationSettings
    private let notchViewModel: NotchViewModel?
    private let displayDuration: Duration
    private var presentationDismissTask: Task<Void, Never>?
    private var notificationSettingsCancellables = Set<AnyCancellable>()
    private var expansionStateCancellable: AnyCancellable?
    private var isActive = false

    private var areNotificationsSuppressed: Bool {
        notchViewModel?.isExpanded == true
    }

    public convenience init(
        notificationSettings: IslandNotificationSettings? = nil,
        notchViewModel: NotchViewModel? = nil
    ) {
        self.init(
            brightnessService: SystemDisplayBrightnessService(),
            notificationSettings: notificationSettings ?? IslandNotificationSettings(defaults: nil),
            notchViewModel: notchViewModel
        )
    }

    init(
        brightnessService: any BrightnessProviding = SystemDisplayBrightnessService(),
        notificationSettings: IslandNotificationSettings? = nil,
        notchViewModel: NotchViewModel? = nil,
        keyInterceptor: (any BrightnessKeyIntercepting)? = nil,
        displayDuration: Duration = BrightnessViewModel.defaultDisplayDuration
    ) {
        self.brightnessService = brightnessService
        self.notificationSettings = notificationSettings ?? IslandNotificationSettings(defaults: nil)
        self.notchViewModel = notchViewModel
        self.displayDuration = displayDuration
        if let keyInterceptor {
            self.keyInterceptor = keyInterceptor
        } else {
            // 必须显式标注 onPerformed：初始化器有多个函数类型参数，未标注的尾随闭包
            // 会按向后匹配规则绑到最后一个（accessibilityPrompt），导致上岛回调拿到空闭包。
            self.keyInterceptor = BrightnessKeyInterceptorService(
                brightnessController: brightnessService,
                onPerformed: { [weak self] in
                    self?.handleBrightnessAdjustment()
                }
            )
        }
        observeNotificationSettings(self.notificationSettings)
        observeExpansionState()
    }

    func activate() {
        isActive = true
        PocketNotchLog.system.info(
            "Brightness module activating: brightnessAdjustmentEnabled=\(self.notificationSettings.isBrightnessAdjustmentEnabled, privacy: .public), islandExpanded=\(self.notchViewModel?.isExpanded == true, privacy: .public)"
        )
        reconcileKeyInterception()
    }

    func deactivate() {
        isActive = false
        keyInterceptor?.stop()
        clearBrightnessPresentation()
    }

    /// 只有「隐藏系统亮度提示」且亮度提醒都开启时才接管亮度键；任一关闭后按键交回
    /// macOS，原生 OSD 照常出现。PocketNotch 自己的提醒不依赖接管，因此不受这个开关影响。
    /// sink 入参是刚写入的新值——`@Published` 在 willSet 阶段发值，直接读属性会拿到旧值。
    private func reconcileKeyInterception(
        isSystemBrightnessHUDHidden: Bool? = nil,
        isBrightnessAdjustmentEnabled: Bool? = nil
    ) {
        let hideSystemHUD = isSystemBrightnessHUDHidden ?? notificationSettings.isSystemBrightnessHUDHidden
        let adjustmentEnabled = isBrightnessAdjustmentEnabled ?? notificationSettings.isBrightnessAdjustmentEnabled
        guard isActive, hideSystemHUD, adjustmentEnabled else {
            keyInterceptor?.stop()
            return
        }
        keyInterceptor?.start()
    }

    /// 亮度键事件处理入口：读取当前亮度并短暂展示在岛内。
    func handleBrightnessAdjustment() {
        guard notificationSettings.isBrightnessAdjustmentEnabled, !areNotificationsSuppressed else {
            PocketNotchLog.system.info(
                "Brightness adjustment suppressed: enabled=\(self.notificationSettings.isBrightnessAdjustmentEnabled, privacy: .public), islandExpanded=\(self.areNotificationsSuppressed, privacy: .public)"
            )
            clearBrightnessPresentation()
            return
        }
        guard let brightness = brightnessService.currentBrightness() else {
            PocketNotchLog.system.warning("Brightness adjustment: currentBrightness() unavailable")
            return
        }
        PocketNotchLog.system.info(
            "Brightness adjustment presented in island: brightness=\(brightness, privacy: .public)"
        )
        brightnessPresentation = BrightnessSnapshot(brightness: brightness)
        presentationDismissTask?.cancel()
        presentationDismissTask = Task { [weak self, displayDuration] in
            do {
                try await Task.sleep(for: displayDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.brightnessPresentation = nil
            self?.presentationDismissTask = nil
        }
    }

    private func observeExpansionState() {
        expansionStateCancellable = notchViewModel?.isExpandedPublisher
            .removeDuplicates()
            .sink { [weak self] isExpanded in
                if isExpanded { self?.clearBrightnessPresentation() }
            }
    }

    private func observeNotificationSettings(_ settings: IslandNotificationSettings) {
        settings.$isSystemBrightnessHUDHidden
            .removeDuplicates()
            .sink { [weak self] isHidden in
                self?.reconcileKeyInterception(isSystemBrightnessHUDHidden: isHidden)
            }
            .store(in: &notificationSettingsCancellables)

        settings.$isBrightnessAdjustmentEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                self.reconcileKeyInterception(isBrightnessAdjustmentEnabled: enabled)
                if !enabled { self.clearBrightnessPresentation() }
            }
            .store(in: &notificationSettingsCancellables)
    }

    private func clearBrightnessPresentation() {
        presentationDismissTask?.cancel()
        presentationDismissTask = nil
        brightnessPresentation = nil
    }
}