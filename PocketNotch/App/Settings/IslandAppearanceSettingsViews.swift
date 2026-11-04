import AppKit
import Combine
import PocketNotchCore
import SwiftUI

private enum AppearanceTab: String, CaseIterable, Identifiable {
    case resting
    case compact
    case interactive

    var id: Self { self }

    var title: String {
        switch self {
        case .resting: NSLocalizedString("settings.appearance.tabResting", comment: "")
        case .compact: NSLocalizedString("settings.appearance.tabCompact", comment: "")
        case .interactive: NSLocalizedString("settings.appearance.tabInteractive", comment: "")
        }
    }
}

enum AppearancePreviewLayout {
    static let previewSize = CGSize(width: 270, height: 164)
    /// 灵动态预览：按真实灵动态（250×24）作 2/3 等比缩放，保持宽扁的岛身比例。
    static let previewIslandSize = CGSize(
        width: IslandAppearanceConstraints.defaultCompactWidth * (2.0 / 3.0),
        height: IslandAppearanceConstraints.defaultCompactHeight * (2.0 / 3.0)
    )
    /// 股票行情预览：宽度取灵动态默认（250）的 60%，高度按岛宽高比（200:32）同步放大。
    /// 股票行情预览：宽度取灵动态默认（250）的 60%，高度按岛宽高比（200:32）同步放大。
    /// 股票行情预览：常驻股票时灵动岛升为二档（345 宽），
    /// 按与灵动态预览同等的 2/3 缩放，展示二档的宽扁岛身。
    static let stockPreviewIslandSize = CGSize(
        width: CompactIslandTier.secondTierMinimumWidth * (2.0 / 3.0),
        height: IslandAppearanceConstraints.defaultCompactHeight * (2.0 / 3.0)
    )
    /// 预览统一使用默认隐藏岛（200×32）作为几何基准，不跟随屏幕或用户尺寸调整。
    static let previewHiddenIslandSize = CGSize(
        width: IslandAppearanceConstraints.defaultRestingWidth,
        height: IslandAppearanceConstraints.defaultFloatingRestingHeight
    )

    static func fixedCompactLayout(
        preferredCompactWidth: CGFloat? = nil
    ) -> ResolvedCompactIslandLayout {
        ResolvedCompactIslandLayout.resolve(
            contentHeight: IslandAppearanceConstraints.defaultCompactHeight,
            minimumIslandHeight: previewHiddenIslandSize.height,
            notchPhysicalWidth: 0,
            restingBodyWidth: IslandAppearanceConstraints.automaticRestingBodyWidth(
                physicalNotchWidth: 0
            ),
            preferredCompactOuterInset: nil,
            preferredCompactVerticalInset: nil,
            preferredCompactWidth: preferredCompactWidth,
            fitsAutomaticContentToMinimumHeight: true
        )
    }

    static func fixedCompactMetrics(
        preferredCompactWidth: CGFloat? = nil
    ) -> IslandBackgroundMetrics {
        IslandBackgroundMetrics.resolved(
            hiddenIslandSize: previewHiddenIslandSize,
            notchPhysicalWidth: 0,
            expandedModuleCount: 1,
            showsCompactContent: true,
            preferredCompactWidth: preferredCompactWidth
        )
    }

    /// 把默认几何的岛等比缩入指定预览画布，保持肩部圆弧为正圆。
    static func islandScale(rendered: CGSize, into canvas: CGSize) -> CGFloat {
        guard rendered.width > 0, rendered.height > 0 else { return 1 }
        return min(
            canvas.width / rendered.width,
            canvas.height / rendered.height
        )
    }

    /// 隐藏态预览固定缩放比例：宽度与高度随设置各自独立变化，不会因等比适配画布而互相压缩。
    /// 展开态与灵动态的岛宽可变，其缩放分别由实际尺寸推导（见 `expandedPreviewScale` 与 `compactPreviewScale`）。
    static let restingPreviewScale: CGFloat = 0.5
    /// 展开态预览左右呼吸：展开岛（此刻页整窗）比灵动态宽得多，等比缩入时两侧各留一点，
    /// 避免背板阴影贴到预览圆角边。缩放比例由实际展开尺寸推导，不写死。
    static let expandedPreviewInset: CGFloat = 10
    /// 灵动态预览可达到的最宽岛体：主体最大宽（500）加两侧肩部预算。
    static var maximumCompactPreviewWidth: CGFloat {
        IslandAppearanceConstraints.maximumCompactWidth
            + NotchShapeSpec.shoulderWidth(
                forBodyWidth: IslandAppearanceConstraints.maximumCompactWidth
            ) * 2
    }
    /// 灵动态缩放由「预览画布宽 / 最大岛宽」推导：默认宽度仍饱满，拉满也不越出预览背景。
    static let compactPreviewScale: CGFloat = previewSize.width / maximumCompactPreviewWidth
}

struct IslandAppearanceSettingsView: View {
    @ObservedObject var settings: IslandAppearanceSettings
    @ObservedObject var residentSettings: CompactResidentSettings
    let registry: ModuleRegistry
    let wallpaperImage: NSImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: AppearanceTab = .resting

    private let appearanceContentWidth: CGFloat = 720

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsHeaderLayout.cardSpacing) {
                header
                    .padding(.bottom, SettingsHeaderLayout.surroundingPadding)

                modeSelectionCard

                appearancePreviewCard

                selectedContent
                    .id(selectedTab)
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            }
            .frame(maxWidth: appearanceContentWidth, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .settingsDetailScrolling()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.18), value: selectedTab)
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
        switch selectedTab {
        case .resting: settings.usesAutomaticRestingLayout
        case .compact: settings.usesAutomaticCompactLayout
        case .interactive: settings.expandedBackgroundStyle == .standard
        }
    }

    private func resetToDefaults() {
        switch selectedTab {
        case .resting: settings.resetRestingToAutomatic()
        case .compact: settings.resetCompactToAutomatic()
        case .interactive:
            settings.expandedBackgroundStyle = .standard
            settings.expandedBackgroundFrostedRegion = IslandAppearanceSettings.defaultFrostedRegion
            settings.expandedLiquidGlassMaterial = IslandAppearanceSettings.defaultLiquidGlassMaterial
        }
    }

    private var modeSelectionCard: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 16) {
                Text("settings.appearance.selectMode")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 12)

                appearanceTabSwitcher
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(height: AppearanceRowLayout.moduleRowHeight)
        }
    }

    private var appearancePreviewCard: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 0) {
                Text("settings.appearance.appearancePreview")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                AppearanceIslandPreview(
                    settings: settings,
                    residentSettings: residentSettings,
                    registry: registry,
                    wallpaperImage: wallpaperImage,
                    tab: selectedTab
                )
                .frame(
                    width: AppearancePreviewLayout.previewSize.width,
                    height: AppearancePreviewLayout.previewSize.height
                )
            }
            .frame(height: AppearancePreviewLayout.previewSize.height)
            .padding(.vertical, AppearanceCardLayout.contentInset)
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .resting:
            RestingIslandAppearanceSettingsView(settings: settings).content
        case .compact:
            CompactIslandAppearanceSettingsView(
                settings: settings,
                residentSettings: residentSettings
            ).content
        case .interactive:
            InteractiveIslandAppearanceSettingsView(
                settings: settings,
                residentSettings: residentSettings,
                registry: registry,
                wallpaperImage: wallpaperImage
            ).content
        }
    }

    /// 紧凑的三项模式切换器，放在“选择模式”卡片右侧。
    private var appearanceTabSwitcher: some View {
        SettingsSegmentedControl(
            selection: $selectedTab,
            options: AppearanceTab.allCases,
            title: { $0.title },
            accessibilityTitle: NSLocalizedString("settings.appearance.selectMode", comment: "")
        )
    }
}

/// 外观设置预览的统一岛组件：隐藏模式 / 灵动模式 / 交互模式共用同一套
/// 真实刘海背板填充、阴影、内容遮罩与顶部贴顶渲染，只传入形状 state、尺寸与内容元素。
private struct IslandAppearanceSurface<Content: View>: View {
    let state: IslandBackgroundState
    let metrics: IslandBackgroundMetrics
    let compactMorphProgress: CGFloat
    let shadowStyle: IslandShadowStyle
    let ambientShadowStyle: IslandShadowStyle
    let backgroundStyle: ExpandedBackgroundStyle
    let frostedRegion: CGFloat
    let liquidGlassMaterial: LiquidGlassMaterial
    @ViewBuilder let content: () -> Content

    init(
        state: IslandBackgroundState,
        metrics: IslandBackgroundMetrics,
        compactMorphProgress: CGFloat,
        shadowStyle: IslandShadowStyle,
        ambientShadowStyle: IslandShadowStyle,
        backgroundStyle: ExpandedBackgroundStyle,
        frostedRegion: CGFloat,
        liquidGlassMaterial: LiquidGlassMaterial = .bubbles,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.state = state
        self.metrics = metrics
        self.compactMorphProgress = compactMorphProgress
        self.shadowStyle = shadowStyle
        self.ambientShadowStyle = ambientShadowStyle
        self.backgroundStyle = backgroundStyle
        self.frostedRegion = frostedRegion
        self.liquidGlassMaterial = liquidGlassMaterial
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 黑色剪影只属于标准纯黑岛；材质类样式不垫黑，直接露材质，
            // 否则玻璃/毛玻璃透明时会透出这片黑。
            if backgroundStyle == .standard {
                shape
                    .fill(PocketNotchTheme.background)
                    .shadow(
                        color: PocketNotchTheme.islandShadowColor.opacity(shadowStyle.opacity),
                        radius: shadowStyle.radius,
                        y: shadowStyle.offsetY
                    )
                    .shadow(
                        color: PocketNotchTheme.islandShadowColor.opacity(ambientShadowStyle.opacity),
                        radius: ambientShadowStyle.radius,
                        y: ambientShadowStyle.offsetY
                    )
                    .mask {
                        Rectangle()
                            .padding(.top, 1)
                    }
            }

            // 背景样式接入点：新增样式时在此按 case 扩展渲染。
            switch backgroundStyle {
            case .standard:
                shape
                    .fill(PocketNotchTheme.background)
            case .frosted:
                // 预览与运行时同路：系统材质 + BlackOverlay 黑色盖板（顶部纯黑、底部平滑渐隐）。
                GeometryReader { geo in
                    ZStack(alignment: .top) {
                        FrostedMaterialBackdrop()
                            .padding(-IslandLayoutToken.hoverOutset)
                        BlackOverlay(
                            frostedRegion: frostedRegion,
                            containerHeight: geo.size.height,
                            cornerRadius: NotchShapeSpec.cornerRadius(
                                forHeight: geo.size.height,
                                expansionProgress: shape.expansionProgress
                            )
                        )
                        .animation(.easeInOut(duration: 0.25), value: frostedRegion)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
                .clipShape(shape)
            case .liquidGlass:
                IslandLiquidGlassBackdrop(
                    shape: shape,
                    material: liquidGlassMaterial,
                    frostedRegion: frostedRegion
                )
            case .simulatedLiquid:
                IslandSimulatedLiquidBackdrop(shape: shape, frostedRegion: frostedRegion)
            }

            content()
                .mask {
                    shape.fill(.white)
                }
        }
    }


    private var shape: NotchShape {
        NotchShape(
            state: state,
            metrics: metrics,
            compactMorphProgress: compactMorphProgress,
            rendersInFullBounds: true
        )
    }
}

/// 外观设置顶部的壁纸预览图：复用媒体灵动设置的壁纸预览容器，
/// 根据所选模式标签展示对应状态的岛形态。形状使用真实刘海组件，
/// 几何取自本机真实屏幕与凹口（并跟随外观设置中的尺寸调整），
/// 各轴独立等比缩入身材匹配的预览画布。
private struct AppearanceIslandPreview: View {
    @ObservedObject var settings: IslandAppearanceSettings
    @ObservedObject var residentSettings: CompactResidentSettings
    let registry: ModuleRegistry
    let wallpaperImage: NSImage?
    let tab: AppearanceTab

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var screenGeometry: (hiddenSize: CGSize, notchWidth: CGFloat) {
        let positioner = NotchPositioner()
        guard let screen = positioner.targetScreen() else {
            return (
                CGSize(
                    width: PocketNotchTheme.islandBackgroundMetrics.hiddenWidth,
                    height: NotchPositioner.fallbackHiddenHeight
                ),
                0
            )
        }
        return (
            positioner.hiddenIslandSize(on: screen),
            positioner.hasNotch(on: screen) ? positioner.notchWidth(on: screen) : 0
        )
    }

    private var restingMetrics: IslandBackgroundMetrics {
        IslandBackgroundMetrics.resolved(
            hiddenIslandSize: screenGeometry.hiddenSize,
            notchPhysicalWidth: screenGeometry.notchWidth,
            expandedModuleCount: 1,
            showsCompactContent: false,
            preferredRestingHeight: settings.customRestingHeight,
            preferredRestingWidth: settings.customRestingWidth,
            preferredEarHeight: settings.customEarHeight
        )
    }

    private var compactPreferredWidth: CGFloat? {
        CompactIslandTier.resolvedPreferredWidth(
            settings.customCompactWidth,
            stockDisplayActive: residentSettings.isStockCompactDisplayActive
        )
    }

    /// 灵动态岛高沿用隐藏态设置，两个状态共用同一个高度变量；耳朵不随高度变化。
    private var resolvedIslandHeight: CGFloat {
        settings.resolvedIslandHeight(
            physicalNotchHeight: screenGeometry.notchWidth > 0 ? screenGeometry.hiddenSize.height : 0,
            defaultIslandHeight: screenGeometry.hiddenSize.height
        )
    }

    private var compactLayout: ResolvedCompactIslandLayout {
        let restingBodyWidth = IslandAppearanceConstraints.automaticRestingBodyWidth(
            physicalNotchWidth: screenGeometry.notchWidth
        )
        return ResolvedCompactIslandLayout.resolve(
            contentHeight: settings.resolvedEarHeight(),
            minimumIslandHeight: resolvedIslandHeight,
            notchPhysicalWidth: screenGeometry.notchWidth,
            restingBodyWidth: restingBodyWidth,
            preferredCompactOuterInset: settings.resolvedCompactOuterInset(),
            preferredCompactVerticalInset: settings.resolvedCompactVerticalInset(
                islandHeight: resolvedIslandHeight
            ),
            preferredCompactWidth: compactPreferredWidth,
            fitsAutomaticContentToMinimumHeight: false
        )
    }

    private var compactBackgroundMetrics: IslandBackgroundMetrics {
        IslandBackgroundMetrics.resolved(
            hiddenIslandSize: screenGeometry.hiddenSize,
            notchPhysicalWidth: screenGeometry.notchWidth,
            expandedModuleCount: 1,
            showsCompactContent: true,
            preferredRestingHeight: settings.customRestingHeight,
            preferredRestingWidth: settings.customRestingWidth,
            preferredCompactOuterInset: settings.resolvedCompactOuterInset(),
            preferredCompactVerticalInset: nil,
            preferredEarHeight: settings.customEarHeight,
            preferredCompactWidth: compactPreferredWidth
        )
    }

    private var expandedMetrics: IslandBackgroundMetrics {
        restingMetrics
    }

    /// 展开岛随「此刻页」卡片总宽变化，等比缩入预览画布并左右留呼吸，避免长度溢出预览背景。
    private var expandedPreviewScale: CGFloat {
        AppearancePreviewLayout.islandScale(
            rendered: expandedMetrics.expandedSize,
            into: CGSize(
                width: AppearancePreviewLayout.previewSize.width
                    - AppearancePreviewLayout.expandedPreviewInset * 2,
                height: AppearancePreviewLayout.previewSize.height
            )
        )
    }

    private var mediaModule: (any PocketNotchModule)? {
        registry.modules.first { module in
            module.id == "media" && module.showsInCompactSettingsPreview
        }
    }

    var body: some View {
        CompactContentWallpaperPreview(
            wallpaperImage: wallpaperImage,
            previewHeight: AppearancePreviewLayout.previewSize.height
        ) {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    switch tab {
                    case .resting:
                        restingPreview
                    case .compact:
                        compactPreview
                    case .interactive:
                        interactivePreview
                    }
                }
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .top
                )
            }
        }
        .frame(
            width: AppearancePreviewLayout.previewSize.width,
            height: AppearancePreviewLayout.previewSize.height
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("settings.appearance.appearanceStylePreview")
        .accessibilityValue(tab.title)
    }

    private var restingPreview: some View {
        IslandAppearanceSurface(
            state: .hidden,
            metrics: restingMetrics,
            compactMorphProgress: 0,
            shadowStyle: IslandMaterialToken.shadowStyle(for: .idle, compactMorphProgress: 0),
            ambientShadowStyle: IslandMaterialToken.ambientShadowStyle(for: .idle, compactMorphProgress: 0),
            backgroundStyle: .standard,
            frostedRegion: IslandAppearanceSettings.defaultFrostedRegion
        ) {
            EmptyView()
        }
        .frame(
            width: restingMetrics.hiddenSize.width,
            height: restingMetrics.hiddenSize.height,
            alignment: .top
        )
        .scaleEffect(AppearancePreviewLayout.restingPreviewScale, anchor: .top)
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(
            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 1),
            value: restingMetrics
        )
    }

    private var compactPreview: some View {
        CompactIslandSurface(
            layout: compactLayout,
            metrics: compactBackgroundMetrics,
            showsContent: true
        ) {
            compactLeadingContent
        } trailing: {
            compactTrailingContent
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .scaleEffect(AppearancePreviewLayout.compactPreviewScale, anchor: .top)
        .animation(
            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 1),
            value: compactLayout
        )
    }

    private var interactivePreview: some View {
        IslandAppearanceSurface(
            state: .expanded,
            metrics: expandedMetrics,
            compactMorphProgress: 1,
            shadowStyle: IslandMaterialToken.shadowStyle(for: .expanded, compactMorphProgress: 1),
            ambientShadowStyle: IslandMaterialToken.ambientShadowStyle(for: .expanded, compactMorphProgress: 1),
            backgroundStyle: settings.expandedBackgroundStyle,
            frostedRegion: settings.expandedBackgroundFrostedRegion,
            liquidGlassMaterial: settings.expandedLiquidGlassMaterial
        ) {
            interactiveSampleContent
        }
        .frame(
            width: expandedMetrics.expandedSize.width,
            height: expandedMetrics.expandedSize.height,
            alignment: .top
        )
        .scaleEffect(expandedPreviewScale, anchor: .top)
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.92),
            value: expandedMetrics
        )
    }

    @ViewBuilder
    private var compactLeadingContent: some View {
        if let mediaModule {
            mediaModule.compactSettingsPreviewLeadingView()
        } else {
            AppearanceEarArtworkPlaceholder()
        }
    }

    @ViewBuilder
    private var compactTrailingContent: some View {
        if let mediaModule {
            mediaModule.compactSettingsPreviewTrailingView()
        } else {
            AppearanceEarBarsPlaceholder()
        }
    }

    /// 展开态背板内的示例内容：复用「此刻」页真实卡片（媒体/待办/文件夹/剪贴板/系统），
    /// 与运行时同一套宽度与排布，保证设置预览与真实展开页一致。
    private var interactiveSampleContent: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: expandedMetrics.hiddenHeight)

            nowPageCardsRow
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .padding(.horizontal, NotchShapeSpec.expandedCornerRadius)
        .allowsHitTesting(false)
    }

    /// 与 `NowSnapshotView` 同源的「此刻」页卡片行：取各模块提供的附件，按统一宽度排布。
    private var nowPageCardsRow: some View {
        let cardHeight = IslandLayoutToken.expandedNowPageCardHeight
        let modules = registry.modules
        return HStack(spacing: IslandLayoutToken.expandedNowPageCardSpacing) {
            if let view = modules.compactMap({ $0.nowPageLeadingAccessoryView() }).first {
                view.frame(
                    width: IslandLayoutToken.expandedNowPageLeadingCardWidth,
                    height: cardHeight
                )
            }
            if let view = modules.compactMap({ $0.nowPageCenterAccessoryView() }).first {
                view.frame(
                    width: IslandLayoutToken.expandedNowPageStandardCardWidth,
                    height: cardHeight,
                    alignment: .top
                )
            }
            if let view = modules.compactMap({ $0.nowPageFolderAccessoryView() }).first {
                view.frame(
                    width: IslandLayoutToken.expandedNowPageQuickStatsCardWidth,
                    height: cardHeight,
                    alignment: .top
                )
            }
            if let view = modules.compactMap({ $0.nowPageTrailingAccessoryView() }).first {
                view.frame(
                    width: IslandLayoutToken.expandedNowPageClipboardCardWidth,
                    height: cardHeight,
                    alignment: .top
                )
            }
            if let view = modules.compactMap({ $0.nowPageRightAccessoryView() }).first {
                view.frame(
                    width: IslandLayoutToken.expandedNowPageSystemCardWidth,
                    height: cardHeight,
                    alignment: .top
                )
            }
            if let view = modules.compactMap({ $0.nowPageRightmostAccessoryView() }).first {
                view.frame(
                    width: IslandLayoutToken.expandedNowPageSystemStatusCardWidth,
                    height: cardHeight,
                    alignment: .top
                )
            }
        }
        .padding(.horizontal, IslandLayoutToken.expandedNowPageHorizontalInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 灵动/交互预览共用的示例封面：三色渐变圆角图块。
private struct AppearanceEarArtworkPlaceholder: View {
    @Environment(\.notchHiddenIslandSize) private var hiddenIslandSize
    @Environment(\.islandCompactContentSize) private var islandCompactContentSize
    var size: CGFloat? = nil
    var cornerRatio: CGFloat = 0.22

    fileprivate static let palette = [
        Color(red: 0.18, green: 0.38, blue: 0.92),
        Color(red: 0.96, green: 0.42, blue: 0.50),
        Color(red: 0.98, green: 0.78, blue: 0.38),
    ]

    @ViewBuilder
    private var resolvedSize: some View {
        let diameter = size
            ?? islandCompactContentSize?.height
            ?? CompactIslandContentSpec.resolvedContentHeight(
                for: hiddenIslandSize.height
            )
        RoundedRectangle(cornerRadius: diameter * cornerRatio, style: .continuous)
            .fill(
                LinearGradient(
                    colors: Self.palette,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "waveform")
                    .font(.system(size: diameter * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: Self.palette[0].opacity(0.22), radius: 3)
    }

    var body: some View {
        resolvedSize
    }
}

/// 灵动预览缺少模块时的示例频谱：静态错落的旋律柱。
private struct AppearanceEarBarsPlaceholder: View {
    @Environment(\.notchHiddenIslandSize) private var hiddenIslandSize
    @Environment(\.islandCompactContentSize) private var islandCompactContentSize

    private static let colors = [
        Color(red: 0.20, green: 0.74, blue: 0.96),
        Color(red: 0.52, green: 0.38, blue: 0.94),
        Color(red: 0.95, green: 0.38, blue: 0.58),
    ]

    var body: some View {
        let diameter = islandCompactContentSize?.height
            ?? CompactIslandContentSpec.resolvedContentHeight(
                for: hiddenIslandSize.height
            )
        HStack(alignment: .center, spacing: max(diameter * 0.09, 2)) {
            ForEach(0..<5) { index in
                Capsule()
                    .fill(Self.colors[index % Self.colors.count].opacity(0.9))
                    .frame(
                        width: max(diameter * 0.07, 2),
                        height: barHeight(diameter, index)
                    )
            }
        }
        .frame(width: diameter * 1.2, height: diameter, alignment: .center)
    }

    private func barHeight(_ diameter: CGFloat, _ index: Int) -> CGFloat {
        let base = diameter * (0.30 + CGFloat(index % 3) * 0.13)
        let offset = CGFloat(index % 2) * diameter * 0.08
        return max(base + offset, diameter * 0.2)
    }
}

private struct InteractiveIslandAppearanceSettingsView: View {
    @ObservedObject var settings: IslandAppearanceSettings
    @ObservedObject var residentSettings: CompactResidentSettings
    let registry: ModuleRegistry
    let wallpaperImage: NSImage?

    fileprivate var content: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("settings.appearance.backgroundStyle")
                            .font(.system(size: 12, weight: .semibold))
                    }

                    Spacer(minLength: 12)

                    Picker("settings.appearance.backgroundStyle", selection: backgroundStyleBinding) {
                        ForEach(ExpandedBackgroundStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                }
                .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)

                if settings.expandedBackgroundStyle == .liquidGlass {
                    AppearanceRowDivider()

                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("settings.appearance.glassStyle")
                                .font(.system(size: 12, weight: .semibold))
                        }

                        Spacer(minLength: 12)

                        Picker("settings.appearance.glassStyle", selection: liquidGlassMaterialBinding) {
                            ForEach(LiquidGlassMaterial.allCases) { material in
                                Text(material.displayName).tag(material)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 200)
                    }
                    .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)
                }

                if settings.expandedBackgroundStyle.supportsFrostedRegion {
                    AppearanceRowDivider()

                    AppearanceSliderRow(
                        title: NSLocalizedString("settings.appearance.materialRegion", comment: ""),
                        subtitle: NSLocalizedString("settings.appearance.materialRegion.description", comment: ""),
                        value: frostedRegionBinding,
                        range: Double(IslandAppearanceSettings.frostedRegionBounds.lowerBound)
                            ... Double(IslandAppearanceSettings.frostedRegionBounds.upperBound),
                        valueText: "\(Int((settings.expandedBackgroundFrostedRegion * 100).rounded()))%",
                        isIntegerValue: false
                    )
                }
            }
        }
    }

    private var backgroundStyleBinding: Binding<ExpandedBackgroundStyle> {
        Binding(
            get: { settings.expandedBackgroundStyle },
            set: { settings.expandedBackgroundStyle = $0 }
        )
    }

    private var liquidGlassMaterialBinding: Binding<LiquidGlassMaterial> {
        Binding(
            get: { settings.expandedLiquidGlassMaterial },
            set: { settings.expandedLiquidGlassMaterial = $0 }
        )
    }

    private var frostedRegionBinding: Binding<Double> {
        Binding(
            get: { Double(settings.expandedBackgroundFrostedRegion) },
            set: { settings.expandedBackgroundFrostedRegion = CGFloat($0) }
        )
    }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 28)
        }
        .settingsDetailScrolling()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RestingIslandAppearanceSettingsView: View {
    @ObservedObject var settings: IslandAppearanceSettings

    private var screenGeometry: (
        defaultHeight: CGFloat,
        physicalNotchHeight: CGFloat,
        notchWidth: CGFloat
    ) {
        let positioner = NotchPositioner()
        guard let screen = positioner.targetScreen() else {
            return (NotchPositioner.fallbackHiddenHeight, 0, 0)
        }
        let hasNotch = positioner.hasNotch(on: screen)
        let defaultHeight = positioner.hiddenIslandSize(on: screen).height
        return (
            defaultHeight,
            hasNotch ? defaultHeight : 0,
            hasNotch ? positioner.notchWidth(on: screen) : 0
        )
    }

    private var resolvedHeight: CGFloat {
        settings.resolvedIslandHeight(
            physicalNotchHeight: screenGeometry.physicalNotchHeight,
            defaultIslandHeight: screenGeometry.defaultHeight
        )
    }

    private var resolvedWidth: CGFloat {
        settings.resolvedRestingWidth(
            physicalNotchWidth: screenGeometry.notchWidth,
            restingHeight: resolvedHeight
        )
    }

    private var minimumWidth: CGFloat {
        IslandAppearanceConstraints.minimumRestingWidth(
            physicalNotchWidth: screenGeometry.notchWidth,
            restingHeight: resolvedHeight
        )
    }

    private var heightBinding: Binding<Double> {
        Binding(
            get: { Double(resolvedHeight) },
            set: {
                settings.setCustomRestingHeight(
                    CGFloat($0),
                    physicalNotchHeight: screenGeometry.physicalNotchHeight
                )
            }
        )
    }

    private var widthBinding: Binding<Double> {
        Binding(
            get: { Double(resolvedWidth) },
            set: {
                settings.setCustomRestingWidth(
                    CGFloat($0),
                    physicalNotchWidth: screenGeometry.notchWidth,
                    restingHeight: resolvedHeight
                )
            }
        )
    }

    fileprivate var content: some View {
        VStack(alignment: .leading, spacing: 24) {
                SettingsCard {
                    AppearanceSliderRow(
                        title: NSLocalizedString("settings.appearance.width", comment: ""),
                        subtitle: NSLocalizedString("settings.appearance.restingWidth.description", comment: ""),
                        value: widthBinding,
                        range: Double(minimumWidth)...Double(
                            IslandAppearanceConstraints.defaultCompactBodyWidth(
                                physicalNotchWidth: screenGeometry.notchWidth
                            )
                        ),
                        valueText: "\(Int(resolvedWidth.rounded()))"
                    )

                    AppearanceRowDivider()

                    AppearanceSliderRow(
                        title: NSLocalizedString("settings.appearance.height", comment: ""),
                        subtitle: NSLocalizedString("settings.appearance.height.description", comment: ""),
                        value: heightBinding,
                        range: Double(
                            IslandAppearanceConstraints.minimumRestingHeight(
                                physicalNotchHeight: screenGeometry.physicalNotchHeight
                            )
                        )...Double(
                            IslandAppearanceConstraints.maximumRestingHeight(
                                physicalNotchHeight: screenGeometry.physicalNotchHeight
                            )
                        ),
                        valueText: "\(Int(resolvedHeight.rounded()))"
                    )
                }
        }
    }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 28)
        }
        .settingsDetailScrolling()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CompactIslandAppearanceSettingsView: View {
    @ObservedObject var settings: IslandAppearanceSettings
    @ObservedObject var residentSettings: CompactResidentSettings

    private var screenGeometry: (
        defaultHeight: CGFloat,
        physicalNotchHeight: CGFloat,
        notchWidth: CGFloat
    ) {
        let positioner = NotchPositioner()
        guard let screen = positioner.targetScreen() else {
            return (NotchPositioner.fallbackHiddenHeight, 0, 0)
        }
        let hasNotch = positioner.hasNotch(on: screen)
        let defaultHeight = positioner.hiddenIslandSize(on: screen).height
        return (
            defaultHeight,
            hasNotch ? defaultHeight : 0,
            hasNotch ? positioner.notchWidth(on: screen) : 0
        )
    }

    /// 灵动态岛高沿用隐藏态设置；耳朵独立，不随高度变化。
    private var resolvedIslandHeight: CGFloat {
        settings.resolvedIslandHeight(
            physicalNotchHeight: screenGeometry.physicalNotchHeight,
            defaultIslandHeight: screenGeometry.defaultHeight
        )
    }

    private var resolvedLayout: ResolvedCompactIslandLayout {
        let preferredWidth = CompactIslandTier.resolvedPreferredWidth(
            settings.customCompactWidth,
            stockDisplayActive: residentSettings.isStockCompactDisplayActive
        )
        return resolveLayout(
            contentHeight: settings.resolvedEarHeight(),
            preferredWidth: preferredWidth
        )
    }

    private var minimumSelectableWidth: CGFloat {
        IslandAppearanceConstraints.defaultCompactBodyWidth(
            physicalNotchWidth: screenGeometry.notchWidth
        )
    }

    private var compactWidthSubtitle: String {
        NSLocalizedString("settings.appearance.compactWidth.description", comment: "")
    }

    private func resolveLayout(
        contentHeight: CGFloat,
        preferredWidth: CGFloat?
    ) -> ResolvedCompactIslandLayout {
        let restingBodyWidth = IslandAppearanceConstraints.automaticRestingBodyWidth(
            physicalNotchWidth: screenGeometry.notchWidth
        )
        return ResolvedCompactIslandLayout.resolve(
            contentHeight: contentHeight,
            minimumIslandHeight: resolvedIslandHeight,
            notchPhysicalWidth: screenGeometry.notchWidth,
            restingBodyWidth: restingBodyWidth,
            preferredCompactOuterInset: settings.resolvedCompactOuterInset(),
            preferredCompactVerticalInset: settings.resolvedCompactVerticalInset(
                islandHeight: resolvedIslandHeight
            ),
            preferredCompactWidth: preferredWidth,
            fitsAutomaticContentToMinimumHeight: false
        )
    }

    private var widthBinding: Binding<Double> {
        Binding(
            get: { Double(resolvedLayout.bodyWidth) },
            set: {
                settings.customCompactWidth = CGFloat($0)
            }
        )
    }

    /// 「耳朵高度」独立于隐藏态「高度」：拖动只改耳朵，不会同步改变岛高。
    private var earHeightBinding: Binding<Double> {
        Binding(
            get: { Double(settings.resolvedEarHeight()) },
            set: { settings.setCustomEarHeight(CGFloat($0)) }
        )
    }

    private var resolvedEarHeightText: String {
        String(Int(settings.resolvedEarHeight().rounded()))
    }

    /// 「耳朵上下间距」拖动即改岛高（岛高 = 耳朵高度 + 2×间距），与隐藏态「高度」共用同一变量。
    private var verticalInsetBinding: Binding<Double> {
        Binding(
            get: { Double(resolvedVerticalInset) },
            set: {
                settings.setCompactVerticalInset(
                    CGFloat($0),
                    physicalNotchHeight: screenGeometry.physicalNotchHeight
                )
            }
        )
    }

    private var resolvedVerticalInset: CGFloat {
        settings.resolvedCompactVerticalInset(islandHeight: resolvedIslandHeight)
    }

    private var verticalInsetRange: ClosedRange<Double> {
        let range = settings.compactVerticalInsetRange(
            physicalNotchHeight: screenGeometry.physicalNotchHeight
        )
        return Double(range.lowerBound)...Double(range.upperBound)
    }

    private var resolvedVerticalInsetText: String {
        String(Int(resolvedVerticalInset.rounded()))
    }

    /// 「外侧间距」拖动即改耳朵到岛外侧边缘的间距，间距计入宽度预算，岛宽随之变化。
    private var outerInsetBinding: Binding<Double> {
        Binding(
            get: { Double(settings.resolvedCompactOuterInset()) },
            set: { settings.customCompactOuterInset = CGFloat($0) }
        )
    }

    private var resolvedOuterInsetText: String {
        String(Int(settings.resolvedCompactOuterInset().rounded()))
    }

    fileprivate var content: some View {
        VStack(alignment: .leading, spacing: SettingsHeaderLayout.cardSpacing) {
                SettingsCard {
                    AppearanceSliderRow(
                        title: NSLocalizedString("settings.appearance.width", comment: ""),
                        subtitle: compactWidthSubtitle,
                        value: widthBinding,
                        range: Double(minimumSelectableWidth)...Double(
                            IslandAppearanceConstraints.maximumCompactWidth
                        ),
                        valueText: "\(Int(resolvedLayout.bodyWidth.rounded()))"
                    )

                    AppearanceRowDivider()

                    AppearanceSliderRow(
                        title: NSLocalizedString("settings.appearance.earHeight", comment: ""),
                        subtitle: NSLocalizedString("settings.appearance.earHeight.description", comment: ""),
                        value: earHeightBinding,
                        range: Double(
                            IslandAppearanceConstraints.minimumCompactHeight
                        )...Double(
                            IslandAppearanceConstraints.maximumEarHeight
                        ),
                        valueText: resolvedEarHeightText
                    )

                    AppearanceRowDivider()

                    AppearanceSliderRow(
                        title: NSLocalizedString("settings.appearance.earVerticalInset", comment: ""),
                        subtitle: NSLocalizedString("settings.appearance.earVerticalInset.description", comment: ""),
                        value: verticalInsetBinding,
                        range: verticalInsetRange,
                        valueText: resolvedVerticalInsetText
                    )

                    AppearanceRowDivider()

                    AppearanceSliderRow(
                        title: NSLocalizedString("settings.appearance.outerInset", comment: ""),
                        subtitle: NSLocalizedString("settings.appearance.outerInset.description", comment: ""),
                        value: outerInsetBinding,
                        range: Double(
                            IslandAppearanceConstraints.minimumCompactOuterInset
                        )...Double(
                            IslandAppearanceConstraints.maximumCompactOuterInset
                        ),
                        valueText: resolvedOuterInsetText
                    )

                appearanceSafetyNote(
                    NSLocalizedString("settings.appearance.compactSafetyNote", comment: "")
                )
                .padding(.top, SettingsHeaderLayout.surroundingPadding)
            }
        }
    }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 28)
        }
        .settingsDetailScrolling()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
