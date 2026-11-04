import PocketNotchShared
import SwiftUI

/// compact 与 expanded 内容的切换层。
///
/// 由 `IslandPhaseController` 的阶段驱动显隐和动画，
/// 不持有任何独立的展开/收起中间状态。
struct IslandContentLayer: View {
    @ObservedObject var residentSettings: CompactResidentSettings
    @State private var presentedResidentModuleID: String?
    @State private var residentModuleOpacity: CGFloat = 1
    @State private var residentModuleSwitchTask: Task<Void, Never>?
    @State private var handoffSourceFrames: [String: CGRect] = [:]
    @State private var handoffDestinationFrames: [String: CGRect] = [:]
    let phaseController: IslandPhaseController
    @Binding var selectedExpandedTab: ExpandedIslandTab
    let registry: ModuleRegistry
    @ObservedObject var expandedTabSettings: ExpandedTabSettings
    let compactLayout: ResolvedCompactIslandLayout
    let visualCanvasSize: CGSize
    let expandedBackgroundSize: CGSize
    let expandedContentTopInset: CGFloat
    let minimalContentTopInset: CGFloat
    let isHoverPreviewActive: Bool
    let hoverSideHorizontalOffset: CGFloat
    let hoverSideVerticalOffset: CGFloat
    let suppressesResidentCompactContent: Bool
    let reduceMotion: Bool
    let isMinimalModeEnabled: Bool
    let screenLockPhase: ScreenLockPhase

    private var showsScreenLockIndicator: Bool {
        screenLockPhase != .unlocked
    }

    var body: some View {
        return Color.clear
            .frame(width: visualCanvasSize.width, height: visualCanvasSize.height)
            .overlay(alignment: .top) {
                compactContent
                    .frame(
                        width: visualCanvasSize.width,
                        height: visualCanvasSize.height,
                        alignment: .top
                    )
                    .opacity(compactPresentationOpacity)
                    .scaleEffect(compactPresentationScale)
                    .offset(y: compactContentOffsetY)
                    .allowsHitTesting(phaseController.isCompactPresentationReady)
                    .animation(compactContentAnimation, value: phaseController.showsCompactContent)
                    .animation(resizeAnimation, value: isHoverPreviewActive)
            }
            .overlay(alignment: .top) {
                if phaseController.usesExpandedGeometry {
                    expandedContent
                        .compositingGroup()
                        .modifier(expandedContentAppearance)
                        .allowsHitTesting(phaseController.showsExpandedContent)
                        .accessibilityHidden(!phaseController.showsExpandedContent)
                }
            }
            .overlay {
                handoffTravelerView
            }
            .onAppear {
                presentedResidentModuleID = residentModulePresentationID
            }
            .onChange(of: residentModulePresentationID) { previousID, nextID in
                handOffResidentModule(from: previousID, to: nextID)
            }
            .onDisappear {
                residentModuleSwitchTask?.cancel()
                residentModuleSwitchTask = nil
            }
            .coordinateSpace(name: IslandHandoffSpace.coordinateSpaceName)
            .onPreferenceChange(IslandHandoffSourceFrameKey.self) {
                guard isHandoffFrameCollectionRelevant else { return }
                handoffSourceFrames = $0
            }
            .onPreferenceChange(IslandHandoffDestinationFrameKey.self) {
                guard isHandoffFrameCollectionRelevant else { return }
                handoffDestinationFrames = $0
            }
            .environment(\.islandHandoffProgress, contentHandoffProgress)
    }

    private var residentModuleID: String {
        switch residentSettings.activeModule {
        case .none: "systemStats"
        case .stocks: "stocks"
        case .media: "media"
        case .weather: "weather"
        }
    }

    private var residentModulePresentationID: String {
        registry.modules.contains {
            $0.id == residentModuleID && $0.isCompactModuleEnabled
        } ? residentModuleID : "none"
    }

    private var visibleResidentModuleID: String {
        presentedResidentModuleID ?? residentModulePresentationID
    }

    /// 同区临时互斥：返回「当前有可见临时且优先级最高」的模块索引；无临时返回 -1。
    @MainActor
    private func topTransientIndex() -> Int {
        var bestIndex = -1
        var bestPriority = Int.min
        for (index, module) in registry.modules.enumerated() {
            guard let priority = module.transientVisualPriority() else { continue }
            if priority > bestPriority {
                bestPriority = priority
                bestIndex = index
            }
        }
        return bestIndex
    }

    // MARK: - Compact

    private var compactContent: some View {
        let transientIndex = topTransientIndex()
        return CompactIslandLayout(
            layout: compactLayout,
            sideHorizontalOffset: hoverSideHorizontalOffset,
            sideVerticalOffset: hoverSideVerticalOffset,
            left: {
                ZStack(alignment: .leading) {
                    if showsScreenLockIndicator {
                        IslandScreenLockIndicator(phase: screenLockPhase)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .asymmetric(
                                        insertion: .scale(scale: 0.62).combined(with: .opacity),
                                        removal: .scale(scale: 0.86).combined(with: .opacity)
                                    )
                            )
                    } else {
                        if visibleResidentModuleID != "none",
                           let module = registry.modules.first(where: {
                               $0.id == visibleResidentModuleID
                           }) {
                            module.hiddenLeadingView()
                                .id("\(visibleResidentModuleID)-leading")
                                .opacity(residentModuleOpacity)
                                .opacity(suppressesResidentCompactContent ? 0 : 1)
                                .animation(
                                    suppressesResidentCompactContent
                                        ? nil
                                        : residentContentRevealAnimation,
                                    value: suppressesResidentCompactContent
                                )
                        }

                        // 只创建当前胜出的临时视图。opacity(0) 的 SwiftUI 视图仍会提交
                        // preference，可能错误改变岛宽或压制常驻音乐。
                        ForEach(Array(registry.modules.indices.reversed()), id: \.self) { index in
                            if transientIndex == index {
                                registry.modules[index].compactNotificationLeadingView()
                            }
                        }
                    }
                }
                .animation(
                    reduceMotion
                        ? PocketNotchTheme.islandReducedMotionAnimation
                        : PocketNotchTheme.islandScreenLockAnimation,
                    value: showsScreenLockIndicator
                )
            },
            right: {
                ZStack(alignment: .trailing) {
                    if !showsScreenLockIndicator {
                        if visibleResidentModuleID != "none",
                           let module = registry.modules.first(where: {
                               $0.id == visibleResidentModuleID
                           }) {
                            module.hiddenTrailingView()
                                .id("\(visibleResidentModuleID)-trailing")
                                .opacity(residentModuleOpacity)
                                .opacity(suppressesResidentCompactContent ? 0 : 1)
                                .animation(
                                    suppressesResidentCompactContent
                                        ? nil
                                        : residentContentRevealAnimation,
                                    value: suppressesResidentCompactContent
                                )
                        }

                        ForEach(Array(registry.modules.indices.reversed()), id: \.self) { index in
                            if transientIndex == index {
                                registry.modules[index].compactNotificationTrailingView()
                            }
                        }
                    }
                }
                .animation(
                    reduceMotion
                        ? PocketNotchTheme.islandReducedMotionAnimation
                        : PocketNotchTheme.islandScreenLockAnimation,
                    value: showsScreenLockIndicator
                )
            }
        )
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        ExpandedIslandPage(
            selectedTab: $selectedExpandedTab,
            modules: registry.modules,
            tabSettings: expandedTabSettings,
            contentTopInset: expandedContentTopInset,
            contentBottomInset: IslandLayoutToken.expandedContentVerticalInset,
            minimalContentTopInset: minimalContentTopInset,
            isMinimalModeEnabled: isMinimalModeEnabled
        )
            .frame(
                width: expandedBackgroundSize.width,
                height: expandedBackgroundSize.height,
                alignment: .top
            )
    }

    // MARK: - 内容接力（compact 耳 ⇆ 此刻页）

    private var contentHandoffDescriptor: IslandContentHandoffDescriptor? {
        registry.modules.compactMap { $0.contentHandoffDescriptor }.first
    }

    private var isContentHandoffEligible: Bool {
        guard !reduceMotion, !isMinimalModeEnabled, selectedExpandedTab == .now else {
            return false
        }
        guard let descriptor = contentHandoffDescriptor else { return false }
        guard handoffSourceFrames[descriptor.id] != nil,
              handoffDestinationFrames[descriptor.id] != nil else { return false }
        // 只有常驻耳正是接力模块自身、且未被临时通知压制时，封面才真的在耳内。
        guard visibleResidentModuleID == descriptor.id,
              !suppressesResidentCompactContent else { return false }
        return descriptor.isEligible()
    }

    /// 接力进度：`nil` = 无接力。展开与收起共用同一函数（h 随 expansionProgress
    /// 正反向变化），中途反向时接力沿原路退回，天然连续可逆。
    /// 常规收起（展开已完成）不接力——页面封面交给背板 mask 吞没，沿用原编排。
    /// 打断收起在背板收拢完成（p 归零）时即结束接力：副本在收缩尾段淡出归位，
    /// 挤压回弹全程不再有任何逐帧接力开销，也不会被收窄的背板 mask 裁切。
    private var contentHandoffProgress: CGFloat? {
        guard isContentHandoffEligible else { return nil }
        switch phaseController.transition {
        case .expanding:
            return clampedHandoffProgress
        case .collapsing where phaseController.interruptsInFlightHandoff:
            let progress = clampedHandoffProgress
            return progress <= 0.001 ? nil : progress
        default:
            return nil
        }
    }

    private var clampedHandoffProgress: CGFloat {
        min(
            max(
                phaseController.observedExpansionProgress
                    / IslandContentHandoffToken.flightProgressSpan,
                0
            ),
            1
        )
    }

    /// 接力 frame 收集的相关性门控：只在接力可能活跃的过渡期收集。
    /// 回弹段（接力已结束、环境值为 nil）画布仍在逐帧弹跳，两端 frame 在
    /// 画布空间逐帧漂移，无门控会触发逐帧 preference 往返与层重算，
    /// 白白吃掉高刷帧预算。
    private var isHandoffFrameCollectionRelevant: Bool {
        switch phaseController.transition {
        case .expanding:
            return true
        case .collapsing:
            return phaseController.interruptsInFlightHandoff && contentHandoffProgress != nil
        default:
            return false
        }
    }

    private func handoffTravelerOpacity(progress h: CGFloat) -> CGFloat {
        let destinationWindow = IslandContentHandoffToken.destinationFadeWindow
        let sourceWindow = IslandContentHandoffToken.sourceFadeWindow
        switch phaseController.transition {
        case .expanding:
            if h <= 0 { return 0 }
            if h < sourceWindow { return h / sourceWindow }
            if h > 1 - destinationWindow { return (1 - h) / destinationWindow }
            return 1
        case .collapsing:
            // 与展开方向完全对称：目的端起飞淡入、源端归位淡出。
            // 源端淡出发生在背板收缩的最后一段（h<0.12 ≈ 30-50ms），
            // 岛体高速运动中归位入黑，无可见消失感。
            if h > 1 - destinationWindow { return (1 - h) / destinationWindow }
            if h < sourceWindow { return h / sourceWindow }
            return 1
        default:
            return 0
        }
    }

    private var handoffTraveler: IslandHandoffTravelerRenderModel? {
        guard let descriptor = contentHandoffDescriptor,
              let source = handoffSourceFrames[descriptor.id],
              let destination = handoffDestinationFrames[descriptor.id],
              let h = contentHandoffProgress,
              destination.width > 0, destination.height > 0 else { return nil }
        let opacity = handoffTravelerOpacity(progress: h)
        guard opacity > 0.001 else { return nil }

        // smoothstep：起步慢、临近落位慢，飞行路径始终待在背板轮廓内不被 mask 裁切。
        let t = h * h * (3 - 2 * h)
        func lerp(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
            from + (to - from) * t
        }
        let renderSize = CGSize(
            width: lerp(source.width, destination.width),
            height: lerp(source.height, destination.height)
        )
        let radius = lerp(
            descriptor.sourceCornerRadius(source.width),
            descriptor.destinationCornerRadius
        )
        // 副本按目的端尺寸构建、整体等比缩放；圆角会跟着缩放，反算构建用圆角
        // 使渲染结果恰好等于插值圆角。
        let scale = renderSize.width / destination.width
        let content = descriptor.destinationContent(
            destination.size,
            scale > 0 ? radius / scale : radius
        )

        return IslandHandoffTravelerRenderModel(
            content: content,
            intrinsicSize: destination.size,
            renderScale: scale,
            renderSize: renderSize,
            center: CGPoint(
                x: lerp(source.midX, destination.midX),
                y: lerp(source.midY, destination.midY)
            ),
            opacity: opacity
        )
    }

    @ViewBuilder
    private var handoffTravelerView: some View {
        if let traveler = handoffTraveler {
            traveler.content
                .frame(
                    width: traveler.intrinsicSize.width,
                    height: traveler.intrinsicSize.height
                )
                .scaleEffect(traveler.renderScale)
                .frame(
                    width: traveler.renderSize.width,
                    height: traveler.renderSize.height
                )
                .opacity(traveler.opacity)
                .position(x: traveler.center.x, y: traveler.center.y)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Animation

    private var compactContentOffsetY: CGFloat {
        guard !reduceMotion else { return 0 }
        return isHoverPreviewActive ? 1 : 0
    }

    /// compact 内容的整体退场不透明度。展开方向锁定到背板逐帧观测进度
    /// （先缩退、稍晚淡出，与展开页淡入对称、同源可逆）；收起方向维持原
    /// 编排——恢复时由 `showsCompactContent` 翻转驱动入场（见下方 animation 绑定）。
    private var compactPresentationOpacity: CGFloat {
        if phaseController.showsCompactContent { return 1 }
        if reduceMotion { return 0 }
        switch phaseController.transition {
        case .expanding:
            let p = min(max(phaseController.observedExpansionProgress, 0), 1)
            return max(0, 1 - max(p - 0.05, 0) / 0.25)
        default:
            return 0
        }
    }

    /// 展开时左右耳向中心退缩：从第 0 帧就随背板长开同步缩小（先动后隐，
    /// 读起来像被长开的背板吞回刘海，而不是原地凭空淡掉）。
    private var compactPresentationScale: CGFloat {
        guard !reduceMotion, !phaseController.showsCompactContent else { return 1 }
        guard phaseController.transition == .expanding else { return 1 }
        let p = min(max(phaseController.observedExpansionProgress, 0), 1)
        let retreat = 1 - PocketNotchTheme.islandCompactContentRetreatScale
        return 1 - retreat * min(p / 0.35, 1)
    }

    private var compactContentAnimation: Animation {
        guard !reduceMotion else { return PocketNotchTheme.islandReducedMotionAnimation }
        return phaseController.showsCompactContent
            ? PocketNotchTheme.islandCompactContentEnterAnimation
            : PocketNotchTheme.islandCompactContentExitAnimation
    }

    private func handOffResidentModule(from previousID: String, to nextID: String) {
        residentModuleSwitchTask?.cancel()

        let currentID = presentedResidentModuleID ?? previousID
        guard currentID != nextID else {
            withAnimation(residentModuleEnterAnimation) {
                residentModuleOpacity = 1
            }
            return
        }

        presentedResidentModuleID = currentID
        withAnimation(residentModuleExitAnimation) {
            residentModuleOpacity = 0
        }

        residentModuleSwitchTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: residentModuleExitDurationNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                presentedResidentModuleID = nextID
                residentModuleOpacity = 0
            }

            do {
                try await Task.sleep(
                    nanoseconds: PocketNotchTheme.islandCompactActivationDelayNanoseconds
                )
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(residentModuleEnterAnimation) {
                residentModuleOpacity = 1
            }
        }
    }

    private var residentModuleExitAnimation: Animation {
        reduceMotion
            ? PocketNotchTheme.islandReducedMotionAnimation
            : PocketNotchTheme.islandCompactResidentModuleExitAnimation
    }

    private var residentModuleEnterAnimation: Animation {
        reduceMotion
            ? PocketNotchTheme.islandReducedMotionAnimation
            : PocketNotchTheme.islandCompactResidentModuleEnterAnimation
    }

    /// 回归的常驻左右耳内容在档位回弹段浮现：与 compact 内容入场同一条 ease，
    /// 压制（临时内容接管）仍是瞬时，不做淡出，避免背后残影。
    private var residentContentRevealAnimation: Animation {
        reduceMotion
            ? PocketNotchTheme.islandReducedMotionAnimation
            : PocketNotchTheme.islandCompactContentEnterAnimation
    }

    private var residentModuleExitDurationNanoseconds: UInt64 {
        reduceMotion
            ? PocketNotchTheme.islandReducedMotionDurationNanoseconds
            : PocketNotchTheme.islandCompactResidentModuleExitDurationNanoseconds
    }

    private var expandedContentAppearance: ExpandedContentTransitionModifier {
        // 用逐帧观测进度（与左右耳退场、背板形变同一真源），展开页被背板
        // 「吞进放出」，而不是靠模型目标值各自抢跑。
        let progress = min(max(phaseController.observedExpansionProgress, 0), 1)
        switch phaseController.transition {
        case .expanding:
            // 展开入场与收起对称：插入首帧全透明，随背板长开从透明浮现。
            // 否则展开内容以不透明姿态插入，其顶部背景列（从 y=0 铺满全高）
            // 会压在仍在显示的左右耳上，造成展开瞬间左右耳闪一下。
            let opacity = min(max(progress / ExpandedContentExpandFadeSpan, 0), 1)
            return ExpandedContentTransitionModifier(opacity: opacity)
        case .collapsing:
            // 内容随背板同步被 mask 从底部吞回；仅在 mask 收缩到尾段时
            // 快速淡出，保证 `tryFinishCollapse` 原子卸载展开内容的瞬间全透明。
            let opacity = min(max(progress / ExpandedContentCollapseFadeSpan, 0), 1)
            return ExpandedContentTransitionModifier(opacity: opacity)
        case .compact, .expanded:
            return .identity
        }
    }

    private var resizeAnimation: Animation {
        guard !reduceMotion else { return PocketNotchTheme.islandReducedMotionAnimation }
        let phase = phaseController.phase
        switch phase {
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
}

/// 收起时内容的淡出跨度（expansionProgress 落到该值以下开始透明收尾）。
private let ExpandedContentCollapseFadeSpan: CGFloat = 0.3

/// 旅行副本的单帧渲染模型：内容按目的端尺寸构建，缩放/位移由 Core 逐帧插值。
private struct IslandHandoffTravelerRenderModel {
    let content: AnyView
    let intrinsicSize: CGSize
    let renderScale: CGFloat
    let renderSize: CGSize
    let center: CGPoint
    let opacity: CGFloat
}

/// 展开时内容的淡入跨度（expansionProgress 涨到该值之前从透明浮现）。
/// 与收起方向对称：插入首帧全透明，避免压住仍在显示的左右耳。
private let ExpandedContentExpandFadeSpan: CGFloat = 0.3

private struct ExpandedContentTransitionModifier: ViewModifier {
    static let identity = Self(opacity: 1)

    let opacity: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
    }
}
