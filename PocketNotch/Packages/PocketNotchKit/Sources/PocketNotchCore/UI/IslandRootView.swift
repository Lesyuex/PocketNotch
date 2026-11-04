import AppKit
import PocketNotchShared
import SwiftUI

/// 刘海 Island 的顶层组装容器。
///
/// 将原 `NotchContainerView`（708 行）拆分为：
/// - `IslandPhaseController` — 动画状态
/// - `IslandShapeLayer` — 背板渲染
/// - `IslandContentLayer` — 内容切换
/// - `IslandHoverController` — hover 追踪
/// - `IslandRootView`（本文件）— 组装以上各层
public struct IslandRootView: View {
    @Environment(\.notchHiddenIslandSize) private var notchHiddenIslandSize
    @Environment(\.notchPhysicalWidth) private var notchPhysicalWidth
    @Environment(\.notchContentTopInset) private var notchContentTopInset
    @Environment(\.notchContentSizeReporter) private var contentSizeReporter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: NotchViewModel
    @State private var phaseController: IslandPhaseController
    @State private var compactContentPreferredWidth: CGFloat?
    @State private var compactContentPreferenceVisible = false
    @State private var residentContentSuppressedByNotification = false
    @State private var selectedExpandedTab: ExpandedIslandTab = .now
    @State private var fileDragLocation: CGPoint?
    @State private var fpsMeter = AnimationFPSMeter()
    @ObservedObject private var interactionSettings: NotchInteractionSettings
    @ObservedObject private var appearanceSettings: IslandAppearanceSettings
    private let registry: ModuleRegistry
    private var expandedTabRequest: ExpandedTabRequestController
    @ObservedObject private var residentSettings: CompactResidentSettings
    @ObservedObject private var expandedTabSettings: ExpandedTabSettings
    @ObservedObject private var screenLockController: ScreenLockController

    public init(
        viewModel: NotchViewModel,
        registry: ModuleRegistry,
        appearanceSettings: IslandAppearanceSettings,
        residentSettings: CompactResidentSettings,
        expandedTabSettings: ExpandedTabSettings,
        expandedTabRequest: ExpandedTabRequestController,
        screenLockController: ScreenLockController
    ) {
        _viewModel = State(initialValue: viewModel)
        _phaseController = State(initialValue: IslandPhaseController(isExpanded: viewModel.isExpanded))
        _compactContentPreferredWidth = State(initialValue: nil)
        _interactionSettings = ObservedObject(wrappedValue: viewModel.interactionSettings)
        _appearanceSettings = ObservedObject(wrappedValue: appearanceSettings)
        self.registry = registry
        self.expandedTabRequest = expandedTabRequest
        _residentSettings = ObservedObject(wrappedValue: residentSettings)
        _expandedTabSettings = ObservedObject(wrappedValue: expandedTabSettings)
        _screenLockController = ObservedObject(wrappedValue: screenLockController)
    }

    public var body: some View {
        return VStack(spacing: 0) {
            Color.clear
                .frame(width: islandCanvasSize.width, height: islandCanvasSize.height)
            notificationSlot
        }
        .overlay(alignment: .top) {
            island
        }
        .frame(width: islandCanvasSize.width)
        .fixedSize(horizontal: false, vertical: true)
        .animation(
            compactTierResizeAnimation,
            value: residentSettings.isStockDisplayActiveForLayout
        )
        .animation(compactTierResizeAnimation, value: compactContentPreferredWidth)
        .environment(
            \.notchHiddenIslandSize,
            CGSize(
                width: compactLayout.bodyWidth,
                height: compactLayout.islandHeight
            )
        )
        .environment(
            \.islandCompactContentSize,
            CGSize(width: compactLayout.leadingContentWidth, height: compactLayout.contentHeight)
        )
        .environment(\.islandFileDragLocation, fileDragLocation)
        .background(sizeReporter)
        .onPreferenceChange(CompactIslandSuppressesResidentContentPreferenceKey.self) {
            residentContentSuppressedByNotification = $0
        }
        .onAppear {
            updateCompactContentVisibility(
                compactContentPreferenceVisible || screenLockController.phase != .unlocked
            )
        }
        .onChange(of: screenLockController.phase) { _, phase in
            updateCompactContentVisibility(
                compactContentPreferenceVisible || phase != .unlocked
            )
        }
        .onChange(of: viewModel.isExpanded) { _, isExpanded in
            if isExpanded {
                applyPendingExpandedTabRequest()
            }
            handleExpansionChange(isExpanded)
        }
        .onChange(of: expandedTabRequest.pendingTab) { _, _ in
            // 已是展开态时手动触发（如「此刻」页剪贴板标题区的激活按钮）也能即时切标签。
            guard viewModel.isExpanded else { return }
            applyPendingExpandedTabRequest()
        }
        .onChange(of: viewModel.state) { _, state in
            if state == .dragging {
                selectedExpandedTab = .transfer
            } else {
                fileDragLocation = nil
            }
        }
        .onChange(of: viewModel.isInteractionSuspended) { _, isSuspended in
            if isSuspended {
                phaseController.resetForSessionSuspension()
            }
        }
        .onChange(of: phaseController.isCompactPresentationReady) { _, isReady in
            if isReady, interactionSettings.isHoverTriggerEnabled {
                viewModel.setHoverRevealEnabled(true)
            } else if !isReady {
                viewModel.setHoverRevealEnabled(false)
            }
        }
        .onChange(of: interactionSettings.hoverRevealDelay) { _, _ in
            guard phaseController.isHovered, !viewModel.isExpanded else { return }
            viewModel.restartPendingHoverReveal()
        }
        .onChange(of: phaseController.expansionProgress) { _, _ in
            // 展开/收起动画每渲染一帧 progress 都会变化；这里逐帧喂给 FPS 采样器。
            fpsMeter.frame()
        }
        .onChange(of: phaseController.transition) { _, transition in
            // 背板 Spring 完成（.expanded）或完全收起（.compact）时结束采样。
            if transition == .expanded || transition == .compact {
                fpsMeter.end()
            }
        }
    }

    // MARK: - Island 主体

    private var island: some View {
        ZStack(alignment: .top) {
            islandShadow
            islandBody
        }
        .frame(width: islandCanvasSize.width, height: islandCanvasSize.height, alignment: .top)
    }

    private var islandBody: some View {
        ZStack(alignment: .top) {
            IslandShapeLayer(
                state: phaseController.backgroundState,
                metrics: backgroundMetrics,
                expansionProgress: phaseController.backgroundCurveProgress,
                compactMorphProgress: phaseController.compactMorphProgress,
                backgroundStyle: appearanceSettings.expandedBackgroundStyle,
                frostedRegion: appearanceSettings.expandedBackgroundFrostedRegion,
                liquidGlassMaterial: appearanceSettings.expandedLiquidGlassMaterial,
                glassCovered: !phaseController.usesExpandedGeometry
            )
            .modifier(IslandExpansionProgressObserver(
                progress: phaseController.backgroundCurveProgress,
                onFrame: { phaseController.reportAnimatedExpansionProgress($0) }
            ))
            .frame(width: backgroundRenderSize.width, height: backgroundRenderSize.height)
            .animation(islandResizeAnimation, value: phaseController.isHoverPreviewActive)
            .animation(islandMaterialAnimation, value: phaseController.phase)

            IslandContentLayer(
                residentSettings: residentSettings,
                phaseController: phaseController,
                selectedExpandedTab: $selectedExpandedTab,
                registry: registry,
                expandedTabSettings: expandedTabSettings,
                compactLayout: compactLayout,
                visualCanvasSize: islandVisualCanvasSize,
                expandedBackgroundSize: expandedBackgroundSize,
                expandedContentTopInset: expandedContentTopInset,
                minimalContentTopInset: minimalExpandedContentTopInset,
                isHoverPreviewActive: compactContentHoverPresentationActive,
                hoverSideHorizontalOffset: islandHoverSideHorizontalOffset,
                hoverSideVerticalOffset: islandHoverSideVerticalOffset,
                suppressesResidentCompactContent: compactContentPreferredWidth != nil
                    || residentContentSuppressedByNotification
                    || phaseController.holdsResidentCompactContentForTierShrink,
                reduceMotion: reduceMotion,
                isMinimalModeEnabled: interactionSettings.isMinimalModeEnabled,
                screenLockPhase: screenLockController.phase
            )
            .frame(
                width: islandVisualCanvasSize.width,
                height: islandVisualCanvasSize.height,
                alignment: .top
            )
            .mask(alignment: .top) {
                islandContentMask
            }
            .onPreferenceChange(CompactIslandContentVisiblePreferenceKey.self) { visible in
                compactContentPreferenceVisible = visible
                updateCompactContentVisibility(
                    visible || screenLockController.phase != .unlocked
                )
            }
            .onPreferenceChange(CompactIslandPreferredWidthPreferenceKey.self) { width in
                let nextPreferredWidth = width > 0 ? width : nil
                let previousTier = resolvedCompactTier(preferredContentWidth: compactContentPreferredWidth)
                let nextTier = resolvedCompactTier(preferredContentWidth: nextPreferredWidth)
                compactContentPreferredWidth = nextPreferredWidth

                if previousTier == .second, nextTier == .first {
                    phaseController.beginCompactTierShrink(reduceMotion: reduceMotion)
                } else if nextTier == .second {
                    phaseController.cancelCompactTierShrink()
                }
            }
        }
        .frame(
            width: islandPresentationCanvasSize.width,
            height: islandPresentationCanvasSize.height,
            alignment: .top
        )
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            IslandFileDragController(
                isEnabled: !viewModel.isInteractionSuspended
                    && !interactionSettings.isMinimalModeEnabled,
                isClickEnabled: interactionSettings.isClickEnabled
                    && phaseController.showsCompactContent,
                isDragSessionActive: viewModel.state == .dragging,
                accessibilityLabel: viewModel.isExpanded ? "收起 Island" : "展开 Island",
                onTargetChange: handleFileDragTargetChange,
                onDrop: handleFileDrop,
                onClick: viewModel.click
            )
            .frame(
                width: islandPresentationCanvasSize.width,
                height: islandPresentationCanvasSize.height
            )
        }
        .background {
            IslandHoverController(
                isEnabled: !viewModel.isInteractionSuspended,
                backgroundState: phaseController.backgroundState,
                backgroundMetrics: backgroundMetrics,
                expansionProgress: phaseController.backgroundCurveProgress,
                compactMorphProgress: phaseController.compactMorphProgress
            ) { isHovered in
                updateIslandHover(isHovered)
            }
        }
        .animation(expandedPageResizeAnimation, value: expandedBackgroundSize)
        .environment(\.islandCollapseAction, {
            viewModel.collapseToIdle()
        })
        .environment(
            \.islandExpandedContentInteraction,
            IslandExpandedContentInteraction(
                begin: { viewModel.beginExpandedContentInteraction() },
                end: { viewModel.endExpandedContentInteraction() }
            )
        )
    }

    private func handleFileDragTargetChange(_ location: CGPoint?) {
        fileDragLocation = location
        if location != nil {
            selectedExpandedTab = .transfer
            viewModel.beginDragging()
        }
    }

    /// 展开开始时消费模块发出的标签请求，把展开页切到对应标签。
    /// 文件拖拽已显式指定 `.transfer`，优先级更高，不参与请求消费。
    private func applyPendingExpandedTabRequest() {
        guard viewModel.state != .dragging else { return }
        guard let tab = expandedTabRequest.consume() else { return }
        guard expandedTabSettings.isEnabled(tab) else { return }
        selectedExpandedTab = tab
    }

    private func handleFileDrop(_ urls: [URL], at location: CGPoint) -> Bool {
        defer { viewModel.endDragging() }
        for module in registry.modules where module.expandedIslandTab == .transfer {
            if module.handleFileDrop(urls, at: location) {
                return true
            }
        }
        return false
    }

    // MARK: - 通知槽

    @ViewBuilder
    private var notificationSlot: some View {
        if !viewModel.isExpanded, screenLockController.phase == .unlocked {
            ZStack(alignment: .top) {
                ForEach(Array(registry.modules.indices.reversed()), id: \.self) { index in
                    registry.modules[index].notificationView()
                }
            }
        }
    }

    // MARK: - 内容遮罩

    private var islandContentMask: some View {
        islandShape
            .fill(PocketNotchTheme.background)
            .frame(width: backgroundRenderSize.width, height: backgroundRenderSize.height)
            .frame(
                width: islandVisualCanvasSize.width,
                height: islandVisualCanvasSize.height,
                alignment: .top
            )
            .animation(islandResizeAnimation, value: phaseController.isHoverPreviewActive)
    }

    // MARK: - 阴影与光晕

    @ViewBuilder
    private var islandShadow: some View {
        // 黑色剪影只属于标准纯黑岛（它是阴影的载体）；材质类样式不垫黑，
        // 否则玻璃/毛玻璃透明时会直接透出这块黑——与设置预览同规则。
        if appearanceSettings.expandedBackgroundStyle == .standard {
            islandShadowSurface
                .frame(width: backgroundRenderSize.width, height: backgroundRenderSize.height)
                .frame(width: islandCanvasSize.width, height: islandCanvasSize.height, alignment: .top)
                .mask {
                    IslandTopEdgeEffectMask()
                }
                .animation(islandResizeAnimation, value: phaseController.isHoverPreviewActive)
                .animation(islandMaterialAnimation, value: phaseController.phase)
                .allowsHitTesting(false)
        }
    }

    private var islandShadowSurface: some View {
        islandShape
            .fill(PocketNotchTheme.background)
            .shadow(
                color: PocketNotchTheme.islandShadowColor.opacity(islandShadowStyle.opacity),
                radius: islandShadowStyle.radius,
                x: 0,
                y: islandShadowStyle.offsetY
            )
            .shadow(
                color: PocketNotchTheme.islandShadowColor.opacity(islandAmbientShadowStyle.opacity),
                radius: islandAmbientShadowStyle.radius,
                x: 0,
                y: islandAmbientShadowStyle.offsetY
            )
            .allowsHitTesting(false)
    }

    // MARK: - 尺寸上报

    private var sizeReporter: some View {
        GeometryReader { proxy in
            Color.clear
                .onChange(of: proxy.size) { _, size in
                    reportSize(totalSize: size)
                }
                .onChange(of: islandCanvasSize) { _, _ in
                    reportSize(totalSize: proxy.size)
                }
                .onChange(of: phaseController.usesExpandedGeometry) { _, _ in
                    reportSize(totalSize: proxy.size)
                }
                .onAppear {
                    reportSize(totalSize: proxy.size)
                }
        }
        .allowsHitTesting(false)
    }

    private func reportSize(totalSize: CGSize) {
        contentSizeReporter?.report(
            totalSize,
            islandCanvasSize: islandCanvasSize,
            interactiveSize: islandPresentationCanvasSize,
            usesExpandedIslandCanvas: phaseController.usesExpandedGeometry
        )
    }

    // MARK: - 形状

    private var islandShape: NotchShape {
        NotchShape(
            state: phaseController.backgroundState,
            metrics: backgroundMetrics,
            expansionProgress: phaseController.backgroundCurveProgress,
            compactMorphProgress: phaseController.compactMorphProgress,
            rendersInFullBounds: true
        )
    }

    // MARK: - 尺寸计算

    private var compactBackgroundSize: CGSize {
        IslandBackgroundPath.size(for: .hidden, metrics: backgroundMetrics)
    }

    private var compactHoverExpandedBackgroundSize: CGSize {
        CGSize(
            width: compactBackgroundSize.width + PocketNotchTheme.islandHoverExpansion.width,
            height: compactBackgroundSize.height + PocketNotchTheme.islandHoverExpansion.height
        )
    }

    private var expansionEntryBackgroundSize: CGSize {
        guard phaseController.isHoverPreviewActive else {
            return visibleBackgroundSize
        }
        return CGSize(
            width: max(visibleBackgroundSize.width, compactHoverExpandedBackgroundSize.width),
            height: max(visibleBackgroundSize.height, compactHoverExpandedBackgroundSize.height)
        )
    }

    private var expandedBackgroundSize: CGSize {
        IslandBackgroundPath.size(for: .expanded, metrics: backgroundMetrics)
    }

    private var currentSize: CGSize {
        let progress = min(max(phaseController.expansionProgress, 0), 1)
        let startSize = phaseController.expansionStartSize ?? compactBackgroundSize
        return CGSize(
            width: startSize.width
                + (expandedBackgroundSize.width - startSize.width) * progress,
            height: startSize.height
                + (expandedBackgroundSize.height - startSize.height) * progress
        )
    }

    private var visibleBackgroundSize: CGSize {
        // 回弹挤压的谷底不允许低于灵动态高度：低于时岛底边上移、compact
        // 内容被 mask 裁切，穿帮。挤压只吃收起途中的高度余量——几何尚高于
        // 灵动高度时仍能看到纵向压缩，几何到位后高度被钳在灵动高度，
        // 纵向的 Q 弹感由过冲拉伸（> 1）保留。
        let height = max(
            currentSize.height * islandHoverScale.height
                * phaseController.compactBounceHeightScale
                * phaseController.compactTierBounceHeightScale,
            compactBackgroundSize.height
        )
        return CGSize(
            width: currentSize.width * islandHoverScale.width
                * phaseController.compactBounceWidthScale
                * phaseController.compactTierBounceWidthScale,
            height: height
        )
    }

    private var backgroundRenderSize: CGSize {
        visibleBackgroundSize
    }

    private var islandCanvasSize: CGSize {
        let stableCanvasBackgroundSize = phaseController.usesExpandedGeometry
            ? expandedBackgroundSize
            : compactBackgroundSize
        return CGSize(
            width: max(stableCanvasBackgroundSize.width, fullCompactBackgroundSize.width)
                + PocketNotchTheme.islandHoverOutset * 2,
            height: stableCanvasBackgroundSize.height + PocketNotchTheme.islandHoverOutset
        )
    }

    private var fullCompactBackgroundSize: CGSize {
        IslandBackgroundPath.size(for: .hidden, metrics: fullCompactBackgroundMetrics)
    }

    private var islandVisualCanvasSize: CGSize {
        visibleBackgroundSize
    }

    private var islandPresentationCanvasSize: CGSize {
        phaseController.usesExpandedGeometry ? expandedBackgroundSize : compactInteractionCanvasSize
    }

    private var compactInteractionCanvasSize: CGSize {
        guard phaseController.isHoverPreviewActive else {
            return currentSize
        }
        return CGSize(
            width: currentSize.width + PocketNotchTheme.islandHoverExpansion.width,
            height: currentSize.height + PocketNotchTheme.islandHoverExpansion.height
        )
    }

    private var islandHoverScale: CGSize {
        guard phaseController.isHoverPreviewActive else { return CGSize(width: 1, height: 1) }
        return CGSize(
            width: (currentSize.width + PocketNotchTheme.islandHoverExpansion.width) / currentSize.width,
            height: (currentSize.height + PocketNotchTheme.islandHoverExpansion.height) / currentSize.height
        )
    }

    private var compactContentHoverPresentationActive: Bool {
        phaseController.isHoverPreviewActive || phaseController.preservesCompactHoverPresentation
    }

    private var islandHoverSideHorizontalOffset: CGFloat {
        compactContentHoverPresentationActive ? PocketNotchTheme.islandHoverExpansion.width / 2 : 0
    }

    private var islandHoverSideVerticalOffset: CGFloat {
        compactContentHoverPresentationActive ? PocketNotchTheme.islandHoverSideVerticalOffset : 0
    }

    // MARK: - Metrics

    private var restingBackgroundMetrics: IslandBackgroundMetrics {
        resolvedBackgroundMetrics(showsCompactContent: false)
    }

    private var dynamicBackgroundMetrics: IslandBackgroundMetrics {
        resolvedBackgroundMetrics(showsCompactContent: true)
    }

    private var backgroundMetrics: IslandBackgroundMetrics {
        IslandBackgroundMetrics.interpolated(
            from: restingBackgroundMetrics,
            to: dynamicBackgroundMetrics,
            progress: phaseController.compactMorphProgress
        )
    }

    private var fullCompactBackgroundMetrics: IslandBackgroundMetrics {
        dynamicBackgroundMetrics
    }

    private var preferredCompactWidth: CGFloat? {
        let configuredWidth = CompactIslandTier.resolvedPreferredWidth(
            appearanceSettings.customCompactWidth,
            stockDisplayActive: residentSettings.isStockDisplayActiveForLayout
        )
        guard let compactContentPreferredWidth else { return configuredWidth }
        return max(configuredWidth ?? 0, compactContentPreferredWidth)
    }

    /// 按给定临时内容宽度推算档位：用于在临时内容退场的那一刻，
    /// 判断岛宽是否真的从二档跌回一档（配置宽度或股票常驻可能仍留在二档）。
    private func resolvedCompactTier(preferredContentWidth: CGFloat?) -> CompactIslandTier {
        let configuredWidth = CompactIslandTier.resolvedPreferredWidth(
            appearanceSettings.customCompactWidth,
            stockDisplayActive: residentSettings.isStockDisplayActiveForLayout
        )
        let combinedWidth = max(configuredWidth ?? 0, preferredContentWidth ?? 0)
        return CompactIslandTier.resolved(
            forWidth: combinedWidth,
            stockDisplayActive: residentSettings.isStockDisplayActiveForLayout
        )
    }

    private var minimalContentAspectRatio: CGFloat? {
        guard interactionSettings.isMinimalModeEnabled else { return nil }
        return registry.modules
            .filter(\.supportsMinimalExpandedView)
            .compactMap(\.expandedMinimalContentAspectRatio)
            .first
    }

    private var minimalContentHeight: CGFloat? {
        guard minimalContentAspectRatio != nil else { return nil }
        return IslandLayoutToken.expandedMinimalContentMediaHeight
    }

    private var minimalContentFrameTopInset: CGFloat {
        IslandLayoutToken.expandedMinimalContentTopInset
            - minimalContentInternalTopInset
    }

    private var minimalContentInternalTopInset: CGFloat {
        guard interactionSettings.isMinimalModeEnabled else { return 0 }
        return registry.modules
            .first(where: { $0.supportsMinimalExpandedView })?
            .expandedMinimalContentInternalTopInset ?? 0
    }

    private var preferredExpandedContentWidth: CGFloat? {
        if let aspectRatio = minimalContentAspectRatio {
            return IslandLayoutToken.expandedMinimalContentMediaHeight * aspectRatio
                + IslandLayoutToken.expandedMinimalContentHorizontalInset * 2
                + IslandLayoutToken.expandedMinimalIslandWidthExpansion
        }
        return registry.modules
            .filter {
                $0.showsInExpandedPage && $0.expandedIslandTab == selectedExpandedTab
            }
            .compactMap(\.expandedPagePreferredContentWidth)
            .max()
    }

    private var preferredExpandedContentHeight: CGFloat? {
        if let contentHeight = minimalContentHeight {
            return contentHeight
        }
        // 此刻页由快照布局整体构成，内容高度由该页自己维护。
        if selectedExpandedTab == .now {
            return IslandLayoutToken.expandedNowPageContentHeight
        }
        return registry.modules
            .filter {
                $0.showsInExpandedPage && $0.expandedIslandTab == selectedExpandedTab
            }
            .compactMap(\.expandedPagePreferredContentHeight)
            .max()
    }

    private var minimumExpandedContentHeight: CGFloat {
        minimalContentHeight ?? IslandLayoutToken.expandedContentHeight
    }

    private func resolvedBackgroundMetrics(showsCompactContent: Bool) -> IslandBackgroundMetrics {
        IslandBackgroundMetrics.resolved(
            hiddenIslandSize: notchHiddenIslandSize,
            notchPhysicalWidth: notchPhysicalWidth,
            expandedModuleCount: registry.modules.count,
            showsCompactContent: showsCompactContent,
            preferredRestingHeight: appearanceSettings.customRestingHeight,
            preferredRestingWidth: appearanceSettings.customRestingWidth,
            preferredCompactOuterInset: appearanceSettings.resolvedCompactOuterInset(),
            preferredCompactVerticalInset: nil,
            preferredEarHeight: appearanceSettings.customEarHeight,
            preferredCompactWidth: preferredCompactWidth,
            preferredExpandedContentHeight: preferredExpandedContentHeight,
            preferredExpandedTotalHeight: nowPageExpandedTotalHeight,
            preferredExpandedContentWidth: preferredExpandedContentWidth,
            minimumExpandedContentHeight: minimumExpandedContentHeight,
            expandedContentTopInset: minimalContentAspectRatio != nil
                ? minimalContentFrameTopInset
                : IslandLayoutToken.expandedContentTopInset,
            expandedContentBottomInset: minimalContentAspectRatio != nil
                ? IslandLayoutToken.expandedMinimalContentBottomInset
                : IslandLayoutToken.expandedContentVerticalInset
        )
    }

    /// 此刻页整窗总高固定为 168（标签栏 32 + 卡片画布 136），隐藏态高度不必参与推算。
    private var nowPageExpandedTotalHeight: CGFloat? {
        if selectedExpandedTab == .now, minimalContentHeight == nil {
            return IslandLayoutToken.expandedNowPageTotalHeight
        }
        return nil
    }

    /// 隐藏态与灵动态共用的岛体高度：隐藏态的用户高度值同样决定灵动态岛高。
    private var resolvedIslandHeight: CGFloat {
        appearanceSettings.resolvedIslandHeight(
            physicalNotchHeight: notchPhysicalWidth > 0 ? notchHiddenIslandSize.height : 0,
            defaultIslandHeight: notchHiddenIslandSize.height
        )
    }

    private var compactLayout: ResolvedCompactIslandLayout {
        let restingBodyWidth = IslandAppearanceConstraints.automaticRestingBodyWidth(
            physicalNotchWidth: notchPhysicalWidth
        )
        let islandHeight = resolvedIslandHeight
        let contentHeight = appearanceSettings.resolvedEarHeight()
        return ResolvedCompactIslandLayout.resolve(
            contentHeight: contentHeight,
            minimumIslandHeight: islandHeight,
            notchPhysicalWidth: notchPhysicalWidth,
            restingBodyWidth: restingBodyWidth,
            preferredCompactOuterInset: appearanceSettings.resolvedCompactOuterInset(),
            preferredCompactVerticalInset: appearanceSettings.resolvedCompactVerticalInset(
                islandHeight: islandHeight
            ),
            preferredCompactWidth: preferredCompactWidth,
            fitsAutomaticContentToMinimumHeight: false
        )
    }

    private var expandedContentTopInset: CGFloat {
        max(
            max(max(notchContentTopInset, notchHiddenIslandSize.height), backgroundMetrics.hiddenHeight),
            34
        ) + IslandLayoutToken.expandedContentTopInset
    }

    private var minimalExpandedContentTopInset: CGFloat {
        backgroundMetrics.hiddenHeight + minimalContentFrameTopInset
    }

    private var notchClickTargetSize: CGSize {
        if !phaseController.showsCompactContent {
            let fallbackWidth = min(backgroundMetrics.hiddenWidth, 240)
            let width = notchPhysicalWidth > 0 ? notchPhysicalWidth : fallbackWidth
            return CGSize(
                width: min(max(width, 180), currentSize.width),
                height: max(notchHiddenIslandSize.height, 34)
            )
        }
        return compactInteractionCanvasSize
    }

    // MARK: - 动画

    private var islandResizeAnimation: Animation {
        guard !reduceMotion else { return PocketNotchTheme.islandReducedMotionAnimation }
        switch phaseController.phase {
        case .hover:
            return PocketNotchTheme.islandHoverAnimation
        case .expanding:
            return PocketNotchTheme.islandExpandBackgroundAnimation
        case .interactive, .expanded:
            return PocketNotchTheme.islandInteractiveSettleAnimation
        case .collapsing:
            return PocketNotchTheme.islandCollapseBackgroundAnimation
        case .hidden, .idle:
            return PocketNotchTheme.islandHoverExitAnimation
        }
    }

    private var compactTierResizeAnimation: Animation {
        reduceMotion
            ? PocketNotchTheme.islandReducedMotionAnimation
            : PocketNotchTheme.islandCompactTierResizeAnimation
    }

    private var expandedPageResizeAnimation: Animation? {
        reduceMotion ? nil : PocketNotchTheme.islandExpandedPageResizeAnimation
    }

    private var islandMaterialAnimation: Animation {
        guard !reduceMotion else { return PocketNotchTheme.islandReducedMotionAnimation }
        switch phaseController.phase {
        case .hover:
            return PocketNotchTheme.islandHoverMaterialAnimation
        case .expanding, .expanded, .interactive:
            return PocketNotchTheme.islandInteractiveSettleAnimation
        case .collapsing:
            return PocketNotchTheme.islandCollapseMaterialAnimation
        case .hidden, .idle:
            return PocketNotchTheme.islandHoverExitAnimation
        }
    }

    private var islandShadowStyle: IslandShadowStyle {
        IslandMaterialToken.shadowStyle(
            for: phaseController.phase,
            compactMorphProgress: phaseController.compactMorphProgress,
            isFloatingIsland: notchPhysicalWidth <= 0
        )
    }

    private var islandAmbientShadowStyle: IslandShadowStyle {
        IslandMaterialToken.ambientShadowStyle(
            for: phaseController.phase,
            compactMorphProgress: phaseController.compactMorphProgress,
            isFloatingIsland: notchPhysicalWidth <= 0
        )
    }

    // MARK: - 事件处理

    private func updateIslandHover(_ isHovered: Bool) {
        guard !viewModel.isInteractionSuspended else { return }
        guard isHovered != phaseController.isHovered else { return }
        phaseController.isHovered = isHovered
        if phaseController.isHoverPreviewActive {
            performHoverHapticFeedback()
        }
        viewModel.hoverChanged(isHovered)
    }

    private func performHoverHapticFeedback() {
        guard interactionSettings.hoverHapticIntensity != .none else { return }

        // `.alignment` 与 `.generic` 在很多触控板上几乎不可感知（用户反馈弱、中无效果），
        // 因此统一使用可感知的 `.levelChange` 模式，并通过触发次数区分强度。
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch interactionSettings.hoverHapticIntensity {
        case .none:
            break
        case .light:
            performer.perform(.levelChange, performanceTime: .drawCompleted)
        case .medium:
            performer.perform(.levelChange, performanceTime: .drawCompleted)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .levelChange,
                    performanceTime: .drawCompleted
                )
            }
        case .strong:
            performer.perform(.levelChange, performanceTime: .drawCompleted)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .levelChange,
                    performanceTime: .drawCompleted
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .levelChange,
                    performanceTime: .drawCompleted
                )
            }
        }
    }

    private func handleExpansionChange(_ isExpanded: Bool) {
        if viewModel.isInteractionSuspended {
            phaseController.resetForSessionSuspension()
            return
        }
        viewModel.setHoverRevealEnabled(false)
        if isExpanded {
            fpsMeter.begin(.expanding)
            phaseController.beginExpansion(
                from: expansionEntryBackgroundSize,
                reduceMotion: reduceMotion
            )
        } else {
            fpsMeter.begin(.collapsing)
            phaseController.beginCollapse(
                compactBackgroundSize: compactBackgroundSize,
                reduceMotion: reduceMotion
            )
        }
    }

    private func updateCompactContentVisibility(_ visible: Bool) {
        guard visible != phaseController.hasCompactModuleContent else { return }
        phaseController.setCompactModuleContentVisible(
            visible,
            reduceMotion: reduceMotion
        )
    }

}
