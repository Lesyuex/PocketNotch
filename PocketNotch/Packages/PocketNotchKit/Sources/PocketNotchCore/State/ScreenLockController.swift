import AppKit
import Combine
import Foundation

public enum ScreenLockPhase: Equatable, Sendable {
    case unlocked
    case locked
    case unlocking
}

/// 屏幕锁定状态的单一真相来源：向岛提供锁屏/解锁图标相位，并播放对应音效。
///
/// 锁屏通知与会话切换的通知到达顺序在不同 macOS 版本上并不稳定，
/// 因此会话失活时用一段短轮询兜底，唤醒/会话恢复时再与系统会话字典核对一次。
@MainActor
public final class ScreenLockController: ObservableObject {
    @Published public private(set) var phase: ScreenLockPhase = .unlocked

    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var unlockConfirmationTask: Task<Void, Never>?
    private var lockReconcileTask: Task<Void, Never>?
    private var lockedStateMonitorTask: Task<Void, Never>?
    private var wakeConfirmationTask: Task<Void, Never>?
    private var lockSound: NSSound?
    private var unlockSound: NSSound?
    private var isStarted = false

    public init() {}

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        observeLockNotifications()
        observeWorkspaceNotifications()
        if Self.sessionScreenLockedState() == true {
            phase = .locked
            startLockedStateMonitor()
        } else {
            phase = .unlocked
        }
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false

        let distributedCenter = DistributedNotificationCenter.default()
        distributedObservers.forEach { distributedCenter.removeObserver($0) }
        distributedObservers.removeAll()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
        workspaceObservers.removeAll()

        lockReconcileTask?.cancel()
        lockReconcileTask = nil
        lockedStateMonitorTask?.cancel()
        lockedStateMonitorTask = nil
        wakeConfirmationTask?.cancel()
        wakeConfirmationTask = nil
        unlockConfirmationTask?.cancel()
        unlockConfirmationTask = nil
        lockSound?.stop()
        unlockSound?.stop()
    }

    private func observeLockNotifications() {
        let distributedCenter = DistributedNotificationCenter.default()
        distributedObservers = [
            Self.screenDidLockNotification,
            Self.screenDidUnlockNotification,
            Self.screenLockUIIsShownNotification,
            Self.screenLockUIIsHiddenNotification,
            Self.screenSaverDidStartNotification,
            Self.screenSaverDidStopNotification,
        ].map { name in
            distributedCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    self?.handleDistributedNotification(notification.name)
                }
            }
        }
    }

    private func observeWorkspaceNotifications() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        workspaceObservers = names.map { name in
            workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    self?.handleWorkspaceNotification(notification.name)
                }
            }
        }
    }

    private func handleDistributedNotification(_ name: Notification.Name) {
        switch name {
        case Self.screenDidLockNotification:
            markLocked()
        case Self.screenDidUnlockNotification:
            markUnlocking()
        case Self.screenLockUIIsShownNotification:
            scheduleLockReconciliation()
        case Self.screenLockUIIsHiddenNotification:
            reconcileWithSession()
        case Self.screenSaverDidStartNotification:
            scheduleLockReconciliation()
        case Self.screenSaverDidStopNotification:
            reconcileWithSession()
        default:
            break
        }
    }

    private func handleWorkspaceNotification(_ name: NSNotification.Name) {
        switch name {
        case NSWorkspace.sessionDidResignActiveNotification:
            scheduleLockReconciliation()
        case NSWorkspace.sessionDidBecomeActiveNotification:
            markUnlocking()
        case NSWorkspace.screensDidWakeNotification,
             NSWorkspace.didWakeNotification:
            reconcileWithSession()
            startWakeLockConfirmation()
        case NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification:
            lockReconcileTask?.cancel()
            lockReconcileTask = nil
            wakeConfirmationTask?.cancel()
            wakeConfirmationTask = nil
        default:
            break
        }
    }

    private func markLocked(playSound: Bool = true) {
        lockReconcileTask?.cancel()
        lockReconcileTask = nil
        unlockConfirmationTask?.cancel()
        unlockConfirmationTask = nil

        guard phase != .locked else { return }
        phase = .locked
        if playSound {
            playLockSound()
        }
        startLockedStateMonitor()
    }

    private func markUnlocking() {
        lockReconcileTask?.cancel()
        lockReconcileTask = nil
        lockedStateMonitorTask?.cancel()
        lockedStateMonitorTask = nil

        guard phase == .locked else { return }
        phase = .unlocking
        playUnlockSound()

        unlockConfirmationTask?.cancel()
        unlockConfirmationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(820))
            guard !Task.isCancelled, let self, self.phase == .unlocking else { return }
            self.unlockConfirmationTask = nil
            self.phase = .unlocked
        }
    }

    /// 解锁通知偶发丢失时仍然要撤销锁屏窗口层级，避免岛一直压在登录层之上。
    private func startLockedStateMonitor() {
        lockedStateMonitorTask?.cancel()
        lockedStateMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                guard self.phase == .locked else { return }
                if Self.sessionScreenLockedState() == false {
                    self.markUnlocking()
                    return
                }
            }
        }
    }

    /// 让外部（如锁屏音乐组件）在展示前主动核对一次真实锁屏状态。
    public func reconcileLockStateFromSession() {
        reconcileWithSession()
    }

    private func reconcileWithSession() {
        guard let isLocked = Self.sessionScreenLockedState() else { return }
        if isLocked {
            markLocked()
        } else if phase == .locked {
            markUnlocking()
        }
    }

    /// 唤醒瞬间系统会话字典可能仍报告「已锁定」；用短间隔轮询尽快确认解锁，
    /// 避免依赖锁屏组件刷新或 500ms 兜底轮询造成视觉延迟。
    private func startWakeLockConfirmation() {
        wakeConfirmationTask?.cancel()
        wakeConfirmationTask = Task { [weak self] in
            for _ in 0..<Self.wakeConfirmationAttempts {
                try? await Task.sleep(for: Self.wakeConfirmationInterval)
                guard !Task.isCancelled, let self, self.phase == .locked else { return }
                if Self.sessionScreenLockedState() == false {
                    self.markUnlocking()
                    return
                }
            }
            self?.wakeConfirmationTask = nil
        }
    }

    private func scheduleLockReconciliation() {
        lockReconcileTask?.cancel()
        lockReconcileTask = Task { [weak self] in
            for delay in Self.lockReconcileDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                if Self.sessionScreenLockedState() == true {
                    self.markLocked()
                    return
                }
            }
            self?.lockReconcileTask = nil
        }
    }

    private func playLockSound() {
        if lockSound == nil {
            lockSound = Self.makeSound(file: "lock", fallbackName: "Pop")
        }
        lockSound?.stop()
        lockSound?.play()
    }

    private func playUnlockSound() {
        if unlockSound == nil {
            unlockSound = Self.makeSound(file: "unlock", fallbackName: "Tink")
        }
        unlockSound?.stop()
        unlockSound?.play()
    }

    private static func makeSound(file: String, fallbackName: String) -> NSSound? {
        let url = URL(fileURLWithPath: lockScreenSoundDirectory)
            .appendingPathComponent("\(file).aif")
        if let sound = NSSound(contentsOf: url, byReference: true) {
            return sound
        }
        return NSSound(named: NSSound.Name(fallbackName))
    }

    private static func sessionScreenLockedState() -> Bool? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return nil
        }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private static let lockScreenSoundDirectory =
        "/System/Library/Frameworks/SecurityInterface.framework/Versions/A/Resources"
    private static let screenDidLockNotification = Notification.Name("com.apple.screenIsLocked")
    private static let screenDidUnlockNotification = Notification.Name("com.apple.screenIsUnlocked")
    private static let screenLockUIIsShownNotification = Notification.Name("com.apple.screenLockUIIsShown")
    private static let screenLockUIIsHiddenNotification = Notification.Name("com.apple.screenLockUIIsHidden")
    private static let screenSaverDidStartNotification = Notification.Name("com.apple.screensaver.didstart")
    private static let screenSaverDidStopNotification = Notification.Name("com.apple.screensaver.didstop")
    private static let wakeConfirmationInterval: Duration = .milliseconds(100)
    private static let wakeConfirmationAttempts = 30
    private static let lockReconcileDelays: [Duration] = [
        .milliseconds(120),
        .milliseconds(220),
        .milliseconds(360),
        .milliseconds(600),
        .milliseconds(1_000),
        .milliseconds(1_500),
    ]
}
