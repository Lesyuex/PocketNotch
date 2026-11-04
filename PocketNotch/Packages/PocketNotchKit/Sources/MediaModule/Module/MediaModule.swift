import Combine
import SwiftUI
import PocketNotchCore

public struct MediaModule: PocketNotchModule {
    public let id = "media"
    public let title: LocalizedStringKey = "module.media.title"
    public let priority = 10

    @MainActor private let viewModel: NowPlayingViewModel
    @MainActor private let monitoringSettings: MediaMonitoringSettings
    @MainActor private let notificationSettings: IslandNotificationSettings
    @MainActor private let residentSettings: CompactResidentSettings
    @MainActor private let compactDisplayObserver: AnyCancellable
    @MainActor private let initialStateObserver: AnyCancellable

    @MainActor
    public init() {
        let monitoringSettings = MediaMonitoringSettings()
        let notificationSettings = IslandNotificationSettings()
        self.monitoringSettings = monitoringSettings
        self.notificationSettings = notificationSettings
        self.residentSettings = CompactResidentSettings()
        viewModel = NowPlayingViewModel(
            monitoringSettings: monitoringSettings,
            notificationSettings: notificationSettings
        )
        compactDisplayObserver = viewModel.compactMediaDisplayActivePublisher
            .removeDuplicates()
            .sink { [weak residentSettings] isActive in
                residentSettings?.setMediaCompactDisplayActive(isActive)
            }
        initialStateObserver = Publishers.CombineLatest(
            monitoringSettings.$isRealtimeMusicMonitoringEnabled.removeDuplicates(),
            viewModel.initialStateResolvedPublisher.removeDuplicates()
        )
        .sink { [weak residentSettings] isMonitoringEnabled, isInitialStateResolved in
            residentSettings?.setMediaInitialStateResolving(
                isMonitoringEnabled && !isInitialStateResolved
            )
        }
    }

    @MainActor
    public init(
        monitoringSettings: MediaMonitoringSettings,
        notificationSettings: IslandNotificationSettings,
        notchViewModel: NotchViewModel? = nil,
        residentSettings: CompactResidentSettings
    ) {
        self.monitoringSettings = monitoringSettings
        self.notificationSettings = notificationSettings
        self.residentSettings = residentSettings
        viewModel = NowPlayingViewModel(
            monitoringSettings: monitoringSettings,
            notificationSettings: notificationSettings,
            notchViewModel: notchViewModel
        )
        compactDisplayObserver = viewModel.compactMediaDisplayActivePublisher
            .removeDuplicates()
            .sink { [weak residentSettings] isActive in
                residentSettings?.setMediaCompactDisplayActive(isActive)
            }
        initialStateObserver = Publishers.CombineLatest(
            monitoringSettings.$isRealtimeMusicMonitoringEnabled.removeDuplicates(),
            viewModel.initialStateResolvedPublisher.removeDuplicates()
        )
        .sink { [weak residentSettings] isMonitoringEnabled, isInitialStateResolved in
            residentSettings?.setMediaInitialStateResolving(
                isMonitoringEnabled && !isInitialStateResolved
            )
        }
    }

    @MainActor public var isCompactModuleEnabled: Bool { residentSettings.activeModule == .media }

    public func minimalView() -> AnyView {
        AnyView(NowPlayingMinimalView(viewModel: viewModel))
    }

    public func hiddenLeadingView() -> AnyView {
        AnyView(
            NowPlayingHiddenLeadingView(
                viewModel: viewModel,
                settings: monitoringSettings,
                role: .resident
            )
        )
    }

    public func hiddenTrailingView() -> AnyView {
        AnyView(
            NowPlayingHiddenTrailingView(
                viewModel: viewModel,
                settings: notificationSettings,
                role: .resident
            )
        )
    }

    public var showsInCompactSettingsPreview: Bool { true }

    public var isCompactSettingsPreviewEnabled: Bool {
        monitoringSettings.isRealtimeMusicMonitoringEnabled
    }

    public func compactSettingsPreviewLeadingView() -> AnyView {
        AnyView(MediaCompactSettingsPreviewLeadingView(settings: monitoringSettings))
    }

    public func compactSettingsPreviewTrailingView() -> AnyView {
        AnyView(MediaCompactSettingsPreviewTrailingView(settings: monitoringSettings))
    }

    public func compactNotificationLeadingView() -> AnyView {
        AnyView(
            NowPlayingHiddenLeadingView(
                viewModel: viewModel,
                settings: monitoringSettings,
                role: .notification
            )
        )
    }

    public func compactNotificationTrailingView() -> AnyView {
        AnyView(
            NowPlayingHiddenTrailingView(
                viewModel: viewModel,
                settings: notificationSettings,
                role: .notification
            )
        )
    }

    /// 临时优先级：切歌与岛下音频输出通知不抢占 compact，音量/耳机连接为 20
    /// （高于 Agent 运行=10，低于失败/等待授权）。
    @MainActor public func transientVisualPriority() -> Int? {
        viewModel.hasCompactTransientPresentation ? 20 : nil
    }

    public func notificationView() -> AnyView {
        AnyView(
            MediaNotificationHostView(
                viewModel: viewModel,
                notificationSettings: notificationSettings
            )
        )
    }

    public var showsInExpandedPage: Bool { true }

    public var expandedPageWeight: CGFloat { 6.7 }

    /// 展开态背板锁定纯黑（与紧凑态同源），不再渲染封面取色氛围光。
    public func expandedBackgroundView() -> AnyView {
        AnyView(Color.clear)
    }

    public func expandedView() -> AnyView {
        AnyView(NowPlayingExpandedView(viewModel: viewModel))
    }

    /// 「此刻」页媒体卡：封面 + 信息 + 进度 + 控制。
    @MainActor
    public func nowPageLeadingAccessoryView() -> AnyView? {
        AnyView(NowPlayingNowPageAccessoryView(viewModel: viewModel))
    }

    /// 「此刻」页封面卡（音乐卡片 2）：左侧音乐卡与待办之间的独立封面，
    /// 复用左侧封面样式等比例放大到同高。
    @MainActor
    public func nowPageMidAccessoryView() -> AnyView? {
        nil
    }

    /// 封面几何接力：compact 耳内封面 ⇆ 「此刻」页媒体卡封面。
    /// 展开时耳内封面起飞落位到媒体卡，收起时沿原路飞回。
    @MainActor
    public var contentHandoffDescriptor: IslandContentHandoffDescriptor? {
        IslandContentHandoffDescriptor(
            id: id,
            isEligible: { [viewModel] in
                viewModel.isCompactMediaDisplayActive && viewModel.isMediaArtworkReady
            },
            sourceCornerRadius: { [viewModel, monitoringSettings] artworkSize in
                guard !viewModel.isUsingAppIconFallback else { return 0 }
                let percentage = monitoringSettings.isCompactArtworkRotationEnabled
                    ? monitoringSettings.compactRotatingArtworkCornerRadiusPercentage
                    : monitoringSettings.compactStaticArtworkCornerRadiusPercentage
                return artworkSize * 0.5 * min(max(percentage / 100, 0), 1)
            },
            destinationCornerRadius: LeftCoverCardDesign.coverCornerRadius,
            destinationContent: { [viewModel] size, cornerRadius in
                AnyView(
                    ArtworkView(
                        data: viewModel.displayArtwork,
                        fallbackSystemName: "music.note",
                        size: size.width,
                        height: size.height,
                        cornerRadius: cornerRadius
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                )
            }
        )
    }

    public var supportsMinimalExpandedView: Bool { true }

    public var expandedMinimalContentAspectRatio: CGFloat? {
        LockScreenMusicWidgetDesign.aspectRatio
    }

    public var expandedMinimalContentInternalTopInset: CGFloat {
        LockScreenMusicWidgetDesign.verticalContentInset
    }

    public func expandedMinimalView() -> AnyView {
        AnyView(NowPlayingMinimalExpandedView(viewModel: viewModel))
    }

    @MainActor
    public func makeLockScreenMusicWidgetController(
        screenLockController: ScreenLockController
    ) -> LockScreenMusicWidgetController {
        LockScreenMusicWidgetController(
            viewModel: viewModel,
            settings: monitoringSettings,
            screenLockController: screenLockController
        )
    }

    public func activate() {
        Task { @MainActor in
            // 开关只控制是否上岛，监听与信息获取常驻运行以支撑展开态与锁屏显示。
            viewModel.startObserving()
        }
    }

    public func deactivate() {
        Task { @MainActor in viewModel.stopObserving() }
    }
}
