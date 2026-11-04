import AppKit
import ApplicationServices
import CoreGraphics
import IOKit
import PocketNotchShared

/// 主动接管系统音量键：由 PocketNotch 写入 CoreAudio，并吞掉原始按键事件，避免 macOS 再显示原生音量 OSD。
///
/// 事件 Tap 依赖“辅助功能”权限。没有权限或当前输出设备不支持软件音量时，事件会继续交给系统处理，
/// 因而不会让用户失去原有音量键能力。
@MainActor
final class SystemVolumeKeyInterceptorService {
    private static let permissionRetryCount = 120
    /// Quartz 没有公开 `.systemDefined` 静态成员，使用 IOKit 的 NX_SYSDEFINED 事件类型。
    private static let systemDefinedEventType = CGEventType(rawValue: UInt32(NX_SYSDEFINED))!

    private let volumeController: AudioOutputVolumeProviding
    private let accessibilityTrustChecker: () -> Bool
    private let accessibilityPrompt: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionRetryTask: Task<Void, Never>?
    private var interceptedKeyCodes: Set<Int> = []
    private var isStarted = false

    init(
        volumeController: AudioOutputVolumeProviding,
        accessibilityTrustChecker: @escaping () -> Bool = { AXIsProcessTrusted() },
        accessibilityPrompt: @escaping () -> Void = AccessibilityAuthorization.promptOnceIfNeeded
    ) {
        self.volumeController = volumeController
        self.accessibilityTrustChecker = accessibilityTrustChecker
        self.accessibilityPrompt = accessibilityPrompt
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        guard !isAccessibilityTrusted else {
            installEventTap()
            return
        }

        // 未授权时首次启动已提示过一次系统授权弹窗；此后保留 macOS 原生音量键行为，
        // 并在短时间内低频检测用户手动授权的结果，不再重复弹窗。
        accessibilityPrompt()
        permissionRetryTask = Task { [weak self] in
            for _ in 0..<Self.permissionRetryCount {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self, self.isStarted else { return }
                if self.isAccessibilityTrusted {
                    self.installEventTap()
                    self.permissionRetryTask = nil
                    return
                }
            }
            self?.permissionRetryTask = nil
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        permissionRetryTask?.cancel()
        permissionRetryTask = nil
        interceptedKeyCodes.removeAll()
        uninstallEventTap()
    }

    deinit {
        permissionRetryTask?.cancel()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
    }

    private var isAccessibilityTrusted: Bool {
        accessibilityTrustChecker()
    }

    private func installEventTap() {
        guard isStarted, eventTap == nil else { return }

        let eventMask = CGEventMask(1) << Self.systemDefinedEventType.rawValue
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            PocketNotchLog.media.warning("Unable to install active volume-key event tap")
            return
        }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            PocketNotchLog.media.warning("Unable to create volume-key event tap run-loop source")
            return
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        PocketNotchLog.media.info("System volume-key interception enabled")
    }

    private func uninstallEventTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let interceptor = Unmanaged<SystemVolumeKeyInterceptorService>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        return MainActor.assumeIsolated {
            interceptor.handle(type: type, event: event)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == Self.systemDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let data = UInt32(truncatingIfNeeded: nsEvent.data1)
        let keyCode = Int((data & 0xFFFF_0000) >> 16)
        let keyState = Int((data & 0x0000_FF00) >> 8)

        guard keyCode == Int(NX_KEYTYPE_SOUND_UP)
                || keyCode == Int(NX_KEYTYPE_SOUND_DOWN)
                || keyCode == Int(NX_KEYTYPE_MUTE) else {
            return Unmanaged.passUnretained(event)
        }

        switch keyState {
        case 0xA: // key down（包含长按重复）
            return handleKeyDown(keyCode: keyCode, modifierFlags: nsEvent.modifierFlags, event: event)
        case 0xB: // key up
            guard interceptedKeyCodes.remove(keyCode) != nil else {
                return Unmanaged.passUnretained(event)
            }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(
        keyCode: Int,
        modifierFlags: NSEvent.ModifierFlags,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasOption = modifiers.contains(.option)
        let hasShift = modifiers.contains(.shift)

        // Option + 音量键是系统声音设置快捷键；Command/Control 组合也保留给系统或其他应用。
        if (hasOption && !hasShift) || modifiers.contains(.command) || modifiers.contains(.control) {
            return Unmanaged.passUnretained(event)
        }

        let command: AudioOutputVolumeCommand
        switch keyCode {
        case Int(NX_KEYTYPE_SOUND_UP):
            command = .increase(fineAdjustment: hasOption && hasShift)
        case Int(NX_KEYTYPE_SOUND_DOWN):
            command = .decrease(fineAdjustment: hasOption && hasShift)
        case Int(NX_KEYTYPE_MUTE):
            command = .toggleMute
        default:
            return Unmanaged.passUnretained(event)
        }

        guard volumeController.perform(command) else {
            // HDMI、部分 USB DAC 等设备没有可写的软件音量时，让 macOS 继续处理。
            return Unmanaged.passUnretained(event)
        }
        interceptedKeyCodes.insert(keyCode)
        return nil
    }
}
