import AppKit
import CoreGraphics
import Foundation

/// 全局屏幕刷新率：动态跟踪当前显示环境的最高刷新率，作为 PocketNotch 所有自驱动动画的默认目标帧率。
///
/// 取所有已连接屏幕 `maximumRefreshRate` 的最大值（多显示器合成节奏以最高者为准）；
/// 无可读值（固定刷新率屏幕或无屏幕）回退 60。显示器热插拔、分辨率切换、睡眠唤醒时自动重读，
/// 变化后主线程派发通知给观察者。
public final class DisplayRefreshRateMonitor {
    public static let shared = DisplayRefreshRateMonitor()

    private let lock = NSLock()
    private var _refreshRate: Double
    private var observers: [UUID: (Double) -> Void] = [:]
    private var appScreenObserver: NSObjectProtocol?
    private var workspaceScreenObservers: [NSObjectProtocol] = []

    /// 当前屏幕最高刷新率（FPS）。线程安全。
    public var refreshRate: Double {
        lock.lock()
        defer { lock.unlock() }
        return _refreshRate
    }

    /// `SCNView.preferredFramesPerSecond` 等整型帧率接口的便捷取值。
    public var preferredFramesPerSecond: Int {
        Int(refreshRate.rounded())
    }

    private init() {
        _refreshRate = Self.resolveRefreshRate(Self.screenRefreshRates())
        observeScreenChanges()
    }

    deinit {
        if let appScreenObserver {
            NotificationCenter.default.removeObserver(appScreenObserver)
        }
        workspaceScreenObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    /// 注册刷新率变化回调（主线程派发，仅在值变化时触发）。返回用于注销的 token。
    public func observe(_ handler: @escaping (Double) -> Void) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let token = UUID()
        observers[token] = handler
        return token
    }

    public func removeObserver(_ token: UUID) {
        lock.lock()
        defer { lock.unlock() }
        observers.removeValue(forKey: token)
    }

    /// 从各屏幕 maximumRefreshRate 中取最大有效值；无有效值回退 60。
    nonisolated static func resolveRefreshRate(_ screenRates: [Int?]) -> Double {
        let highest = screenRates.compactMap { $0 }.filter { $0 > 0 }.max()
        return highest.map(Double.init) ?? 60
    }

    /// 从各屏幕 `CGDisplayMode` 读取最高刷新率；无可读值返回 nil。
    private static func screenRefreshRates() -> [Int?] {
        NSScreen.screens.map { screen in
            let screenID = (
                screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber
            )?.uint32Value
            guard let screenID,
                  let mode = CGDisplayCopyDisplayMode(screenID) else {
                return nil
            }
            let rate = mode.refreshRate
            guard rate.isFinite, rate > 0 else { return nil }
            return Int(rate.rounded())
        }
    }

    private func observeScreenChanges() {
        let notificationCenter = NotificationCenter.default
        appScreenObserver = notificationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceScreenObservers = [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.didWakeNotification
        ].map { name in
            workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
        }
    }

    private func refresh() {
        let newRate = Self.resolveRefreshRate(Self.screenRefreshRates())

        lock.lock()
        let changed = newRate != _refreshRate
        _refreshRate = newRate
        let handlers = Array(observers.values)
        lock.unlock()

        guard changed else { return }
        handlers.forEach { $0(newRate) }
    }
}