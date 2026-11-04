import PocketNotchCore
import SwiftUI

/// 亮度键上岛：按压亮度键时接管系统亮度并吞掉原生 OSD，在灵动刘海上短暂展示亮度。
public struct BrightnessModule: PocketNotchModule {
    public let id = "brightness"
    public let title: LocalizedStringKey = "module.brightness.title"
    public let priority = 40

    /// 亮度调节只做临时通知，不参与常驻 compact 内容竞争。
    @MainActor public var isCompactModuleEnabled: Bool { false }

    @MainActor private let viewModel: BrightnessViewModel
    @MainActor private let notificationSettings: IslandNotificationSettings

    @MainActor
    public init(
        notificationSettings: IslandNotificationSettings? = nil,
        notchViewModel: NotchViewModel? = nil
    ) {
        self.notificationSettings = notificationSettings ?? IslandNotificationSettings(defaults: nil)
        viewModel = BrightnessViewModel(
            notificationSettings: notificationSettings,
            notchViewModel: notchViewModel
        )
    }

    public func compactNotificationLeadingView() -> AnyView {
        AnyView(BrightnessHiddenLeadingView(viewModel: viewModel))
    }

    public func compactNotificationTrailingView() -> AnyView {
        AnyView(BrightnessHiddenTrailingView(viewModel: viewModel, settings: notificationSettings))
    }

    /// 临时优先级：亮度调节为 25，优先于音量/切歌（20）与电源（15）。
    @MainActor public func transientVisualPriority() -> Int? {
        viewModel.brightnessPresentation != nil ? 25 : nil
    }

    public func activate() {
        Task { @MainActor in viewModel.activate() }
    }

    public func deactivate() {
        Task { @MainActor in viewModel.deactivate() }
    }
}