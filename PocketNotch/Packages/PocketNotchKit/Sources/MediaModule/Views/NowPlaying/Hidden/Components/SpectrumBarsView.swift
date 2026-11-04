import AppKit
import PocketNotchCore
import PocketNotchShared
import QuartzCore
import SwiftUI

struct MusicSpectrumBarGeometry: Equatable {
    let barWidth: CGFloat
    let spacing: CGFloat
    let cornerRadius: CGFloat
    let totalWidth: CGFloat

    static let minimumCompactRightEarWidth = CompactIslandContentSpec.defaultSideContentWidth
    private static let barWidthRange: ClosedRange<CGFloat> = 1.5...3.5
    private static let spacingRange: ClosedRange<CGFloat> = 1.0...2.2

    static func resolve(
        configuration: MusicSpectrumConfiguration,
        availableWidth: CGFloat = Self.minimumCompactRightEarWidth
    ) -> Self {
        let barCount = CGFloat(configuration.style.barCount)
        let gapCount = max(barCount - 1, 1)
        // 4/5/6 条使用完全相同的实际 pt 尺寸；设置值直接就是 pt，不再乘系数。
        let barWidth = min(
            max(CGFloat(configuration.barWidthScale), barWidthRange.lowerBound),
            barWidthRange.upperBound
        )
        let spacing = min(
            max(CGFloat(configuration.barSpacingScale), spacingRange.lowerBound),
            spacingRange.upperBound
        )
        // 仅在异常狭窄的容器中等比缩小，正常 26 pt 内容区可完整容纳最大 6 条样式。
        let rawTotalWidth = barCount * barWidth + gapCount * spacing
        let fitScale = min(1, availableWidth / max(rawTotalWidth, 1))
        let fittedBarWidth = barWidth * fitScale
        let fittedSpacing = spacing * fitScale
        let cornerRadiusProgress = CGFloat(
            min(max(configuration.barCornerRadiusScale, 0), 1)
        )

        return Self(
            barWidth: fittedBarWidth,
            spacing: fittedSpacing,
            cornerRadius: fittedBarWidth / 2 * cornerRadiusProgress,
            totalWidth: barCount * fittedBarWidth + gapCount * fittedSpacing
        )
    }

}

/// 30/45fps 读取最新频谱目标，交给 Core Animation 在合成器中按屏幕刷新率补间。
/// 采样容量对应的渐变图层长期驻留；4/5/6 条模式只激活所需图层，切换时不重建采样链路。
/// 频谱律动组件
final class SpectrumRendererView: NSView {
    private enum Design {
        /// 最短柱高 = 内容区方形边长 × 该比例，保证静止/低幅时仍有可见基准。
        static let minHeightRatio: CGFloat = 0.178
        /// 最长柱高 = 内容区方形边长 × 该比例，限制满幅峰值不至于顶到边界。
        static let maxHeightRatio: CGFloat = 0.82
        /// 柱子发光（shadow）的不透明度，克制地营造轻微辉光。
        static let glowOpacity: CGFloat = 0.18
        /// 柱子发光（shadow）的模糊半径（pt）。
        static let glowRadius: CGFloat = 2
        /// 柱高上升（attack）时的动画时长：短促有力，跟上打击节拍。
        static let attackDuration: CFTimeInterval = 0.06
        /// 柱高回落（release）时的动画时长：更利落地跟随节拍，同时保留自然衰减。
        static let releaseDuration: CFTimeInterval = 0.12
        /// 从播放切回暂停/静态形态时的强制回落时长，平滑收拢到稳定状态。
        static let settleDuration: CFTimeInterval = 0.12
        /// 目标幅值变化阈值：小于它则不触发键帧动画，省去无意义的重排。
        static let targetLevelChangeThreshold: CGFloat = 0.012
        /// 当前展示高度与目标高度之差阈值：小于它则跳过动画直接定态。
        static let heightChangeThreshold: CGFloat = 0.002
        /// 上升动画的时间曲线：快入缓收，配合 attackDuration 呈现击鼓感。
        static let attackTiming = CAMediaTimingFunction(
            controlPoints: 0.20,
            0.72,
            0.32,
            1
        )
        /// 回落动画的时间曲线：收尾更缓，模拟声音自然衰减。
        static let releaseTiming = CAMediaTimingFunction(
            controlPoints: 0.24,
            0.62,
            0.38,
            1
        )
    }

    private let maximumBarCount = AudioSpectrumConfiguration.sampledBandCount
    private let stateLock = NSLock()
    private var source: SpectrumDataSource?
    private var colors: [Color] = []
    private var barGradientsByBarCount: [Int: [SpectrumBarGradient]] = [:]
    private var configuration = MusicSpectrumConfiguration(
        style: .five,
        sensitivity: 0.5,
        attackTime: 0.5,
        releaseTime: 0.5
    )
    private var isActive = false
    private var reduceMotion = false
    private var occlusionObserver: NSObjectProtocol?
    private var displayedLevels: [CGFloat]
    private var filteredLevels: [CGFloat]
    private var pendingLevels: [CGFloat]?
    private var pendingTickID: UInt64?
    private var barLayers: [CAGradientLayer] = []
    private var minBarHeight: CGFloat = 0
    private var maxBarHeight: CGFloat = 0
    private var availableWidth: CGFloat = MusicSpectrumBarGeometry.minimumCompactRightEarWidth
    /// 高度计算用的虚拟边长；nil 时沿用实际 bounds。宽高比紧的容器传更大值可抬高最高柱。
    private var virtualSide: CGFloat?
    /// 锁屏呈现：窗口被委托到私有锁屏 Space 后 `isOnActiveSpace` 恒为 false，
    /// 若沿用桌面门控会永远注册不上，频谱冻结。此时放宽 Space 判定，仅保留可见性门控。
    private var isLockScreenPresentation = false

    override init(frame frameRect: NSRect) {
        let count = AudioSpectrumConfiguration.sampledBandCount
        self.displayedLevels = [CGFloat](repeating: 0, count: count)
        self.filteredLevels = [CGFloat](repeating: 0, count: count)
        super.init(frame: frameRect)
        configureLayers()
    }

    required init?(coder: NSCoder) {
        let count = AudioSpectrumConfiguration.sampledBandCount
        self.displayedLevels = [CGFloat](repeating: 0, count: count)
        self.filteredLevels = [CGFloat](repeating: 0, count: count)
        super.init(coder: coder)
        configureLayers()
    }

    deinit {
        AnimationScheduler.shared.unregister(self)
    }

    override func layout() {
        super.layout()
        updateLayerGeometry()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeOcclusionObserver()
        guard let window else {
            AnimationScheduler.shared.unregister(self)
            return
        }
        // 跨 Space / 被全屏应用遮挡时窗口不参与合成，频谱停止动画（守耗电铁律）。
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.synchronizeRegistration()
        }
        synchronizeRegistration()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateLayerContentsScale()
    }

    // MARK: - 配置（主线程调用）

    func setSource(_ source: SpectrumDataSource) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard source !== self.source else { return }
        self.source = source
    }

    func setColors(_ colors: [Color]) {
        guard colors != self.colors else { return }
        self.colors = colors
        updateLayerColors()
    }

    func setBarGradients(_ gradients: [Int: [SpectrumBarGradient]]) {
        guard gradients != barGradientsByBarCount else { return }
        barGradientsByBarCount = gradients
        updateLayerColors()
    }

    /// 只在显式设置了虚拟边长时，用它放宽高度计算基准；其余调用不变。
    func setVirtualSide(_ side: CGFloat?) {
        guard side != virtualSide else { return }
        virtualSide = side
        updateLayerGeometry(animated: false)
    }

    func setLockScreenPresentation(_ isLockScreen: Bool) {
        stateLock.lock()
        guard isLockScreen != isLockScreenPresentation else {
            stateLock.unlock()
            return
        }
        isLockScreenPresentation = isLockScreen
        stateLock.unlock()
        synchronizeRegistration()
    }

    func setConfiguration(_ configuration: MusicSpectrumConfiguration) {
        stateLock.lock()
        guard configuration != self.configuration else {
            stateLock.unlock()
            return
        }
        let previousConfiguration = self.configuration
        let styleChanged = previousConfiguration.style != configuration.style
        let geometryChanged = styleChanged
            || previousConfiguration.barWidthScale != configuration.barWidthScale
            || previousConfiguration.barSpacingScale != configuration.barSpacingScale
            || previousConfiguration.barCornerRadiusScale != configuration.barCornerRadiusScale
        self.configuration = configuration
        let source = self.source
        let shouldAnimate = !reduceMotion
        let shouldReadSource = isActive && !reduceMotion
        pendingLevels = nil
        pendingTickID = nil
        stateLock.unlock()

        if previousConfiguration.updateRate != configuration.updateRate {
            AnimationScheduler.shared.setTargetFrameRate(
                configuration.updateRate.animationFrameRate,
                followsDisplay: configuration.updateRate.followsDisplayRefreshRate
            )
        }

        if styleChanged {
            updateLayerColors()
        }

        guard styleChanged else {
            if geometryChanged {
                updateLayerGeometry(animated: shouldAnimate)
            }
            return
        }

        let currentLevels = (shouldReadSource ? source : nil).map {
            AudioSpectrumConfiguration.renderedLevels(
                from: $0.readBands(),
                configuration: configuration
            )
        } ?? displayedLevels
        let paddedLevels = (0..<maximumBarCount).map { index in
            currentLevels.indices.contains(index) ? currentLevels[index] : 0
        }
        stateLock.lock()
        filteredLevels = paddedLevels
        stateLock.unlock()
        updateLayerGeometry(animated: shouldAnimate)
        apply(
            levels: currentLevels,
            animated: shouldAnimate,
            forcedDuration: 0.18
        )
    }

    func initialize(isActive: Bool, reduceMotion: Bool) {
        stateLock.lock()
        self.isActive = isActive
        self.reduceMotion = reduceMotion
        // 暂停/静止时保留上一帧，频柱原地冻结而非归零。
        filteredLevels = displayedLevels
        stateLock.unlock()

        if isActive {
            synchronizeRegistration()
        } else {
            apply(levels: displayedLevels, animated: false)
        }
    }

    func update(isActive: Bool, reduceMotion: Bool) {
        stateLock.lock()
        guard isActive != self.isActive || reduceMotion != self.reduceMotion else {
            stateLock.unlock()
            return
        }
        let wasActive = self.isActive
        PocketNotchLog.media.debug(
            "Spectrum renderer state changed active=\(isActive) previous=\(wasActive) reduceMotion=\(reduceMotion)"
        )
        self.isActive = isActive
        self.reduceMotion = reduceMotion
        // 暂停/静止时保留上一帧，频柱原地冻结而非归零。
        filteredLevels = displayedLevels
        pendingLevels = nil
        pendingTickID = nil
        stateLock.unlock()

        if isActive {
            synchronizeRegistration()
        } else {
            AnimationScheduler.shared.unregister(self)
            apply(
                levels: displayedLevels,
                animated: wasActive && !reduceMotion,
                forcedDuration: Design.settleDuration
            )
        }
    }

    func teardown() {
        stateLock.lock()
        isActive = false
        source = nil
        pendingLevels = nil
        pendingTickID = nil
        stateLock.unlock()
        removeOcclusionObserver()
        AnimationScheduler.shared.unregister(self)
        barLayers.forEach { $0.removeAllAnimations() }
    }

    // MARK: - 注册与可见性门控

    private func synchronizeRegistration() {
        stateLock.lock()
        let shouldRun = isActive && !reduceMotion
        let isLockScreen = isLockScreenPresentation
        stateLock.unlock()
        guard shouldRun else { return }
        guard let window else {
            AnimationScheduler.shared.unregister(self)
            return
        }
        // 锁屏窗口被托管在私有 Space 上，`isOnActiveSpace` 不成立；锁屏场景只以
        // 合成可见性为准，其余场景仍要求窗口位于当前活动 Space 且可见。
        let isOnTargetSpace = isLockScreen || window.isOnActiveSpace
        if isOnTargetSpace, window.occlusionState.contains(.visible) {
            setSchedulerFrameRate()
            AnimationScheduler.shared.register(self)
        } else {
            AnimationScheduler.shared.unregister(self)
        }
    }

    private func setSchedulerFrameRate() {
        stateLock.lock()
        let frameRate = configuration.updateRate.animationFrameRate
        let followsDisplay = configuration.updateRate.followsDisplayRefreshRate
        stateLock.unlock()
        AnimationScheduler.shared.setTargetFrameRate(frameRate, followsDisplay: followsDisplay)
    }

    private func removeOcclusionObserver() {
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
    }

    // MARK: - 图层

    private func configureLayers() {
        wantsLayer = true
        layer?.masksToBounds = false
        barLayers = (0..<maximumBarCount).map { _ in
            let bar = CAGradientLayer()
            bar.startPoint = CGPoint(x: 0.5, y: 1)
            bar.endPoint = CGPoint(x: 0.5, y: 0)
            bar.shadowOffset = .zero
            bar.shadowRadius = Design.glowRadius
            bar.shadowOpacity = Float(Design.glowOpacity)
            bar.allowsEdgeAntialiasing = true
            layer?.addSublayer(bar)
            return bar
        }
        updateLayerContentsScale()
        updateLayerColors()
    }

    private func updateLayerGeometry(animated: Bool = false) {
        availableWidth = max(bounds.width, 1)
        let square = virtualSide.map { max(max(availableWidth, bounds.height), $0) }
            ?? min(availableWidth, bounds.height)
        guard availableWidth > 0, square > 0 else { return }

        let centerY = bounds.midY
        let activeBarCount = configuration.style.barCount
        let geometry = MusicSpectrumBarGeometry.resolve(
            configuration: configuration,
            availableWidth: availableWidth
        )
        let barWidth = geometry.barWidth
        let spacing = geometry.spacing
        let widthRange = MediaMonitoringSettings.spectrumBarWidthRange
        let clampedWidth = min(
            max(configuration.barWidthScale, widthRange.lowerBound),
            widthRange.upperBound
        )
        let widthProgress = CGFloat(
            (clampedWidth - widthRange.lowerBound)
                / (widthRange.upperBound - widthRange.lowerBound)
        )
        // 柱子越细，整体高度范围略收窄；越宽，最低/最高高度略提高，保持视觉比例。
        let minHeightRatio = Design.minHeightRatio
            - 0.02
            + widthProgress * 0.04
        let maxHeightRatio = Design.maxHeightRatio
            - 0.05
            + widthProgress * 0.10
        minBarHeight = max(barWidth, square * minHeightRatio)
        maxBarHeight = square * maxHeightRatio
        // 频柱固定居中排布，不再提供对齐方式设置。
        let startX = bounds.midX - geometry.totalWidth / 2 + barWidth / 2

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated {
            CATransaction.setAnimationDuration(0.18)
            CATransaction.setAnimationTimingFunction(
                CAMediaTimingFunction(name: .easeOut)
            )
        }
        for (index, bar) in barLayers.enumerated() {
            let isVisible = index < activeBarCount
            let level = displayedLevels.indices.contains(index) ? displayedLevels[index] : 0
            let height = height(for: level)
            bar.position = CGPoint(
                x: isVisible
                    ? startX + CGFloat(index) * (barWidth + spacing)
                    : bounds.maxX,
                y: centerY
            )
            // 保持固定最大高度，实时变化只通过 scaleY 合成，避免逐帧修改 bounds 触发额外绘制。
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: maxBarHeight)
            // 固定静态 shadowPath：阴影只随几何变化而更新，60fps 柱高动画不再离屏重算阴影。
            bar.shadowPath = CGPath(
                roundedRect: CGRect(x: 0, y: 0, width: barWidth, height: maxBarHeight),
                cornerWidth: min(barWidth / 2, maxBarHeight / 2),
                cornerHeight: min(barWidth / 2, maxBarHeight / 2),
                transform: nil
            )
            bar.transform = CATransform3DMakeScale(
                1,
                max(max(height / max(maxBarHeight, 1), 0), 0.001),
                1
            )
            bar.cornerRadius = layerCornerRadius(
                for: height,
                geometry: geometry
            )
            bar.opacity = isVisible ? 1 : 0
        }
        CATransaction.commit()
    }

    private func updateLayerColors() {
        let fallback = MediaPaletteStyle.foregroundColors(from: colors).map { NSColor($0) }
        let fallbackTop = fallback.first ?? .white
        let fallbackBottom = fallback.last ?? fallbackTop
        let columnGradients = barGradientsByBarCount[configuration.style.barCount] ?? []

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in barLayers.enumerated() {
            let top: NSColor
            let bottom: NSColor
            if columnGradients.indices.contains(index) {
                top = NSColor(columnGradients[index].top)
                bottom = NSColor(columnGradients[index].bottom)
            } else {
                top = fallbackTop
                bottom = fallbackBottom
            }
            bar.colors = [top.cgColor, bottom.cgColor]
            bar.locations = [0, 1]
            bar.shadowColor = bottom.cgColor
        }
        CATransaction.commit()
    }

    private func updateLayerContentsScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        barLayers.forEach { $0.contentsScale = scale }
    }

    private func apply(
        levels: [CGFloat],
        animated: Bool,
        forcedDuration: CFTimeInterval? = nil
    ) {
        guard minBarHeight > 0, maxBarHeight > 0 else {
            displayedLevels = normalized(levels)
            needsLayout = true
            return
        }

        let normalizedLevels = normalized(levels)
        for (index, bar) in barLayers.enumerated() {
            let targetLevel = normalizedLevels[index]
            let previousTargetLevel = displayedLevels.indices.contains(index)
                ? displayedLevels[index]
                : 0
            if animated,
               forcedDuration == nil,
               abs(targetLevel - previousTargetLevel) <= Design.targetLevelChangeThreshold {
                continue
            }
            let targetHeight = height(for: targetLevel)
            let targetScale = max(targetHeight / max(maxBarHeight, 1), 0.001)
            let presentationScale = bar.presentation()?.transform.m22 ?? bar.transform.m22
            let presentationHeight = presentationScale * maxBarHeight
            let geometry = MusicSpectrumBarGeometry.resolve(
                configuration: configuration,
                availableWidth: availableWidth
            )

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bar.transform = CATransform3DMakeScale(1, targetScale, 1)
            bar.cornerRadius = layerCornerRadius(
                for: targetHeight,
                geometry: geometry
            )
            CATransaction.commit()

            displayedLevels[index] = targetLevel
            bar.removeAnimation(forKey: "pocketnotch.spectrum.height")
            guard animated,
                  abs(presentationHeight - targetHeight) > Design.heightChangeThreshold else {
                continue
            }

            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = presentationScale
            animation.toValue = targetScale
            let isAttack = targetHeight > presentationHeight
            animation.duration = forcedDuration
                ?? (isAttack ? Design.attackDuration : Design.releaseDuration)
            animation.timingFunction = isAttack ? Design.attackTiming : Design.releaseTiming
            animation.isRemovedOnCompletion = true
            bar.add(animation, forKey: "pocketnotch.spectrum.height")
        }
    }

    private func normalized(_ levels: [CGFloat]) -> [CGFloat] {
        (0..<maximumBarCount).map { index in
            guard index < configuration.style.barCount,
                  levels.indices.contains(index) else { return 0 }
            return min(max(levels[index], 0), 1)
        }
    }

    private func height(for level: CGFloat) -> CGFloat {
        minBarHeight + min(max(level, 0), 1) * (maxBarHeight - minBarHeight)
    }

    /// 将设置中的圆角比例换算到固定最大高度图层的坐标系。
    /// 由于实时柱高使用 scaleY，直接设置 barWidth / 2 会让低柱状态的圆角被压扁，
    /// 看起来像没有跟随设置变化。这里按当前显示高度反算，并限制为合法最大圆角。
    private func layerCornerRadius(
        for renderedHeight: CGFloat,
        geometry: MusicSpectrumBarGeometry
    ) -> CGFloat {
        let progress = CGFloat(
            min(max(configuration.barCornerRadiusScale, 0), 1)
        )
        let desiredRadius = min(
            geometry.barWidth / 2 * progress,
            renderedHeight / 2
        )
        let scale = max(renderedHeight / max(maxBarHeight, 1), 0.001)
        return min(desiredRadius / scale, maxBarHeight / 2)
    }
}

extension SpectrumRendererView: IslandAnimator {
    func animationTick(
        deltaTime: CFTimeInterval,
        tickID: UInt64,
        callbackTime: CFTimeInterval
    ) {
        stateLock.lock()
        guard isActive, !reduceMotion, let source else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        let raw = source.readBands()

        stateLock.lock()
        let configuration = self.configuration
        stateLock.unlock()
        let rawLevels = AudioSpectrumConfiguration.renderedLevels(
            from: raw,
            configuration: configuration
        )

        stateLock.lock()
        guard isActive, !reduceMotion else {
            stateLock.unlock()
            return
        }
        let dt = CGFloat(min(max(deltaTime, 0), 0.1))
        let inputDeadband = AudioSpectrumConfiguration.inputDeadband(
            for: configuration.rhythmDetail
        )
        for index in 0..<configuration.style.barCount {
            let current = filteredLevels[index]
            let rawTarget = rawLevels[index]
            let difference = rawTarget - current
            let magnitude = abs(difference)
            // 高频段的绝对幅值通常较低，固定死区会把它们的小幅变化全部吃掉。
            // 按当前局部幅值缩小死区，仅改善响应，不对任何频段额外增益。
            let localLevel = min(max(max(current, rawTarget), 0), 0.25)
            let deadbandScale = 0.35 + localLevel / 0.25 * 0.65
            let adaptiveDeadband = inputDeadband * deadbandScale
            guard magnitude > adaptiveDeadband else { continue }

            // Hysteresis absorbs FFT noise around the current value without muting real peaks.
            let direction: CGFloat = difference > 0 ? 1 : -1
            let target = rawTarget - direction * adaptiveDeadband
            let timeConstant = target > current
                ? AudioSpectrumConfiguration.attackTimeConstant(
                    for: configuration.attackTime
                )
                : AudioSpectrumConfiguration.releaseTimeConstant(
                    for: configuration.releaseTime
                )
            let progress = 1 - exp(-Double(dt / timeConstant))
            filteredLevels[index] = current + (target - current) * CGFloat(progress)
        }
        pendingLevels = filteredLevels
        pendingTickID = tickID
        stateLock.unlock()
    }

    func animationCommit(
        tickID: UInt64,
        callbackTime: CFTimeInterval
    ) {
        stateLock.lock()
        guard pendingTickID == tickID, let levels = pendingLevels else {
            stateLock.unlock()
            return
        }
        pendingLevels = nil
        pendingTickID = nil
        let shouldAnimate = !reduceMotion
        stateLock.unlock()
        apply(levels: levels, animated: shouldAnimate)
    }
}

/// SpectrumRendererView 的 SwiftUI 入口。
struct SpectrumBarsView: NSViewRepresentable {
    let source: SpectrumDataSource
    let colors: [Color]
    let isActive: Bool
    let reduceMotion: Bool
    let configuration: MusicSpectrumConfiguration
    /// 按频柱数量保存的封面逐列渐变；缺少时退回 `colors` 的统一渐变。
    var barGradientsByBarCount: [Int: [SpectrumBarGradient]] = [:]
    /// 高度计算用的虚拟边长；nil 时沿用实际 bounds。宽高比紧的容器传更大值可抬高最高柱。
    var virtualSide: CGFloat?
    /// 锁屏音乐小组件为 true：窗口位于私有锁屏 Space，跳过活动 Space 门控。
    var isLockScreenPresentation: Bool = false

    func makeNSView(context: Context) -> SpectrumRendererView {
        let view = SpectrumRendererView()
        view.setSource(source)
        view.setColors(colors)
        view.setBarGradients(barGradientsByBarCount)
        view.setConfiguration(configuration)
        view.setVirtualSide(virtualSide)
        view.setLockScreenPresentation(isLockScreenPresentation)
        view.initialize(isActive: isActive, reduceMotion: reduceMotion)
        return view
    }

    func updateNSView(_ view: SpectrumRendererView, context: Context) {
        view.setSource(source)
        view.setColors(colors)
        view.setBarGradients(barGradientsByBarCount)
        view.setConfiguration(configuration)
        view.setVirtualSide(virtualSide)
        view.setLockScreenPresentation(isLockScreenPresentation)
        view.update(isActive: isActive, reduceMotion: reduceMotion)
    }

    static func dismantleNSView(_ view: SpectrumRendererView, coordinator: Void) {
        view.teardown()
    }
}
