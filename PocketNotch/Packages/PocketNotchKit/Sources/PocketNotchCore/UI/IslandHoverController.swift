import AppKit
import SwiftUI

/// Hover 追踪视图。
///
/// `NSTrackingArea` 边界事件立即采样；形状内移动与布局刷新限制为约 60Hz，
/// 退出状态需稳定 75ms 后再次命中才发布。不安装 local/global event monitors。
struct IslandHoverController: NSViewRepresentable {
    let isEnabled: Bool
    let backgroundState: IslandBackgroundState
    let backgroundMetrics: IslandBackgroundMetrics
    let expansionProgress: CGFloat
    let compactMorphProgress: CGFloat
    let onHoverChange: (Bool) -> Void

    func makeNSView(context: Context) -> IslandHoverNSView {
        let view = IslandHoverNSView()
        view.onHoverChange = onHoverChange
        view.updateShapeGeometry(
            state: backgroundState,
            metrics: backgroundMetrics,
            expansionProgress: expansionProgress,
            compactMorphProgress: compactMorphProgress
        )
        view.setTrackingEnabled(isEnabled)
        return view
    }

    func updateNSView(_ nsView: IslandHoverNSView, context: Context) {
        nsView.onHoverChange = onHoverChange
        nsView.updateShapeGeometry(
            state: backgroundState,
            metrics: backgroundMetrics,
            expansionProgress: expansionProgress,
            compactMorphProgress: compactMorphProgress
        )
        nsView.setTrackingEnabled(isEnabled)
        if isEnabled {
            nsView.scheduleHoverStateRefresh()
        }
    }

    static func dismantleNSView(_ nsView: IslandHoverNSView, coordinator: ()) {
        nsView.invalidate()
    }
}

final class IslandHoverNSView: NSView {
    var onHoverChange: ((Bool) -> Void)?

    private var hoverTrackingArea: NSTrackingArea?
    private var trailingRefreshWorkItem: DispatchWorkItem?
    private var trailingRefreshIsGeometryDriven = false
    private var exitValidationWorkItem: DispatchWorkItem?
    private var hoverCoordinator = IslandHoverCoordinator()
    private var isActive = true
    private var isTrackingEnabled = true
    private var lastHoverTrueRectInWindow: CGRect?
    private var backgroundState: IslandBackgroundState = .hidden
    private var backgroundMetrics: IslandBackgroundMetrics = .default
    private var expansionProgress: CGFloat = 0
    private var compactMorphProgress: CGFloat = 0

    /// 悬停粘滞矩形只取其与当前窗口区域的交集：收起时窗口缩小，
    /// 旧展开态的大矩形若原样保留，会让回到旧面板区域的指针被误判为仍悬停。
    private static func clampedHoverRect(
        _ rect: CGRect?,
        windowRect: CGRect
    ) -> CGRect? {
        guard let clamped = rect?.intersection(windowRect),
              !clamped.isNull,
              !clamped.isEmpty else { return nil }
        return clamped
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea

        super.updateTrackingAreas()
        requestGeometryRefresh()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        requestGeometryRefresh()
    }

    override func mouseEntered(with event: NSEvent) {
        refreshHoverStateImmediately()
    }

    override func mouseExited(with event: NSEvent) {
        refreshHoverStateImmediately()
    }

    override func mouseMoved(with event: NSEvent) {
        requestPointerRefresh()
    }

    /// Hover 视图只负责 tracking，不参与命中测试。
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func scheduleHoverStateRefresh() {
        requestGeometryRefresh()
    }

    func updateShapeGeometry(
        state: IslandBackgroundState,
        metrics: IslandBackgroundMetrics,
        expansionProgress: CGFloat,
        compactMorphProgress: CGFloat
    ) {
        backgroundState = state
        backgroundMetrics = metrics
        self.expansionProgress = expansionProgress
        self.compactMorphProgress = compactMorphProgress
    }

    func setTrackingEnabled(_ isEnabled: Bool) {
        guard isEnabled != isTrackingEnabled else { return }
        isTrackingEnabled = isEnabled
        trailingRefreshWorkItem?.cancel()
        trailingRefreshWorkItem = nil
        trailingRefreshIsGeometryDriven = false
        exitValidationWorkItem?.cancel()
        exitValidationWorkItem = nil
        hoverCoordinator = IslandHoverCoordinator()
        lastHoverTrueRectInWindow = nil

        if isEnabled {
            requestGeometryRefresh()
        }
    }

    func invalidate() {
        isActive = false
        trailingRefreshWorkItem?.cancel()
        trailingRefreshWorkItem = nil
        trailingRefreshIsGeometryDriven = false
        exitValidationWorkItem?.cancel()
        exitValidationWorkItem = nil
        lastHoverTrueRectInWindow = nil
        onHoverChange = nil
    }

    private func requestGeometryRefresh() {
        requestRefresh(isGeometryDriven: true)
    }

    private func requestPointerRefresh() {
        requestRefresh(isGeometryDriven: false)
    }

    private func requestRefresh(isGeometryDriven: Bool) {
        guard isActive, isTrackingEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        switch hoverCoordinator.requestRefresh(at: now) {
        case .refreshNow:
            trailingRefreshWorkItem?.cancel()
            trailingRefreshWorkItem = nil
            trailingRefreshIsGeometryDriven = false
            refreshHoverStateImmediately(isGeometryDriven: isGeometryDriven)
        case let .scheduleTrailing(after: delay):
            trailingRefreshIsGeometryDriven = trailingRefreshIsGeometryDriven || isGeometryDriven
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.isActive else { return }
                let isGeometryDriven = self.trailingRefreshIsGeometryDriven
                self.trailingRefreshWorkItem = nil
                self.trailingRefreshIsGeometryDriven = false
                self.hoverCoordinator.trailingRefreshFired(
                    at: ProcessInfo.processInfo.systemUptime
                )
                self.refreshHoverStateImmediately(isGeometryDriven: isGeometryDriven)
            }
            trailingRefreshWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        case .none:
            trailingRefreshIsGeometryDriven = trailingRefreshIsGeometryDriven || isGeometryDriven
        }
    }

    private func refreshHoverStateImmediately(
        validatesPendingExit: Bool = false,
        isGeometryDriven: Bool = false
    ) {
        guard isActive, isTrackingEnabled else { return }
        guard let window, !isHidden, alphaValue > 0 else {
            if validatesPendingExit {
                hoverCoordinator.cancelPendingExit()
            }
            return
        }

        let pointerScreenPoint = NSEvent.mouseLocation
        let pointInWindow = window.convertPoint(fromScreen: pointerScreenPoint)
        let pointInView = convert(pointInWindow, from: nil)
        let windowRect = convert(bounds, to: nil)
        let shapePath = IslandHoverHitTesting.shapePath(
            in: bounds,
            state: backgroundState,
            metrics: backgroundMetrics,
            expansionProgress: expansionProgress,
            compactMorphProgress: compactMorphProgress,
            isFlipped: isFlipped
        )
        let isSpatiallyInside = IslandHoverHitTesting.contains(
            pointInView: pointInView,
            bounds: bounds,
            pointerScreenPoint: pointerScreenPoint,
            windowFrame: window.frame,
            backingScaleFactor: window.backingScaleFactor,
            shapePath: shapePath
        )

        let isInside: Bool
        if isSpatiallyInside {
            lastHoverTrueRectInWindow = windowRect
            isInside = IslandHoverInput.isEligible(
                isSpatiallyInside: true,
                pressedMouseButtons: NSEvent.pressedMouseButtons
            )
        } else if let lastRect = Self.clampedHoverRect(
            lastHoverTrueRectInWindow,
            windowRect: windowRect
        ), lastRect.contains(pointInWindow) {
            isInside = IslandHoverInput.isEligible(
                isSpatiallyInside: true,
                pressedMouseButtons: NSEvent.pressedMouseButtons
            )
        } else {
            lastHoverTrueRectInWindow = nil
            isInside = IslandHoverInput.isEligible(
                isSpatiallyInside: false,
                pressedMouseButtons: NSEvent.pressedMouseButtons
            )
        }

        apply(
            hoverCoordinator.sample(
                isInside: isInside,
                at: ProcessInfo.processInfo.systemUptime,
                validatesPendingExit: validatesPendingExit,
                isGeometryDriven: isGeometryDriven
            )
        )
    }

    private func apply(_ actions: IslandHoverCoordinator.SampleActions) {
        if actions.cancelsExitValidation {
            exitValidationWorkItem?.cancel()
            exitValidationWorkItem = nil
        }

        if let delay = actions.exitValidationDelay {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.isActive else { return }
                self.exitValidationWorkItem = nil
                self.refreshHoverStateImmediately(validatesPendingExit: true)
            }
            exitValidationWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }

        if let isInside = actions.emission {
            onHoverChange?(isInside)
        }
    }
}

enum IslandHoverRefreshDecision: Equatable {
    case refreshNow
    case scheduleTrailing(after: TimeInterval)
    case none
}

struct IslandHoverCoordinator {
    static let refreshThrottleInterval: TimeInterval = 0.016
    static let exitDebounceInterval: TimeInterval = 0.075

    struct SampleActions: Equatable {
        var emission: Bool?
        var exitValidationDelay: TimeInterval?
        var cancelsExitValidation = false
    }

    private(set) var publishedIsInside = false
    private(set) var pendingExitDeadline: TimeInterval?
    private var lastRefreshUptime: TimeInterval?
    private var hasTrailingRefresh = false

    mutating func requestRefresh(at uptime: TimeInterval) -> IslandHoverRefreshDecision {
        guard let lastRefreshUptime else {
            self.lastRefreshUptime = uptime
            return .refreshNow
        }

        let elapsed = max(uptime - lastRefreshUptime, 0)
        guard elapsed < Self.refreshThrottleInterval else {
            self.lastRefreshUptime = uptime
            hasTrailingRefresh = false
            return .refreshNow
        }

        guard !hasTrailingRefresh else { return .none }
        hasTrailingRefresh = true
        return .scheduleTrailing(after: Self.refreshThrottleInterval - elapsed)
    }

    mutating func trailingRefreshFired(at uptime: TimeInterval) {
        hasTrailingRefresh = false
        lastRefreshUptime = uptime
    }

    mutating func sample(
        isInside: Bool,
        at uptime: TimeInterval,
        validatesPendingExit: Bool = false,
        isGeometryDriven: Bool = false
    ) -> SampleActions {
        if isInside {
            let cancelsExitValidation = pendingExitDeadline != nil
            pendingExitDeadline = nil
            guard !publishedIsInside else {
                return SampleActions(cancelsExitValidation: cancelsExitValidation)
            }
            publishedIsInside = true
            return SampleActions(
                emission: true,
                cancelsExitValidation: cancelsExitValidation
            )
        }

        guard publishedIsInside else {
            let cancelsExitValidation = pendingExitDeadline != nil
            pendingExitDeadline = nil
            return SampleActions(cancelsExitValidation: cancelsExitValidation)
        }

        if validatesPendingExit {
            guard let deadline = pendingExitDeadline else {
                return SampleActions()
            }
            guard uptime >= deadline else {
                return SampleActions(exitValidationDelay: deadline - uptime)
            }
            pendingExitDeadline = nil
            publishedIsInside = false
            return SampleActions(emission: false, cancelsExitValidation: true)
        }

        // 几何/布局变化驱动的刷新不走退出防抖：防抖是为「指针贴边抖动」设计的，
        // 而窗口缩放等几何变化是布局真相——指针明确落在几何体外就必须立即退出，
        // 否则收起缩窗后 16ms 的 compact 激活会读到过期的 isHovered=true，
        // 先假性膨胀、再被 75ms 后迟到的退出事件缩回（收起尾段抖一下）。
        if isGeometryDriven {
            pendingExitDeadline = nil
            publishedIsInside = false
            return SampleActions(emission: false, cancelsExitValidation: true)
        }

        guard pendingExitDeadline == nil else { return SampleActions() }
        pendingExitDeadline = uptime + Self.exitDebounceInterval
        return SampleActions(exitValidationDelay: Self.exitDebounceInterval)
    }

    mutating func cancelPendingExit() {
        pendingExitDeadline = nil
    }
}

enum IslandHoverInput {
    static func isEligible(
        isSpatiallyInside: Bool,
        pressedMouseButtons: Int
    ) -> Bool {
        isSpatiallyInside && pressedMouseButtons == 0
    }
}

enum IslandHoverHitTesting {
    static func shapePath(
        in bounds: CGRect,
        state: IslandBackgroundState,
        metrics: IslandBackgroundMetrics,
        expansionProgress: CGFloat,
        compactMorphProgress: CGFloat,
        isFlipped: Bool
    ) -> CGPath {
        let path = IslandBackgroundPath.makePath(
            for: state,
            in: bounds,
            metrics: metrics,
            expansionProgress: expansionProgress,
            compactMorphProgress: compactMorphProgress,
            rendersInFullBounds: true
        )
        guard !isFlipped else { return path }

        var transform = CGAffineTransform(
            a: 1,
            b: 0,
            c: 0,
            d: -1,
            tx: 0,
            ty: bounds.minY + bounds.maxY
        )
        return path.copy(using: &transform) ?? path
    }

    static func contains(
        pointInView: CGPoint,
        bounds: CGRect,
        pointerScreenPoint: CGPoint,
        windowFrame: CGRect,
        backingScaleFactor: CGFloat,
        shapePath: CGPath? = nil
    ) -> Bool {
        let topEdgeTolerance = 1 / max(backingScaleFactor, 1)
        let isAtWindowTopEdge = abs(pointerScreenPoint.y - windowFrame.maxY) <= topEdgeTolerance

        if let shapePath {
            let drawnBounds = shapePath.boundingBoxOfPath
            if shapePath.contains(pointInView, using: .winding) {
                return true
            }

            // CGRect/路径都不把上边界算作内部；鼠标顶到屏幕最上沿时补一次容错，
            // 但横向仍严格限制在形状顶边的实际可见范围内，透明肩部不参与 hover。
            return isAtWindowTopEdge
                && pointInView.x >= drawnBounds.minX
                && pointInView.x <= drawnBounds.maxX
        }

        if bounds.contains(pointInView) {
            return true
        }

        // CGRect.contains 不包含 maxY；鼠标顶到屏幕最上沿时，坐标也可能落在窗口
        // maxY 边界上。只对顶部一个物理像素做容错，且仍严格限制在 Island 横向范围内。
        let isHorizontallyInside = pointInView.x >= bounds.minX && pointInView.x <= bounds.maxX

        return isAtWindowTopEdge && isHorizontallyInside
    }
}
