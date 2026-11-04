import AppKit
import Combine
import Foundation
import PocketNotchCore
import MediaModule
import StockModule
import SwiftUI
import WeatherModule

struct CompactContentWallpaperPreview<Content: View>: View {
    let wallpaperImage: NSImage?
    let content: Content
    let previewHeight: CGFloat

    init(
        wallpaperImage: NSImage?,
        previewHeight: CGFloat = 216,
        @ViewBuilder content: () -> Content
    ) {
        self.wallpaperImage = wallpaperImage
        self.previewHeight = previewHeight
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                wallpaper(size: proxy.size)

                content
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: .top
                    )
            }
        }
        .frame(height: previewHeight)
        .clipShape(previewShape)
        .overlay {
            previewShape.strokeBorder(.white.opacity(0.08), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 7)
    }

    @ViewBuilder
    private func wallpaper(size: CGSize) -> some View {
        ZStack(alignment: .top) {
            Color(red: 0.12, green: 0.14, blue: 0.17)

            if let wallpaperImage {
                let renderSize = wallpaperRenderSize(
                    sourceSize: wallpaperImage.size,
                    targetSize: size
                )

                Image(nsImage: wallpaperImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: renderSize.width, height: renderSize.height)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .clipped()
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .allowsHitTesting(false)
    }

    private func wallpaperRenderSize(sourceSize: CGSize, targetSize: CGSize) -> CGSize {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              targetSize.width > 0,
              targetSize.height > 0 else {
            return targetSize
        }

        let scale = max(
            targetSize.width / sourceSize.width,
            targetSize.height / sourceSize.height
        )
        return CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
    }

    private var previewShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }
}

enum CompactSettingsFeature: Equatable {
    case media
    case weather
    case stocks

    var moduleID: String {
        switch self {
        case .media: "media"
        case .weather: "weather"
        case .stocks: "stocks"
        }
    }

    var previewTitle: String {
        switch self {
        case .media: NSLocalizedString("settings.compact.mediaPreview", comment: "")
        case .weather: NSLocalizedString("settings.compact.weatherPreview", comment: "")
        case .stocks: NSLocalizedString("settings.compact.stocksPreview", comment: "")
        }
    }
}

struct CompactContentPreview: View {
    let feature: CompactSettingsFeature
    let registry: ModuleRegistry
    let wallpaperImage: NSImage?
    let previewHeight: CGFloat
    let previewIslandSize: CGSize

    private var displayedModule: (any PocketNotchModule)? {
        registry.modules.first { module in
            module.id == feature.moduleID && module.showsInCompactSettingsPreview
        }
    }

    init(
        feature: CompactSettingsFeature,
        registry: ModuleRegistry,
        wallpaperImage: NSImage?,
        previewHeight: CGFloat = 216,
        previewIslandSize: CGSize = AppearancePreviewLayout.previewIslandSize
    ) {
        self.feature = feature
        self.registry = registry
        self.wallpaperImage = wallpaperImage
        self.previewHeight = previewHeight
        self.previewIslandSize = previewIslandSize
    }

    private var compactLayout: ResolvedCompactIslandLayout {
        AppearancePreviewLayout.fixedCompactLayout(
            preferredCompactWidth: compactPreferredWidth
        )
    }

    private var compactBackgroundMetrics: IslandBackgroundMetrics {
        AppearancePreviewLayout.fixedCompactMetrics(
            preferredCompactWidth: compactPreferredWidth
        )
    }

    /// 股票行情预览反映真实常驻行为：常驻股票时灵动岛升为二档宽度（345），
    /// 左右耳随之变宽，保证名称与涨跌幅完整可见。
    private var compactPreferredWidth: CGFloat? {
        feature == .stocks ? CompactIslandTier.secondTierMinimumWidth : nil
    }

    var body: some View {
        CompactContentWallpaperPreview(
            wallpaperImage: wallpaperImage,
            previewHeight: previewHeight
        ) {
            ZStack(alignment: .top) {
                CompactIslandSurface(
                    layout: compactLayout,
                    metrics: compactBackgroundMetrics,
                    showsContent: displayedModule != nil
                ) {
                    displayedModule?.compactSettingsPreviewLeadingView()
                        ?? AnyView(EmptyView())
                } trailing: {
                    displayedModule?.compactSettingsPreviewTrailingView()
                        ?? AnyView(EmptyView())
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .scaleEffect(
                    AppearancePreviewLayout.islandScale(
                        rendered: CGSize(
                            width: compactLayout.islandWidth,
                            height: compactLayout.islandHeight
                        ),
                        into: previewIslandSize
                    ),
                    anchor: .top
                )

                if displayedModule == nil {
                    emptyState
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: NSLocalizedString("settings.compact.previewFormat", comment: ""), feature.previewTitle))
        .accessibilityValue(displayedModule == nil ? NSLocalizedString("settings.compact.noPreview", comment: "") : String(format: NSLocalizedString("settings.compact.previewingFormat", comment: ""), feature.previewTitle))
    }

    private var emptyState: some View {
                    Label("settings.compact.noPreviewAvailable", systemImage: "rectangle.3.group")
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule(style: .continuous).fill(.black.opacity(0.26)))
            .padding(.top, 88)
    }
}

struct CompactContentSettingsView: View {
    let feature: CompactSettingsFeature
    @ObservedObject var appearanceSettings: IslandAppearanceSettings
    @ObservedObject var stockSettings: StockSettings
    @ObservedObject var monitoringSettings: MediaMonitoringSettings
    @ObservedObject var weatherSettings: WeatherMonitoringSettings
    let registry: ModuleRegistry
    let wallpaperImage: NSImage?

    private let contentWidth: CGFloat = 620

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsHeaderLayout.cardSpacing) {
                header
                    .padding(.bottom, SettingsHeaderLayout.surroundingPadding)

                switch feature {
                case .media:
                    MediaMonitoringSettingsView(
                        settings: monitoringSettings,
                        isEmbedded: true,
                        wallpaperImage: wallpaperImage,
                        appearanceSettings: appearanceSettings,
                        registry: registry
                    )
                case .weather:
                    WeatherMonitoringSettingsView(
                        settings: weatherSettings,
                        isEmbedded: true,
                        appearanceSettings: appearanceSettings,
                        registry: registry,
                        wallpaperImage: wallpaperImage
                    )
                case .stocks:
                    moduleCard {
                        stockEnableCard
                    }
                    moduleCard {
                        previewStockCard
                    }
                    moduleCard {
                        stockControlSection
                    }
                    moduleCard {
                        watchlistStockCard
                    }
                }
            }
            .frame(maxWidth: contentWidth, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .settingsDetailScrolling()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        Color.clear
            .frame(height: SettingsHeaderLayout.placeholderHeight)
            .overlay(alignment: .topTrailing) {
                SettingsResetButton(isDisabled: usesDefaults) {
                    resetToDefaults()
                }
                .offset(y: SettingsHeaderLayout.resetButtonOffset)
            }
    }

    private var usesDefaults: Bool {
        switch feature {
        case .media: monitoringSettings.usesDefaultVisualPreferences
        case .weather: weatherSettings.usesDefaultValues
        case .stocks: stockSettings.usesDefaultValues
        }
    }

    private func resetToDefaults() {
        switch feature {
        case .media: monitoringSettings.resetToDefault()
        case .weather: weatherSettings.resetToDefault()
        case .stocks: stockSettings.resetToDefault()
        }
    }

    private func moduleCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        SettingsCard {
            content()
        }
    }

    private var stockEnableCard: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("settings.stocks.realtimeStock")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                stockStatusBadge
            }

            Spacer(minLength: 8)

            Toggle("settings.stocks.showStockMonitoring", isOn: $stockSettings.isPersistent)
                .labelsHidden()
                .toggleStyle(SettingsCompactSwitchToggleStyle())
                .frame(width: 44, height: 44)
                .accessibilityHint("settings.stocks.showStockMonitoring.description")
        }
        .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)
    }

    private var stockControlSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModuleSettingRow(
                title: NSLocalizedString("settings.stocks.excludeWeekends", comment: ""),
                description: NSLocalizedString("settings.stocks.excludeWeekends.description", comment: "")
            ) {
                Toggle("settings.stocks.excludeWeekends", isOn: $stockSettings.excludesWeekends)
                    .labelsHidden()
                    .toggleStyle(SettingsCompactSwitchToggleStyle())
                    .frame(width: 44, height: 44)
                    .accessibilityHint("settings.stocks.excludeWeekends.hint")
            }
            .animation(.easeOut(duration: 0.16), value: stockSettings.excludesWeekends)

            AppearanceRowDivider()

            StockPrioritySettingsSection(settings: stockSettings)
        }
    }

    private var previewStockCard: some View {
        StockSettingsView(
            settings: stockSettings,
            isEmbedded: true,
            appearanceSettings: appearanceSettings,
            registry: registry,
            wallpaperImage: wallpaperImage
        ).stockPreviewCard
    }

    private var watchlistStockCard: some View {
        StockSettingsView(
            settings: stockSettings,
            isEmbedded: true,
            appearanceSettings: appearanceSettings,
            registry: registry,
            wallpaperImage: wallpaperImage
        ).watchlistControls
    }


    private var stockStatusBadge: some View {
        Text(stockSettings.isPersistent ? NSLocalizedString("settings.common.enabled", comment: "") : NSLocalizedString("settings.common.closed", comment: ""))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(stockSettings.isPersistent ? Color.red : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(stockSettings.isPersistent ? Color.red.opacity(0.12) : Color.secondary.opacity(0.10))
            }
            .animation(.easeOut(duration: 0.16), value: stockSettings.isPersistent)
    }
}

/// 媒体灵动的壁纸预览：在桌面壁纸上渲染媒体紧凑岛，供“媒体灵动”卡片等复用。
struct MediaLivingIslandPreview: View {
    let wallpaperImage: NSImage?
    let registry: ModuleRegistry

    init(
        wallpaperImage: NSImage?,
        registry: ModuleRegistry
    ) {
        self.wallpaperImage = wallpaperImage
        self.registry = registry
    }

    private var mediaModule: (any PocketNotchModule)? {
        registry.modules.first { module in
            module.id == "media" && module.showsInCompactSettingsPreview
        }
    }

    private var compactLayout: ResolvedCompactIslandLayout {
        AppearancePreviewLayout.fixedCompactLayout()
    }

    private var compactBackgroundMetrics: IslandBackgroundMetrics {
        AppearancePreviewLayout.fixedCompactMetrics()
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .top) {
                wallpaper(size: size)

                CompactIslandSurface(
                    layout: compactLayout,
                    metrics: compactBackgroundMetrics,
                    showsContent: mediaModule != nil
                ) {
                    mediaModule?.compactSettingsPreviewLeadingView()
                        ?? AnyView(EmptyView())
                } trailing: {
                    mediaModule?.compactSettingsPreviewTrailingView()
                        ?? AnyView(EmptyView())
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .scaleEffect(
                    AppearancePreviewLayout.islandScale(
                        rendered: CGSize(
                            width: compactLayout.islandWidth,
                            height: compactLayout.islandHeight
                        ),
                        into: AppearancePreviewLayout.previewIslandSize
                    ),
                    anchor: .top
                )
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .overlay(alignment: .top) {
                if mediaModule == nil {
        Label("settings.compact.noPreviewAvailable", systemImage: "rectangle.3.group")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule(style: .continuous).fill(.black.opacity(0.26)))
                        .padding(.top, 88)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("settings.compact.mediaDynamicPreview")
        .accessibilityValue(mediaModule == nil ? NSLocalizedString("settings.compact.noPreview", comment: "") : NSLocalizedString("settings.compact.previewingMediaDynamic", comment: ""))
    }

    @ViewBuilder
    private func wallpaper(size: CGSize) -> some View {
        ZStack(alignment: .top) {
            Color(red: 0.12, green: 0.14, blue: 0.17)

            if let wallpaperImage {
                let renderSize = wallpaperRenderSize(
                    sourceSize: wallpaperImage.size,
                    targetSize: size
                )

                Image(nsImage: wallpaperImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: renderSize.width, height: renderSize.height)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .clipped()
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .allowsHitTesting(false)
    }

    private func wallpaperRenderSize(sourceSize: CGSize, targetSize: CGSize) -> CGSize {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              targetSize.width > 0,
              targetSize.height > 0 else {
            return targetSize
        }

        let scale = max(
            targetSize.width / sourceSize.width,
            targetSize.height / sourceSize.height
        )
        return CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
    }
}
