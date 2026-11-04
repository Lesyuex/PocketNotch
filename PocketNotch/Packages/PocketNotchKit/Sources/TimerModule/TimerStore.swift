import AppKit
import Foundation
import Observation

/// 计时器状态机：倒计时 + 正计时（秒表）。
///
/// 仅在「运行中」驱动一个显示节拍器，暂停 / 空闲 / 结束立即停表（耗电铁律）。
/// 计时基于绝对墙钟时刻推导，跨睡眠、挂起与界面显示/隐藏都不会漂移。
@MainActor
@Observable
public final class TimerStore {
    public enum Mode: String, CaseIterable, Sendable {
        /// 从设定时长倒数到 0。
        case countdown
        /// 秒表，从 0 累加。
        case stopwatch
    }

    public enum RunState: Sendable {
        case idle
        case running
        case paused
        /// 倒计时归零后的完成态。
        case finished
    }

    /// 倒计时可调范围与步进（秒）。
    public static let countdownMinimum: TimeInterval = 0.01
    public static let countdownMaximum: TimeInterval = 99 * 3600
    public static let countdownStep: TimeInterval = 60
    public static let defaultCountdown: TimeInterval = 5 * 60

    public private(set) var mode: Mode = .countdown
    public private(set) var runState: RunState = .idle
    /// 倒计时设定时长（秒）；0 表示尚未输入。
    public private(set) var countdownDuration: TimeInterval = 0
    /// 倒计时剩余（秒）。
    public private(set) var remaining: TimeInterval = 0
    /// 正计时已累计（秒）。
    public private(set) var elapsed: TimeInterval = 0
    /// 秒表分段时长（秒），按记录顺序保存。
    public private(set) var laps: [TimeInterval] = []

    /// 倒计时完成后的临时上岛通知态；非 nil 时由 TimerModule 暴露为 compact 临时通知。
    public private(set) var completionPresentation: TimerCompletionPresentation?
    private var completionDismissTask: Task<Void, Never>?
    private static let completionDisplayDuration: Duration = .seconds(3)

    /// 当前自定义名称；空表示用模式默认标题（倒计时 / 秒表）。
    public private(set) var name: String = ""

    private static let tickInterval: TimeInterval = 0.25

    private var displayTimer: Timer?
    /// 运行中的绝对基准：倒计时为到期时刻，正计时为「零点的墙钟时刻」。
    private var anchor: Date?

    public init() {}

    // MARK: - 查询

    /// 当前应展示的秒数（倒计时显示剩余，正计时显示已累计）。
    public var displayedSeconds: TimeInterval {
        switch mode {
        case .countdown: remaining
        case .stopwatch: elapsed
        }
    }

    public var isRunning: Bool { runState == .running }

    /// 倒计时处于未开始的空闲态（可输入时长）。
    public var isCountdownIdle: Bool { mode == .countdown && runState == .idle }

    /// 倒计时尚未输入时长：启动前需要先让用户输入。
    public var needsCountdownInput: Bool {
        mode == .countdown && runState == .idle && countdownDuration <= 0
    }

    // MARK: - 操作

    /// 切换模式：运行中忽略；否则停止并把该模式归位到空闲态。
    public func setMode(_ mode: Mode) {
        guard mode != self.mode, runState != .running else { return }
        stopTicker()
        clearCompletionPresentation()
        self.mode = mode
        runState = .idle
        anchor = nil
        remaining = countdownDuration
        elapsed = 0
        laps.removeAll()
    }

    public func toggle() {
        switch runState {
        case .running:
            pause()
        case .idle, .paused:
            start()
        case .finished:
            remaining = countdownDuration
            start()
        }
    }

    public func start() {
        guard runState != .running else { return }
        clearCompletionPresentation()
        switch mode {
        case .countdown:
            guard countdownDuration > 0 else { return }
            if remaining <= 0 { remaining = countdownDuration }
            anchor = Date().addingTimeInterval(remaining)
        case .stopwatch:
            anchor = Date().addingTimeInterval(-elapsed)
        }
        runState = .running
        startTicker()
        refresh()
    }

    public func pause() {
        guard runState == .running else { return }
        stopTicker()
        refresh()
        anchor = nil
        runState = .paused
    }

    /// 重置：清空已输入时长与累计时间，回到「没有时间」的初始态。
    public func reset() {
        stopTicker()
        anchor = nil
        clearCompletionPresentation()
        runState = .idle
        if mode == .countdown {
            countdownDuration = 0
            remaining = 0
        }
        elapsed = 0
        laps.removeAll()
    }

    /// 写入倒计时时长（仅倒计时未运行时允许）。
    public func setCountdownDuration(_ seconds: TimeInterval) {
        guard mode == .countdown, runState != .running else { return }
        guard seconds >= Self.countdownMinimum else { return }
        clearCompletionPresentation()
        let clamped = (min(seconds, Self.countdownMaximum) * 100).rounded() / 100
        countdownDuration = clamped
        remaining = clamped
        if runState == .finished { runState = .idle }
    }

    /// 按分钟调整刚输入的倒计时时长（仅倒计时未运行时允许）。
    public func adjustCountdown(by delta: TimeInterval) {
        guard mode == .countdown, runState != .running else { return }
        clearCompletionPresentation()
        let base = countdownDuration > 0 ? countdownDuration : Self.defaultCountdown
        let updated = min(max(base + delta, Self.countdownMinimum), Self.countdownMaximum)
        countdownDuration = updated
        remaining = updated
        if runState == .finished { runState = .idle }
    }

    /// 为正在运行或暂停的倒计时加时；只影响本次倒计时。
    public func extendCountdown(by delta: TimeInterval) {
        guard mode == .countdown, delta > 0 else { return }
        guard runState == .running || runState == .paused else { return }

        let now = Date()
        let current = runState == .running
            ? max((anchor ?? now).timeIntervalSince(now), 0)
            : max(remaining, 0)
        let updated = min(current + delta, Self.countdownMaximum)

        remaining = updated
        if runState == .running {
            anchor = now.addingTimeInterval(updated)
        }
    }

    /// 记录一段秒表分段（从启动到记录点的累计时长）；仅秒表运行中有效。
    public func recordLap() {
        guard mode == .stopwatch, runState == .running else { return }
        laps.append(max(elapsed, 0))
    }

    /// 停止计时并释放节拍器（模块停用 / 退出时调用）。
    public func stop() {
        stopTicker()
        anchor = nil
    }

    // MARK: - 节拍

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func stopTicker() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func refresh() {
        guard let anchor else { return }
        switch mode {
        case .countdown:
            let left = anchor.timeIntervalSinceNow
            if left <= 0 {
                remaining = 0
                finish()
            } else {
                remaining = left
            }
        case .stopwatch:
            elapsed = Date().timeIntervalSince(anchor)
        }
    }

    private func finish() {
        stopTicker()
        anchor = nil
        runState = .finished
        presentCompletion()
        if let sound = NSSound(named: "Glass") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func presentCompletion() {
        completionPresentation = TimerCompletionPresentation(duration: countdownDuration)
        completionDismissTask?.cancel()
        completionDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.completionDisplayDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.completionPresentation = nil
            self?.completionDismissTask = nil
        }
    }

    private func clearCompletionPresentation() {
        completionDismissTask?.cancel()
        completionDismissTask = nil
        completionPresentation = nil
    }

    /// 更新当前自定义名称（由卡片重命名提交时同步）。
    public func updateName(_ value: String) {
        name = value
    }
}

/// 倒计时完成时上岛临时通知的载荷；保留原时长以备文案扩展。
public struct TimerCompletionPresentation: Sendable, Equatable {
    public let duration: TimeInterval
    public init(duration: TimeInterval) { self.duration = duration }
}
