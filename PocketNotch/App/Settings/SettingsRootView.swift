import AgentEventModule
import AppKit
import Combine
import Foundation
import PocketNotchCore
import MediaModule
import StockModule
import SwiftUI
import WeatherModule

private extension View {
    /// 仅在外观被强制（深/浅色）时声明 preferredColorScheme；
    /// 跟随系统时不挂修饰符，避免 preferredColorScheme(nil) 在 macOS 上不释放旧值的问题。
    @ViewBuilder
    func appliedPreferredColorScheme(_ scheme: ColorScheme?) -> some View {
        if let scheme {
            preferredColorScheme(scheme)
        } else {
            self
        }
    }
}

struct SettingsRootView: View {
    private enum MenuCategory: String, CaseIterable, Identifiable {
        case island
        case modules
        case components
        case system

        var id: Self { self }

        var titleKey: String {
            switch self {
            case .island: "settings.category.appearanceInteraction"
            case .modules: "settings.category.dynamicServices"
            case .components: "settings.category.components"
            case .system: "settings.category.system"
            }
        }

        var panes: [Pane] {
            switch self {
            case .island: [.general, .interaction, .appearance]
            case .modules: [.media, .stocks, .agent, .weather, .notifications]
            case .components: [.lockScreen]
            case .system: [.permissions]
            }
        }
    }

    private enum Pane: String, CaseIterable, Identifiable {
        case appearance
        case interaction
        case general
        case notifications
        case media
        case weather
        case stocks
        case lockScreen
        case agent

        case permissions

        var id: Self { self }

        var titleKey: String {
            switch self {
            case .appearance: "settings.pane.appearance"
            case .interaction: "settings.pane.interaction"
            case .general: "settings.pane.general"
            case .notifications: "settings.pane.notifications"
            case .media: "settings.pane.media"
            case .weather: "settings.pane.weather"
            case .stocks: "settings.pane.stocks"
            case .lockScreen: "settings.pane.lockScreen"
            case .agent: "settings.pane.agent"

            case .permissions: "settings.pane.permissions"
            }
        }

        var subtitleKey: String {
            switch self {
            case .appearance: "settings.pane.appearance.subtitle"
            case .interaction: "settings.pane.interaction.subtitle"
            case .general: "settings.pane.general.subtitle"
            case .notifications: "settings.pane.notifications.subtitle"
            case .media: "settings.pane.media.subtitle"
            case .weather: "settings.pane.weather.subtitle"
            case .stocks: "settings.pane.stocks.subtitle"
            case .lockScreen: "settings.pane.lockScreen.subtitle"
            case .agent: "settings.pane.agent.subtitle"

            case .permissions: "settings.pane.permissions.subtitle"
            }
        }

        var symbol: String {
            switch self {
            case .appearance: "sparkles.rectangle.stack"
            case .interaction: "cursorarrow.motionlines"
            case .general: "gearshape"
            case .notifications: "bell.badge"
            case .media: "music.note"
            case .weather: "cloud.sun"
            case .stocks: "chart.line.uptrend.xyaxis"
            case .lockScreen: "lock.display"
            case .agent: "cpu"

            case .permissions: "hand.raised"
            }
        }

        var iconColor: Color {
            switch self {
            case .media: Color(red: 255 / 255, green: 49 / 255, blue: 92 / 255) // 音乐红粉
            case .weather: Color(red: 6 / 255, green: 140 / 255, blue: 254 / 255) // 天气预报蓝
            case .agent: Color(red: 102 / 255, green: 90 / 255, blue: 250 / 255) // Agent 紫

            case .stocks: Color(red: 0.09, green: 0.11, blue: 0.15) // 同外观/交互
            case .general: Color(red: 0.55, green: 0.55, blue: 0.58) // 灰
            case .appearance: Color(red: 57 / 255, green: 199 / 255, blue: 92 / 255) // 外观绿
            case .lockScreen: Color(red: 0.09, green: 0.11, blue: 0.15) // 黑
            case .interaction: Color(red: 6 / 255, green: 140 / 255, blue: 254 / 255) // 同天气
            case .notifications: Color(red: 254 / 255, green: 59 / 255, blue: 64 / 255) // 通知橙
            case .permissions: Color(red: 48 / 255, green: 209 / 255, blue: 156 / 255) // 权限青绿
            }
        }

        /// 动态服务图标统一白字形；背景色即各自图标色（见 iconColor）。
        var iconForeground: Color {
            .white
        }

        var badge: String? {
            switch self {
            case .stocks: NSLocalizedString("settings.stocks.developing", comment: "")
            default: nil
            }
        }
    }

    @ObservedObject var languageSettings: AppLanguageSettings
    @ObservedObject var themeSettings: AppThemeSettings
    @ObservedObject var menuBarSettings: MenuBarSettings
    @ObservedObject var launchAtLoginSettings: LaunchAtLoginSettings
    @ObservedObject var appearanceSettings: IslandAppearanceSettings
    @ObservedObject var interactionSettings: NotchInteractionSettings
    @ObservedObject var expandedTabSettings: ExpandedTabSettings
    @ObservedObject var displaySettings: NotchDisplaySettings
    @ObservedObject var notificationSettings: IslandNotificationSettings
    @ObservedObject var monitoringSettings: MediaMonitoringSettings
    @ObservedObject var weatherSettings: WeatherMonitoringSettings
    @ObservedObject var stockSettings: StockSettings
    @ObservedObject var residentSettings: CompactResidentSettings
    let registry: ModuleRegistry
    @ObservedObject var wallpaperPreview: SettingsWallpaperPreviewModel
    @ObservedObject var agentController: AgentActivityController
    let onDisplaySelectionChange: () -> Void
    @State private var selectedPane: Pane = .general

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var resolvedColorScheme: ColorScheme {
        themeSettings.resolvedColorScheme
    }

    private var palette: SettingsSurfacePalette {
        SettingsSurfacePalette(scheme: resolvedColorScheme)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SystemMaterialBackdrop(material: .underWindowBackground)
                .ignoresSafeArea(.container, edges: .top)

            HStack(spacing: 0) {
                sidebar
                paneDivider
                detail
            }
            .ignoresSafeArea(.container, edges: .top)

        }
        .frame(
            minWidth: 704,
            idealWidth: 704,
            maxWidth: 704,
            minHeight: 660,
            maxHeight: .infinity
        )
        .appliedPreferredColorScheme(themeSettings.resolvedColorScheme)
        .environment(\.haloSurface, palette)
        .environment(\.locale, languageSettings.locale)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(MenuCategory.allCases) { category in
                        menuSection(titleKey: category.titleKey, panes: category.panes)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.top, 44)
                .padding(.bottom, 16)
                .background {
                    SidebarScrollViewConfigurator()
                }
            }

            Spacer(minLength: 8)

        }
        .frame(width: 200)
        .background {
            SettingsPaneBackdrop(colorScheme: resolvedColorScheme)
        }
    }

    private var paneDivider: some View {
        Rectangle()
            .fill(
                resolvedColorScheme == .light
                    ? Color.black.opacity(0.015)
                    : Color.white.opacity(0.03)
            )
            .frame(width: 0.5)
    }


    private func menuSection(titleKey: String, panes: [Pane]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(titleKey))
                .font(.caption2.weight(.semibold))
                .tracking(0.45)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .frame(height: 14)

            VStack(spacing: 3) {
                ForEach(panes) { pane in
                    sidebarButton(pane)
                }
            }
        }
    }

    @ViewBuilder
    private func paneIcon(for pane: Pane) -> some View {
        if pane == .agent {
            AIChipRobotIcon()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: pane.symbol)
        }
    }

    private func sidebarButton(_ pane: Pane) -> some View {
        Button {
            selectedPane = pane
        } label: {
            HStack(spacing: 8) {
                paneIcon(for: pane)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(selectedPane == pane ? Color.white : palette.labelPrimary)
                    .frame(width: 22, height: 22)

                HStack(spacing: 6) {
                    Text(LocalizedStringKey(pane.titleKey))
                        .font(.system(size: 12, weight: selectedPane == pane ? .semibold : .medium))
                        .foregroundStyle(selectedPane == pane ? Color.white : palette.labelPrimary)
                        .lineLimit(1)

                    if let badge = pane.badge {
                        Text(badge)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.secondary.opacity(0.10)))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        selectedPane == pane
                            ? palette.selectedSidebarBackground
                            : .clear
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(pane.titleKey)))
        .accessibilityValue(selectedPane == pane ? NSLocalizedString("settings.common.selected", comment: "") : "")
    }

    private var detail: some View {
        Group {
            switch selectedPane {
            case .appearance:
                IslandAppearanceSettingsView(
                    settings: appearanceSettings,
                    residentSettings: residentSettings,
                    registry: registry,
                    wallpaperImage: wallpaperPreview.image
                )
            case .interaction:
                IslandInteractionSettingsView(
                    settings: interactionSettings,
                    tabSettings: expandedTabSettings,
                    displaySettings: displaySettings,
                    onDisplaySelectionChange: onDisplaySelectionChange
                )
            case .general:
                GeneralSettingsView(languageSettings: languageSettings, themeSettings: themeSettings, menuBarSettings: menuBarSettings, launchAtLoginSettings: launchAtLoginSettings)
            case .notifications:
                NotificationSettingsView(settings: notificationSettings)
            case .media:
                CompactContentSettingsView(
                    feature: .media,
                    appearanceSettings: appearanceSettings,
                    stockSettings: stockSettings,
                    monitoringSettings: monitoringSettings,
                    weatherSettings: weatherSettings,
                    registry: registry,
                    wallpaperImage: wallpaperPreview.image
                )
            case .weather:
                CompactContentSettingsView(
                    feature: .weather,
                    appearanceSettings: appearanceSettings,
                    stockSettings: stockSettings,
                    monitoringSettings: monitoringSettings,
                    weatherSettings: weatherSettings,
                    registry: registry,
                    wallpaperImage: wallpaperPreview.image
                )
            case .stocks:
                StockDevelopmentPlaceholderView()
            case .lockScreen:
                LockScreenMusicSettingsView(
                    settings: monitoringSettings,
                    wallpaperImage: wallpaperPreview.image
                )
            case .agent:
                AgentDevelopmentPlaceholderView()

            case .permissions:
                PermissionSettingsView(
                    monitoringSettings: monitoringSettings,
                    notificationSettings: notificationSettings
                )
            }
        }
        .id(selectedPane)
        .frame(width: 500)
        .frame(maxHeight: .infinity)
        .background {
            SettingsPaneBackdrop(colorScheme: resolvedColorScheme)
        }
    }
}

private struct SidebarScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureEnclosingScrollView(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureEnclosingScrollView(for: nsView)
    }

    private func configureEnclosingScrollView(for view: NSView) {
        DispatchQueue.main.async { [weak view] in
            guard let scrollView = view?.enclosingScrollView else { return }
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.hasHorizontalScroller = false
            scrollView.hasVerticalScroller = true

            // 只收窄侧边栏的竖向滚动条。使用浮层样式后它不会参与内容布局，
            // 自定义 scroller 宽度则避免系统默认轨道在视觉上显得过粗。
            if !(scrollView.verticalScroller is CompactOverlayScroller) {
                scrollView.verticalScroller = CompactOverlayScroller()
            }
            scrollView.verticalScroller?.controlSize = .small
        }
    }
}

private final class CompactOverlayScroller: NSScroller {
    override class func scrollerWidth(
        for controlSize: NSControl.ControlSize,
        scrollerStyle: NSScroller.Style
    ) -> CGFloat {
        if scrollerStyle == .overlay {
            return 6
        }
        return super.scrollerWidth(for: controlSize, scrollerStyle: scrollerStyle)
    }
}

private struct SettingsPaneBackdrop: View {
    let colorScheme: ColorScheme

    var body: some View {
        ZStack {
            SystemMaterialBackdrop(material: .underWindowBackground)
            if colorScheme == .light {
                Color.white.opacity(0.10)
            } else {
                Color.black.opacity(0.18)
            }
        }
    }
}

private struct AgentDevelopmentPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)

            Text("settings.agent.developing")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)

            Text("settings.agent.developing.description")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StockDevelopmentPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)

            Text("settings.stocks.developing")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)

            Text("settings.stocks.developing.description")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


