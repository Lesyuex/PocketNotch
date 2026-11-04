import AppKit
import CoreVideo
import Foundation
import PocketNotchCore
import PocketNotchShared

protocol IslandAnimator: AnyObject {
    func animationTick(
        deltaTime: CFTimeInterval,
        tickID: UInt64,
        callbackTime: CFTimeInterval
    )

    func animationCommit(
        tickID: UInt64,
        callbackTime: CFTimeInterval
    )
}

final class AnimationScheduler {
    static let shared = AnimationScheduler()

    private struct WeakParticipant {
        weak var animator: IslandAnimator?
    }

    /// 目标帧率请求：跟随全局屏幕刷新率（默认），或固定值（如省电档 30 FPS）。
    private enum TargetRateRequest {
        case followsDisplay
        case fixed(Double)
    }

    private let lock = NSLock()
    private var participants: [WeakParticipant] = []
    private var displayLink: CVDisplayLink?
    private var throttle = DisplayLinkThrottle(targetFrameRate: 30)
    private var clock = AnimationClock()
    private var nominalInterval: CFTimeInterval = 1.0 / 60.0
    private var pendingMainCommit = false
    private var tickID: UInt64 = 0
    private var lastRawCallbackTime: CFTimeInterval = 0
    private var reducedRateUntil: CFTimeInterval = 0
    private var rateRequest: TargetRateRequest = .followsDisplay
    private var currentTargetFrameRate: Double
    private var screenRateObserver: UUID?
    private var applicationObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    private init() {
        let initialRate = Self.normalTargetFrameRate
        currentTargetFrameRate = initialRate
        throttle.updateTargetFrameRate(initialRate)
        observeSystemTransitions()
        observeDisplayRefreshRateChanges()
    }

    func register(_ animator: IslandAnimator) {
        let shouldStartDisplayLink: Bool

        lock.lock()
        pruneLocked()
        guard !participants.contains(where: { $0.animator === animator }) else {
            lock.unlock()
            return
        }

        shouldStartDisplayLink = displayLink == nil
        participants.append(WeakParticipant(animator: animator))
        if shouldStartDisplayLink {
            startDisplayLinkLocked()
            guard displayLink != nil else {
                participants.removeAll { $0.animator === animator }
                pruneLocked()
                lock.unlock()
                return
            }
        }
        lock.unlock()
    }

    /// 设置当前频谱动画目标帧率。显示链路仍由 CVDisplayLink 驱动，
    /// 这里仅控制派发到主线程的频率，避免应用层固定在 30 FPS。
    ///
    /// `followsDisplay` 为 true 时忽略 `frameRate`，目标帧率实时跟随全局屏幕刷新率
    /// （显示器变化时自动更新）；false 时使用固定值。
    func setTargetFrameRate(_ frameRate: Double, followsDisplay: Bool = false) {
        lock.lock()
        rateRequest = followsDisplay ? .followsDisplay : .fixed(max(frameRate, 1))
        updateThrottleTargetLocked(at: ProcessInfo.processInfo.systemUptime)
        lock.unlock()
    }

    func unregister(_ animator: IslandAnimator) {
        let shouldStopDisplayLink: Bool
        let linkToStop: CVDisplayLink?

        lock.lock()
        pruneLocked()

        participants.removeAll { $0.animator === animator }
        pruneLocked()

        shouldStopDisplayLink = participants.isEmpty
        linkToStop = shouldStopDisplayLink ? displayLink : nil
        if shouldStopDisplayLink {
            displayLink = nil
            throttle.reset()
            clock.reset()
            pendingMainCommit = false
            self.tickID = 0
            lastRawCallbackTime = 0
            reducedRateUntil = 0
            rateRequest = .followsDisplay
            currentTargetFrameRate = Self.normalTargetFrameRate
            throttle.updateTargetFrameRate(Self.normalTargetFrameRate)
        }
        lock.unlock()

        if let linkToStop {
            CVDisplayLinkStop(linkToStop)
        }
    }

    private func startDisplayLinkLocked() {
        guard displayLink == nil else { return }
        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess,
              let link else { return }

        CVDisplayLinkSetOutputHandler(link) { [weak self] _, _, _, _, _ -> CVReturn in
            guard let self else { return kCVReturnSuccess }
            let callbackTime = ProcessInfo.processInfo.systemUptime
            self.handleTick(at: callbackTime)
            return kCVReturnSuccess
        }

        let period = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link)
        nominalInterval = period.timeValue > 0
            ? Double(period.timeScale) / Double(period.timeValue)
            : 1.0 / 60.0
        displayLink = link
        CVDisplayLinkStart(link)
    }

    private func handleTick(at callbackTime: CFTimeInterval) {
        let participantsSnapshot: [ParticipantSnapshot]
        let tickID: UInt64
        let deltaTime: CFTimeInterval

        lock.lock()
        pruneLocked()
        guard !participants.isEmpty else {
            let linkToStop = displayLink
            displayLink = nil
            throttle.reset()
            clock.reset()
            pendingMainCommit = false
            self.tickID = 0
            lastRawCallbackTime = 0
            reducedRateUntil = 0
            rateRequest = .followsDisplay
            currentTargetFrameRate = Self.normalTargetFrameRate
            throttle.updateTargetFrameRate(Self.normalTargetFrameRate)
            lock.unlock()
            if let linkToStop {
                DispatchQueue.main.async {
                    CVDisplayLinkStop(linkToStop)
                }
            }
            return
        }

        participantsSnapshot = participants.compactMap { participant in
            guard let animator = participant.animator else { return nil }
            return ParticipantSnapshot(animator: animator)
        }

        updateAdaptiveThrottleLocked(at: callbackTime)
        guard !pendingMainCommit else {
            lock.unlock()
            return
        }
        guard throttle.shouldDispatch(at: callbackTime) else {
            lock.unlock()
            return
        }

        pendingMainCommit = true
        self.tickID &+= 1
        tickID = self.tickID
        deltaTime = clock.sample(at: callbackTime)
        lock.unlock()

        for snapshot in participantsSnapshot {
            snapshot.animator.animationTick(
                deltaTime: deltaTime,
                tickID: tickID,
                callbackTime: callbackTime
            )
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for snapshot in participantsSnapshot {
                snapshot.animator.animationCommit(
                    tickID: tickID,
                    callbackTime: callbackTime
                )
            }
            self.finishCommit()
        }
    }

    private func finishCommit() {
        lock.lock()
        pendingMainCommit = false
        pruneLocked()
        let shouldStopDisplayLink = participants.isEmpty
        let linkToStop = shouldStopDisplayLink ? displayLink : nil
        if shouldStopDisplayLink {
            displayLink = nil
            throttle.reset()
            clock.reset()
            tickID = 0
            lastRawCallbackTime = 0
            reducedRateUntil = 0
            rateRequest = .followsDisplay
            currentTargetFrameRate = Self.normalTargetFrameRate
            throttle.updateTargetFrameRate(Self.normalTargetFrameRate)
        }
        lock.unlock()

        if let linkToStop {
            CVDisplayLinkStop(linkToStop)
        }
    }

    private func pruneLocked() {
        participants = participants.compactMap { participant in
            guard participant.animator != nil else { return nil }
            return participant
        }
    }

    private struct ParticipantSnapshot {
        let animator: IslandAnimator
    }
}

private extension AnimationScheduler {
    /// 未显式指定帧率时的默认目标：实时跟随当前屏幕最高刷新率。
    static var normalTargetFrameRate: Double { DisplayRefreshRateMonitor.shared.refreshRate }
    static let reducedTargetFrameRate: Double = 20
    static let systemTransitionThrottleDuration: CFTimeInterval = 0.4
    static let rawCallbackStallThreshold: CFTimeInterval = 0.033

    /// 屏幕刷新率变化（插拔显示器、分辨率/ProMotion 档位切换）时，
    /// 跟随屏幕的请求立即采用新速率，无需等待视图层重新设置。
    func observeDisplayRefreshRateChanges() {
        screenRateObserver = DisplayRefreshRateMonitor.shared.observe { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            if case .followsDisplay = self.rateRequest {
                self.updateThrottleTargetLocked(at: ProcessInfo.processInfo.systemUptime)
            }
            self.lock.unlock()
        }
    }

    func observeSystemTransitions() {
        let notificationCenter = NotificationCenter.default
        applicationObservers = [
            NSApplication.didResignActiveNotification,
            NSApplication.didBecomeActiveNotification
        ].map { name in
            notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.enterReducedRateWindow()
            }
        }

        workspaceObservers = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ].map { name in
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.enterReducedRateWindow()
            }
        }
    }

    func enterReducedRateWindow() {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        reducedRateUntil = max(reducedRateUntil, now + Self.systemTransitionThrottleDuration)
        updateThrottleTargetLocked(at: now)
        lock.unlock()
    }

    func updateAdaptiveThrottleLocked(at callbackTime: CFTimeInterval) {
        if lastRawCallbackTime > 0 {
            let rawInterval = max(callbackTime - lastRawCallbackTime, 0)
            if rawInterval > Self.rawCallbackStallThreshold {
                reducedRateUntil = max(
                    reducedRateUntil,
                    callbackTime + Self.systemTransitionThrottleDuration
                )
            }
        }
        lastRawCallbackTime = callbackTime
        updateThrottleTargetLocked(at: callbackTime)
    }

    func updateThrottleTargetLocked(at time: CFTimeInterval) {
        let resolvedRate: Double
        switch rateRequest {
        case .followsDisplay:
            resolvedRate = Self.normalTargetFrameRate
        case .fixed(let rate):
            resolvedRate = rate
        }
        let targetFrameRate = time < reducedRateUntil ? Self.reducedTargetFrameRate : resolvedRate
        guard targetFrameRate != currentTargetFrameRate else { return }
        currentTargetFrameRate = targetFrameRate
        throttle.updateTargetFrameRate(targetFrameRate)
        PocketNotchLog.media.debug(
            "Spectrum animation scheduler target=\(targetFrameRate, privacy: .public) FPS"
        )
    }
}
