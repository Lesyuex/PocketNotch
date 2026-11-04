import Observation
import SwiftUI

/// 三态动画的唯一状态真相来源。
///
/// 集中管理 `expansionProgress`、内容可见性、几何切换和动画编排，
/// 替代原 `NotchContainerView` 的 10+ 个分散 `@State`。
/// 视图层只读取属性并绑定动画，不再自行持有任何展开/收起中间状态。
@Observable
@MainActor
public final class IslandPhaseController {

    // MARK: - 外部只读状态

    /// 背板膨胀进度：0 = compact，1 = 完整展开。由 Spring 动画驱动。
    /// 注意：这是模型目标值，在 `withAnimation` 中一次到位；视图 body 逐帧
    /// 读到的是它而非插值。需要真实插值时使用 `observedExpansionProgress`。
    public private(set) var expansionProgress: CGFloat = 0

    /// 展开进度的逐帧观测值：来自视图层 Animatable 观察器的真实动画插值
    /// （含过冲）。回弹起跳时机与内容接力都以此为准——固定延迟在打断收起
    /// 的短行程下会造成「背景已停、回弹未起」的死区，Q 弹起跳发滞。
    public private(set) var observedExpansionProgress: CGFloat = 0

    /// 视图层逐帧回写观测进度（见 `IslandExpansionProgressObserver`）。
    public func reportAnimatedExpansionProgress(_ value: CGFloat) {
        guard abs(value - observedExpansionProgress) > 0.0005 else { return }
        observedExpansionProgress = value
    }

    /// 是否使用展开态几何（路径、画布、窗口全部按展开尺寸渲染）。
    /// 展开首帧原子切换为 true，收起 Spring 到达终点后切回 false。
    public private(set) var usesExpandedGeometry = false

    /// compact 内容是否可见。展开时先 fade out，收起完成后 fade in。
    public private(set) var showsCompactContent = true

    /// 展开页内容是否可见。compact 退出动画完成后入场，收起开始后退场。
    public private(set) var showsExpandedContent = false

    /// 展开膨胀的起始尺寸。从当前可见尺寸（含 Hover 膨胀）继续生长，
    /// 避免先回缩再展开。
    public private(set) var expansionStartSize: CGSize?

    public private(set) var transition: IslandPresentationTransition = .compact

    /// 本次收起是否打断了进行中的元素接力（展开未完成即收起）。
    /// 仅此时收起方向保留封面回飞与落位保持；常规收起完全沿用原编排，
    /// 避免页面封面早于背板 mask 吞没就消失。
    public private(set) var interruptsInFlightHandoff = false

    public private(set) var preservesCompactHoverPresentation = false

    /// 当前 Hover 状态，由 `IslandHoverController` 写入。
    public var isHovered = false

    /// 模块是否有 compact 内容可显示（决定 resting vs dynamic 形态）。
    public private(set) var hasCompactModuleContent = false

    /// compact 背板形变进度：0 = resting，1 = dynamic。与展开进度正交。
    public private(set) var compactMorphProgress: CGFloat = 0

    /// 收起回弹进度：0 = 挤压到底部，1 = 静止。过冲期间短暂 >1。
    /// 它只驱动叠加在几何之上的弹性通道，几何本身单程走向灵动宽度、从不折返。
    public private(set) var compactBounceProgress: CGFloat = 1

    /// 档位回缩（二档 → 一档）的挤压回弹进度：0 = 挤压到底，1 = 静止。
    /// 与收起回弹共用同一套压缩/回弹参数，叠加在档位几何之上。
    public private(set) var compactTierBounceProgress: CGFloat = 1

    /// 档位回缩期间是否按住常驻左右耳内容：压缩段按住不显示，
    /// 回弹拉伸段才放开，让回归的常驻内容骑着弹回一起出现。
    public private(set) var holdsResidentCompactContentForTierShrink = false

    /// 弹性通道的宽度比例。0→1 是挤压过程（squash & stretch 的 squash），
    /// 1 之后的过冲换算成可见的宽度拉伸，静止时收敛为 1。
    public var compactBounceWidthScale: CGFloat {
        if compactBounceProgress <= 1 {
            return PocketNotchTheme.islandCompactSquashWidthRatio
                + (1 - PocketNotchTheme.islandCompactSquashWidthRatio) * compactBounceProgress
        }
        return 1 + (compactBounceProgress - 1) * PocketNotchTheme.islandCompactBounceStretchGain
    }

    /// 高度方向的弹性比例，比宽度克制；顶部锚点始终固定。
    public var compactBounceHeightScale: CGFloat {
        if compactBounceProgress <= 1 {
            return PocketNotchTheme.islandCompactSquashHeightRatio
                + (1 - PocketNotchTheme.islandCompactSquashHeightRatio) * compactBounceProgress
        }
        return 1 + (compactBounceProgress - 1) * PocketNotchTheme.islandCompactBounceHeightStretchGain
    }

    /// 档位回缩弹性通道的宽度比例，压缩/回弹换算与收起回弹完全一致。
    public var compactTierBounceWidthScale: CGFloat {
        if compactTierBounceProgress <= 1 {
            return PocketNotchTheme.islandCompactSquashWidthRatio
                + (1 - PocketNotchTheme.islandCompactSquashWidthRatio) * compactTierBounceProgress
        }
        return 1 + (compactTierBounceProgress - 1) * PocketNotchTheme.islandCompactBounceStretchGain
    }

    /// 档位回缩弹性通道的高度比例，顶部锚点始终固定。
    public var compactTierBounceHeightScale: CGFloat {
        if compactTierBounceProgress <= 1 {
            return PocketNotchTheme.islandCompactSquashHeightRatio
                + (1 - PocketNotchTheme.islandCompactSquashHeightRatio) * compactTierBounceProgress
        }
        return 1 + (compactTierBounceProgress - 1) * PocketNotchTheme.islandCompactBounceHeightStretchGain
    }

    // MARK: - 回调

    /// 通知窗口控制器在状态边界变化时调整窗口 frame。
    @ObservationIgnored
    public var onWindowFrameChange: ((_ usesExpandedCanvas: Bool) -> Void)?

    // MARK: - 内部

    @ObservationIgnored private var presentationTask: Task<Void, Never>?
    @ObservationIgnored private var presentationGeneration = 0
    @ObservationIgnored private var collapseBackgroundDidFinish = false
    @ObservationIgnored private var compactContentRecoveryDidFinish = false
    @ObservationIgnored private var compactBouncePending = false
    @ObservationIgnored private var compactBounceDidFinish = false
    @ObservationIgnored private var isCompactActivationPending = false
    @ObservationIgnored private var compactBounceTask: Task<Void, Never>?
    @ObservationIgnored private var compactTierBounceTask: Task<Void, Never>?
    @ObservationIgnored private var usesReducedMotion = false
    @ObservationIgnored private var pendingCompactTierShrink = false
    @ObservationIgnored private var pendingCompactTierShrinkReduceMotion = false

    public init(isExpanded: Bool = false) {
        if isExpanded {
            expansionProgress = 1
            usesExpandedGeometry = true
            showsCompactContent = false
            showsExpandedContent = true
            transition = .expanded
        }
    }

    // MARK: - 派生属性

    /// 当前呈现阶段，由纯函数推导。视图按此选择动画曲线和材质参数。
    public var phase: IslandPresentationPhase {
        IslandPresentationStateMachine.phase(
            transition: transition,
            isHovered: isHoverPreviewActive,
            isExpandedContentVisible: showsExpandedContent
        )
    }

    /// compact 形态：无内容时为 resting，有内容时为 dynamic。
    public var compactForm: IslandCompactForm {
        IslandPresentationStateMachine.compactForm(
            showsCompactContent: hasCompactModuleContent
        )
    }

    public var isCompactPresentationReady: Bool {
        transition == .compact && !usesExpandedGeometry && showsCompactContent
    }

    /// 是否应在 Hover 时膨胀背板。展开、回缩和 compact 内容恢复期间不叠加 Hover scale。
    public var isHoverPreviewActive: Bool {
        isHovered && isCompactPresentationReady
    }

    /// 背板路径的曲率进度。仅完整展开/收起时在 0–1 间变化；
    /// 隐藏态与灵动态（含 Hover）始终保持收紧曲率。
    public var backgroundCurveProgress: CGFloat {
        usesExpandedGeometry ? expansionProgress : 0
    }

    /// 背板的目标状态枚举（供 `NotchShape` / `IslandBackgroundPath` 使用）。
    public var backgroundState: IslandBackgroundState {
        usesExpandedGeometry ? .expanded : .hidden
    }

    public func setCompactModuleContentVisible(_ visible: Bool, reduceMotion: Bool) {
        hasCompactModuleContent = visible
        let targetProgress: CGFloat = visible ? 1 : 0

        if reduceMotion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                compactMorphProgress = targetProgress
            }
        } else {
            withAnimation(PocketNotchTheme.islandCompactMorphAnimation) {
                compactMorphProgress = targetProgress
            }
        }
    }

    // MARK: - 档位回缩（二档 → 一档）

    /// 二档回缩到一档时复刻收起回弹：先用快弹簧把档位几何压向挤压底点，
    /// 在它仍向内运动时交给回弹弹簧，形成一次可见的 Q 弹。
    /// 压缩段按住回归的常驻左右耳内容，回弹拉伸段才放开。
    public func beginCompactTierShrink(reduceMotion: Bool = false) {
        guard transition == .compact else {
            pendingCompactTierShrink = true
            pendingCompactTierShrinkReduceMotion = reduceMotion
            return
        }
        pendingCompactTierShrink = false
        compactTierBounceTask?.cancel()

        if reduceMotion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                compactTierBounceProgress = 1
                holdsResidentCompactContentForTierShrink = false
            }
            return
        }

        holdsResidentCompactContentForTierShrink = true
        withAnimation(PocketNotchTheme.islandCompactTierShrinkAnticipationAnimation) {
            compactTierBounceProgress = 0
        }

        compactTierBounceTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: PocketNotchTheme.islandCompactBounceAnticipationDurationNanoseconds
            )
            guard !Task.isCancelled, let self, self.transition == .compact else { return }
            withAnimation(PocketNotchTheme.islandCompactTierShrinkBounceAnimation) {
                self.compactTierBounceProgress = 1
            }

            try? await Task.sleep(
                nanoseconds: PocketNotchTheme.islandCompactContentReboundRideDelayNanoseconds
            )
            guard !Task.isCancelled, self.transition == .compact else { return }
            self.holdsResidentCompactContentForTierShrink = false
        }
    }

    /// 档位重新升回二档（新的临时内容接管）时取消回缩编舞，
    /// 立即恢复静止弹性与常驻内容可见性，避免与新的展开抢跑。
    public func cancelCompactTierShrink() {
        compactTierBounceTask?.cancel()
        compactTierBounceTask = nil
        pendingCompactTierShrink = false
        guard compactTierBounceProgress != 1 || holdsResidentCompactContentForTierShrink else {
            return
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            compactTierBounceProgress = 1
            holdsResidentCompactContentForTierShrink = false
        }
    }

    /// 收起完成进入 `.compact` 后补播启动期间被暂存的档位回缩。
    private func flushPendingCompactTierShrink() {
        guard pendingCompactTierShrink else { return }
        pendingCompactTierShrink = false
        beginCompactTierShrink(reduceMotion: pendingCompactTierShrinkReduceMotion)
    }

    // MARK: - 展开

    /// 从当前可见尺寸开始展开动画。
    ///
    /// 1. 原子事务：记录起始尺寸、重置进度、切换到展开几何，并直接进入
    ///    `.expanding`（不再空等一拍——几何翻转与弹簧起步同一次提交，弹簧
    ///    从上一帧已渲染尺寸起步，连续无死区；与打断重开的分支完全一致）
    /// 2. 背板 Spring 动画：progress 0 → 1
    /// 3. compact 退出 + expanded 入场：由观测进度门控编排
    public func beginExpansion(
        from startSize: CGSize,
        reduceMotion: Bool = false
    ) {
        presentationTask?.cancel()
        compactBounceTask?.cancel()
        cancelCompactTierShrink()
        presentationGeneration &+= 1
        isCompactActivationPending = false
        interruptsInFlightHandoff = false
        let generation = presentationGeneration

        if reduceMotion {
            withAnimation(PocketNotchTheme.islandReducedMotionAnimation) {
                expansionStartSize = nil
                usesExpandedGeometry = true
                expansionProgress = 1
                showsCompactContent = false
                showsExpandedContent = true
                preservesCompactHoverPresentation = false
                transition = .expanded
            }
            onWindowFrameChange?(true)
            return
        }

        if usesExpandedGeometry {
            preservesCompactHoverPresentation = false
            transition = .expanding
            animateExpansion(generation: generation)
            scheduleExpandedContent(generation: generation)
            return
        }

        let shouldPreserveHoverPresentation = isHoverPreviewActive
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            expansionStartSize = startSize
            expansionProgress = 0
            usesExpandedGeometry = true
            showsExpandedContent = false
            preservesCompactHoverPresentation = shouldPreserveHoverPresentation
            transition = .expanding
        }

        onWindowFrameChange?(true)

        animateExpansion(generation: generation)
        scheduleExpandedContent(generation: generation)
    }

    private func animateExpansion(generation: Int) {
        withAnimation(
            PocketNotchTheme.islandCompactContentExitAnimation
        ) {
            showsCompactContent = false
        }

        withAnimation(
            PocketNotchTheme.islandExpandBackgroundAnimation,
            completionCriteria: .removed
        ) {
            expansionProgress = 1
        } completion: { [weak self] in
            guard let self,
                  self.presentationGeneration == generation,
                  self.transition == .expanding else { return }
            self.transition = .expanded
        }
    }

    /// 展开页入场跟随背板逐帧进度：观测进度越过阈值即入场（此时内容已被背板盖住），
    /// 弹簧参数再调也不与背景运动脱节；打断/短行程下进度已过阈值则立即入场，无死区。
    /// 兜底期限保证测试与异常环境下内容仍会出现。
    private func scheduleExpandedContent(generation: Int) {
        presentationTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(
                PocketNotchTheme.islandExpandedContentEnterDeadline
            )
            var isReady = false
            while !Task.isCancelled {
                guard let self else { return }
                guard self.presentationGeneration == generation,
                      self.transition == .expanding || self.transition == .expanded else { return }
                if self.observedExpansionProgress
                    >= PocketNotchTheme.islandExpandedContentEnterProgressThreshold
                    || Date() >= deadline {
                    isReady = true
                    break
                }
                try? await Task.sleep(nanoseconds: 8_000_000)
            }
            guard isReady, !Task.isCancelled, let self,
                  self.presentationGeneration == generation,
                  self.transition == .expanding || self.transition == .expanded else { return }

            self.preservesCompactHoverPresentation = false
            withAnimation(PocketNotchTheme.islandExpandedContentEnterAnimation) {
                self.showsExpandedContent = true
            }
        }
    }

    // MARK: - 收起

    /// 从展开态开始收起动画。
    ///
    /// 1. expanded 内容开始退场，背板短暂错峰后同步回缩
    /// 2. 背板回缩尾段恢复 compact 内容
    /// 3. 背景与内容均完成后原子切回 compact 几何
    public func beginCollapse(
        compactBackgroundSize: CGSize,
        reduceMotion: Bool = false
    ) {
        guard transition != .collapsing else { return }

        let transitionBeforeCollapse = transition
        let expandedContentWasVisible = showsExpandedContent
        guard transitionBeforeCollapse != .compact else { return }

        presentationTask?.cancel()
        compactBounceTask?.cancel()
        cancelCompactTierShrink()
        presentationGeneration &+= 1
        isCompactActivationPending = false
        let generation = presentationGeneration
        collapseBackgroundDidFinish = false
        compactContentRecoveryDidFinish = false
        compactBouncePending = hasCompactModuleContent
        compactBounceDidFinish = false
        usesReducedMotion = reduceMotion
        interruptsInFlightHandoff = transitionBeforeCollapse == .expanding
            && observedExpansionProgress < IslandContentHandoffToken.flightProgressSpan

        // 注意：此处不清除 preservesCompactHoverPresentation。打断展开的收起
        // 需要耳位锚点保持起飞时的 hover 偏移，旅行副本的归位路径才不会跳变；
        // 背板收拢完成后再清除（此时耳朵尚未恢复，偏移切换不可见）。
        transition = .collapsing

        if reduceMotion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showsExpandedContent = false
                expansionStartSize = nil
                usesExpandedGeometry = false
                expansionProgress = 0
                showsCompactContent = false
                preservesCompactHoverPresentation = false
            }
            collapseBackgroundDidFinish = true
            onWindowFrameChange?(false)
            startCompactContentRecovery(generation: generation)
            return
        }

        guard expandedContentWasVisible else {
            startCollapseBackground(
                compactBackgroundSize: compactBackgroundSize,
                generation: generation,
                recoverCompactContentImmediately: !compactBouncePending
            )
            return
        }

        // 内容不单独淡出：收起一开始背景就同步收缩，背板 mask 会把 expanded
        // 内容从底部逐行吞回，避免「内容先凭空消失、背景随后收缩」的割裂感。
        showsExpandedContent = false
        startCollapseBackground(
            compactBackgroundSize: compactBackgroundSize,
            generation: generation,
            recoverCompactContentImmediately: false
        )
    }

    private func startCollapseBackground(
        compactBackgroundSize: CGSize,
        generation: Int,
        recoverCompactContentImmediately: Bool
    ) {
        guard presentationGeneration == generation,
              transition == .collapsing else { return }

        // 几何单程走向目标形态，永不折返：有内容时直接走到灵动宽度，
        // 随后的 Q 弹全部交给叠加在几何之上的弹性通道，速度因此连续。
        expansionStartSize = nil
        guard expansionProgress > 0.001 else {
            collapseBackgroundDidFinish = true
            if compactBouncePending {
                startCompactBounce(generation: generation)
            } else {
                startCompactContentRecovery(generation: generation)
            }
            tryFinishCollapse(generation: generation)
            return
        }

        withAnimation(
            PocketNotchTheme.islandCollapseBackgroundAnimation,
            completionCriteria: .removed
        ) {
            expansionProgress = 0
            compactMorphProgress = compactBouncePending ? 1 : 0
        } completion: { [weak self] in
            self?.markCollapseBackgroundFinished(generation: generation)
        }

        if compactBouncePending {
            scheduleCompactBounce(generation: generation)
        } else if recoverCompactContentImmediately {
            startCompactContentRecovery(generation: generation)
        } else {
            scheduleCompactContentRecovery(generation: generation)
        }
    }

    /// 背板收拢到接近灵动宽度（观测进度低于阈值）后再启动弹性通道。
    /// 用逐帧观测进度而非固定延迟：常规与打断收起的背板行程不同，
    /// 固定延迟在打断路径会让背景早早停住、回弹迟迟不起，Q 弹起跳前出现死区。
    private func scheduleCompactBounce(generation: Int) {
        compactBounceTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(0.6)
            var isReady = false
            while !Task.isCancelled {
                guard let self else { return }
                guard self.presentationGeneration == generation,
                      self.transition == .collapsing else { return }
                if self.observedExpansionProgress <= Self.compactBounceStartProgressThreshold
                    || Date() >= deadline {
                    isReady = true
                    break
                }
                try? await Task.sleep(nanoseconds: 8_000_000)
            }
            guard isReady, !Task.isCancelled, let self,
                  self.presentationGeneration == generation,
                  self.transition == .collapsing else { return }
            self.startCompactBounce(generation: generation)
        }
    }

    /// 回弹起跳的观测进度阈值：背板收拢到该进度附近即开始挤压，
    /// 落点与旧固定 190ms 延迟在常规路径上一致。
    static let compactBounceStartProgressThreshold: CGFloat = 0.1

    /// 先用快弹簧把弹性通道压到挤压底点（anticipation），在它仍在向内运动时
    /// 交给回弹弹簧：弹簧带着向内速度起步，谷底更深、弹回更连贯，
    /// 不会出现「压到死再从零速度弹起」的机械断裂。
    /// 左右耳在回弹拉伸段入场（骑弹回复位），窗口切回 compact 画布仍等
    /// 回弹收敛，避免拉伸中的岛被窗框裁切。
    private func startCompactBounce(generation: Int) {
        guard presentationGeneration == generation,
              transition == .collapsing else { return }

        withAnimation(PocketNotchTheme.islandCompactBounceAnticipationAnimation) {
            compactBounceProgress = 0
        }

        compactBounceTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: PocketNotchTheme.islandCompactBounceAnticipationDurationNanoseconds
            )
            guard !Task.isCancelled,
                  let self,
                  self.presentationGeneration == generation,
                  self.transition == .collapsing else { return }
            withAnimation(
                PocketNotchTheme.islandCompactBounceAnimation,
                completionCriteria: .removed
            ) {
                self.compactBounceProgress = 1
            } completion: { [weak self] in
                guard let self,
                      self.presentationGeneration == generation,
                      self.transition == .collapsing else { return }
                self.compactBounceDidFinish = true
                self.tryFinishCollapse(generation: generation)
            }

            try? await Task.sleep(
                nanoseconds: PocketNotchTheme.islandCompactContentReboundRideDelayNanoseconds
            )
            guard !Task.isCancelled,
                  self.presentationGeneration == generation,
                  self.transition == .collapsing else { return }
            self.startCompactContentRecovery(generation: generation)
        }
    }

    private func scheduleCompactContentRecovery(generation: Int) {
        presentationTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: PocketNotchTheme.islandCompactContentRecoveryDelayNanoseconds
            )
            guard !Task.isCancelled,
                  let self,
                  self.presentationGeneration == generation,
                  self.transition == .collapsing else { return }
            self.startCompactContentRecovery(generation: generation)
        }
    }

    private func startCompactContentRecovery(generation: Int) {
        guard presentationGeneration == generation,
              transition == .collapsing else { return }
        guard !showsCompactContent else {
            compactContentRecoveryDidFinish = true
            tryFinishCollapse(generation: generation)
            return
        }

        let animation = usesExpandedGeometry
            ? PocketNotchTheme.islandCompactContentEnterAnimation
            : PocketNotchTheme.islandReducedMotionAnimation
        let duration = usesExpandedGeometry
            ? PocketNotchTheme.islandCompactContentRecoveryDurationNanoseconds
            : PocketNotchTheme.islandReducedMotionDurationNanoseconds
        withAnimation(animation) {
            showsCompactContent = true
        }
        presentationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: duration)
            guard !Task.isCancelled else { return }
            self?.markCompactContentRecoveryFinished(generation: generation)
        }
    }

    private func markCollapseBackgroundFinished(generation: Int) {
        guard presentationGeneration == generation,
              transition == .collapsing else { return }
        collapseBackgroundDidFinish = true
        // 背板收拢完成：清除 hover 呈现锚点（打断收起的接力此时也已结束，
        // 耳朵尚未恢复，偏移切换不可见）。
        preservesCompactHoverPresentation = false
        // 有内容时还要等弹性通道收敛（左右耳在回弹拉伸段入场，
        // 窗口切回仍等回弹收敛）。
        tryFinishCollapse(generation: generation)
    }

    private func markCompactContentRecoveryFinished(generation: Int) {
        guard presentationGeneration == generation,
              transition == .collapsing else { return }
        compactContentRecoveryDidFinish = true
        tryFinishCollapse(generation: generation)
    }

    private func tryFinishCollapse(generation: Int) {
        guard presentationGeneration == generation,
              transition == .collapsing,
              !showsExpandedContent,
              collapseBackgroundDidFinish,
              compactContentRecoveryDidFinish,
              !compactBouncePending || compactBounceDidFinish,
              !isCompactActivationPending else { return }

        isCompactActivationPending = true
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            usesExpandedGeometry = false
            expansionStartSize = nil
        }
        onWindowFrameChange?(false)

        presentationTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: PocketNotchTheme.islandCompactActivationDelayNanoseconds
            )
            guard !Task.isCancelled,
                  let self,
                  self.presentationGeneration == generation,
                  self.transition == .collapsing,
                  !self.usesExpandedGeometry,
                  self.showsCompactContent else { return }

            self.isCompactActivationPending = false
            if self.isHovered {
                let animation = self.usesReducedMotion
                    ? PocketNotchTheme.islandReducedMotionAnimation
                    : PocketNotchTheme.islandHoverAnimation
                withAnimation(animation) {
                    self.transition = .compact
                }
            } else {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    self.transition = .compact
                }
            }
            self.flushPendingCompactTierShrink()
        }
    }

    // MARK: - 取消

    /// 锁屏等系统级中断发生时，窗口会先隐藏，再无动画回到稳定 compact 状态。
    /// 这不是用户发起的收起，不保留任何 presentation velocity 或 Hover 状态。
    public func resetForSessionSuspension() {
        presentationTask?.cancel()
        compactBounceTask?.cancel()
        compactTierBounceTask?.cancel()
        compactTierBounceTask = nil
        presentationGeneration &+= 1
        isCompactActivationPending = false
        collapseBackgroundDidFinish = true
        compactContentRecoveryDidFinish = true
        compactBouncePending = false
        compactBounceDidFinish = true
        compactBounceProgress = 1
        compactTierBounceProgress = 1
        holdsResidentCompactContentForTierShrink = false
        pendingCompactTierShrink = false
        usesReducedMotion = false
        interruptsInFlightHandoff = false

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            expansionProgress = 0
            usesExpandedGeometry = false
            showsCompactContent = true
            showsExpandedContent = false
            expansionStartSize = nil
            transition = .compact
            preservesCompactHoverPresentation = false
            isHovered = false
        }
        onWindowFrameChange?(false)
    }
}
