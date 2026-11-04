import AppKit
import ApplicationServices
import CoreGraphics
import IOKit
import PocketNotchShared

/// 亮度键拦截器的抽象，供 ViewModel 依赖注入与测试替换。
@MainActor
protocol BrightnessKeyIntercepting: AnyObject {
    func start()
    func stop()
}

/// 主动接管系统亮度键：由 PocketNotch 写入系统亮度，并吞掉原始按键事件，
/// 避免 macOS 再显示原生亮度 OSD。
///
/// 事件 Tap 依赖“辅助功能”权限。没有权限时事件会继续交给系统处理，
/// 因而不会让用户失去原有亮度键能力。
///
/// 同时监听两种亮度键通道，任一命中都会拦截：
/// - 系统媒体键（`NX_SYSDEFINED`，亮度上/下 = keyCode 12/11）；F 键作为标准功能键时
///   按 `Fn+亮度键` 仍走此通道，因此该分支始终有效。
/// - 裸功能键（`keyDown`/`keyUp`，候选键为 `kVK_F2`=120 上 / `kVK_F1`=122 下）。
///   部分机型/设置下亮度键以普通按键事件到达，单独监听媒体键会完全收不到事件。
@MainActor
final class BrightnessKeyInterceptorService: BrightnessKeyIntercepting {
    private static let permissionRetryCount = 120
    /// Quartz 没有公开 `.systemDefined` 静态成员，使用 IOKit 的 NX_SYSDEFINED 事件类型。
    private static let systemDefinedEventType = CGEventType(rawValue: UInt32(NX_SYSDEFINED))!
    /// 裸功能键通道：kVK_F2 = 0x78 = 120（亮度上）、kVK_F1 = 0x7A = 122（亮度下）。
    private static let functionKeyBrightnessUpKeyCode = 120
    private static let functionKeyBrightnessDownKeyCode = 122

    private let brightnessController: BrightnessProviding
    private let onPerformed: () -> Void
    private let accessibilityTrustChecker: () -> Bool
    private let accessibilityPrompt: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionRetryTask: Task<Void, Never>?
    private var interceptedKeyCodes: Set<Int> = []
    private var isStarted = false

    init(
        brightnessController: BrightnessProviding,
        onPerformed: @escaping () -> Void = {},
        accessibilityTrustChecker: @escaping () -> Bool = { AXIsProcessTrusted() },
        accessibilityPrompt: @escaping () -> Void = AccessibilityAuthorization.promptOnceIfNeeded
    ) {
        self.brightnessController = brightnessController
        self.onPerformed = onPerformed
        self.accessibilityTrustChecker = accessibilityTrustChecker
        self.accessibilityPrompt = accessibilityPrompt
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        // 启动时不主动弹出「辅助功能」授权窗，避免打扰用户。仅静默读取授权状态：
        // 已授权则立即接管亮度键；未授权则保留 macOS 原生亮度键行为，并低频检测用户
        // 手动授权的结果，授权后自动接管。需要弹窗的入口由调用方按需触发。
        PocketNotchLog.system.info(
            "Brightness-key interceptor start: accessibilityTrusted=\(self.isAccessibilityTrusted, privacy: .public)"
        )
        guard !isAccessibilityTrusted else {
            installEventTap()
            return
        }

        PocketNotchLog.system.info("Brightness-key interception awaiting accessibility permission")
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
            PocketNotchLog.system.info(
                "Brightness-key interceptor: accessibility not granted within retry window; keys fall through to macOS"
            )
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

        let eventMask = (CGEventMask(1) << Self.systemDefinedEventType.rawValue)
            | CGEventMask(NX_KEYDOWNMASK | NX_KEYUPMASK)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            PocketNotchLog.system.warning("Unable to install active brightness-key event tap")
            return
        }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            PocketNotchLog.system.warning("Unable to create brightness-key event tap run-loop source")
            return
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        PocketNotchLog.system.info("System brightness-key interception enabled")
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
        let interceptor = Unmanaged<BrightnessKeyInterceptorService>
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

        switch type {
        case .keyDown, .keyUp:
            return handleFunctionKey(type: type, event: event)
        case Self.systemDefinedEventType:
            return handleSystemDefinedKey(event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// 裸功能键通道：按 `kVK_F1`/`kVK_F2` 识别亮度方向。
    private func handleFunctionKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let brightnessKeyCode: Int
        switch keyCode {
        case Self.functionKeyBrightnessUpKeyCode:
            brightnessKeyCode = Int(NX_KEYTYPE_BRIGHTNESS_UP)
        case Self.functionKeyBrightnessDownKeyCode:
            brightnessKeyCode = Int(NX_KEYTYPE_BRIGHTNESS_DOWN)
        default:
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            PocketNotchLog.system.info(
                "Brightness key received (function-key channel): rawKeyCode=\(keyCode, privacy: .public)"
            )
            guard let nsEvent = NSEvent(cgEvent: event) else {
                return Unmanaged.passUnretained(event)
            }
            return handleBrightnessKeyDown(
                keyCode: brightnessKeyCode,
                modifierFlags: nsEvent.modifierFlags,
                event: event
            )
        case .keyUp:
            PocketNotchLog.system.info(
                "Brightness key received (function-key channel, key up): rawKeyCode=\(keyCode, privacy: .public)"
            )
            guard interceptedKeyCodes.remove(brightnessKeyCode) != nil else {
                return Unmanaged.passUnretained(event)
            }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// 媒体键通道：`NX_SYSDEFINED` 子类型 8，亮度上/下 = keyCode 12/11。
    private func handleSystemDefinedKey(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let data = UInt32(truncatingIfNeeded: nsEvent.data1)
        let keyCode = Int((data & 0xFFFF_0000) >> 16)
        let keyState = Int((data & 0x0000_FF00) >> 8)

        guard keyCode == Int(NX_KEYTYPE_BRIGHTNESS_UP)
                || keyCode == Int(NX_KEYTYPE_BRIGHTNESS_DOWN) else {
            return Unmanaged.passUnretained(event)
        }

        switch keyState {
        case 0xA: // key down（包含长按重复）
            PocketNotchLog.system.info(
                "Brightness key received (media-key channel): keyCode=\(keyCode, privacy: .public), state=0xA"
            )
            return handleBrightnessKeyDown(
                keyCode: keyCode,
                modifierFlags: nsEvent.modifierFlags,
                event: event
            )
        case 0xB: // key up
            PocketNotchLog.system.info(
                "Brightness key received (media-key channel): keyCode=\(keyCode, privacy: .public), state=0xB"
            )
            guard interceptedKeyCodes.remove(keyCode) != nil else {
                return Unmanaged.passUnretained(event)
            }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleBrightnessKeyDown(
        keyCode: Int,
        modifierFlags: NSEvent.ModifierFlags,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasOption = modifiers.contains(.option)
        let hasShift = modifiers.contains(.shift)

        // Command/Control 组合保留给系统或其他应用；Option 单独按下也放行，避免抢占未来系统快捷键。
        if modifiers.contains(.command) || modifiers.contains(.control) || (hasOption && !hasShift) {
            return Unmanaged.passUnretained(event)
        }

        let command: BrightnessCommand
        switch keyCode {
        case Int(NX_KEYTYPE_BRIGHTNESS_UP):
            command = .increase(fineAdjustment: hasOption && hasShift)
        case Int(NX_KEYTYPE_BRIGHTNESS_DOWN):
            command = .decrease(fineAdjustment: hasOption && hasShift)
        default:
            return Unmanaged.passUnretained(event)
        }

        guard brightnessController.perform(command) else {
            PocketNotchLog.system.warning(
                "Unable to apply brightness \(keyCode == Int(NX_KEYTYPE_BRIGHTNESS_UP) ? "increase" : "decrease"); key passed to system"
            )
            return Unmanaged.passUnretained(event)
        }
        PocketNotchLog.system.info(
            "Brightness \(keyCode == Int(NX_KEYTYPE_BRIGHTNESS_UP) ? "increase" : "decrease") applied (fine=\(hasOption && hasShift, privacy: .public)); event swallowed"
        )
        interceptedKeyCodes.insert(keyCode)
        onPerformed()
        return nil
    }
}