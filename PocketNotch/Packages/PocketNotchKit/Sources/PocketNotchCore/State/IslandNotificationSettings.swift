import AppKit
import Combine
import Foundation
import SwiftUI

/// 音量调节提醒在灵动刘海左耳展示的图标样式。
public enum VolumeIconStyle: String, CaseIterable, Identifiable, Sendable {
    case system
    case device

    public var id: String { rawValue }
}

/// 音量条配色样式。
public enum VolumeBarColorStyle: String, CaseIterable, Identifiable, Sendable {
    case standard
    case gradient
    case coverTheme
    case custom

    public var id: String { rawValue }
}

/// 音量条可选颜色（RGB 双精度），便于持久化与跨线程传递。
public struct VolumeBarColor: Equatable, Sendable {
    public static let `default` = VolumeBarColor(red: 1, green: 1, blue: 1)

    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    public init(color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(
            red: resolved.redComponent,
            green: resolved.greenComponent,
            blue: resolved.blueComponent
        )
    }

    public var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    fileprivate var components: [Double] {
        [red, green, blue]
    }

    fileprivate init?(components: [Double]) {
        guard components.count == 3 else { return nil }
        self.init(red: components[0], green: components[1], blue: components[2])
    }
}

/// Island 临时通知的统一用户偏好。各项默认开启，并即时持久化到 UserDefaults。
@MainActor
public final class IslandNotificationSettings: ObservableObject {
    private enum Keys {
        static let powerStatus = "notifications.powerStatusEnabled"
        static let bluetoothConnection = "notifications.bluetoothConnectionEnabled"
        static let songChange = "notifications.songChangeEnabled"
        static let audioOutputChange = "notifications.audioOutputChangeEnabled"
        static let volumeAdjustment = "notifications.volumeAdjustmentEnabled"
        static let brightnessAdjustment = "notifications.brightnessAdjustmentEnabled"
        static let hideSystemVolumeHUD = "notifications.hideSystemVolumeHUD"
        static let hideSystemBrightnessHUD = "notifications.hideSystemBrightnessHUD"
        static let brightnessPercentage = "notifications.brightnessPercentageEnabled"
        static let volumeIconStyle = "notifications.volumeIconStyle"
        static let rightEarBattery = "notifications.rightEarBatteryEnabled"
        static let volumeBarColorStyle = "notifications.volumeBarColorStyle"
        static let volumeBarCustomColor = "notifications.volumeBarCustomColor"
        static let volumeBarCustomGradientEnabled = "notifications.volumeBarCustomGradientEnabled"
        static let volumeBarCustomGradientEndColor = "notifications.volumeBarCustomGradientEndColor"
        static let songChangeDismissalEffect = "notifications.songChangeDismissalEffect"
        static let audioOutputChangeDismissalEffect = "notifications.audioOutputChangeDismissalEffect"
    }

    @Published public var isPowerStatusEnabled: Bool {
        didSet { persist(isPowerStatusEnabled, forKey: Keys.powerStatus) }
    }

    @Published public var isBluetoothConnectionEnabled: Bool {
        didSet { persist(isBluetoothConnectionEnabled, forKey: Keys.bluetoothConnection) }
    }

    @Published public var isSongChangeEnabled: Bool {
        didSet { persist(isSongChangeEnabled, forKey: Keys.songChange) }
    }

    @Published public var isAudioOutputChangeEnabled: Bool {
        didSet { persist(isAudioOutputChangeEnabled, forKey: Keys.audioOutputChange) }
    }

    /// PocketNotch 自身的音量提醒开关。与系统 OSD 隐藏开关相互独立：
    /// 模块侧按「隐藏开 && 提醒开」才接管按键——关掉提醒时按键自动交回系统，
    /// 避免按键被吞掉却没有任何反馈，同时不破坏用户保存的隐藏偏好。
    @Published public var isVolumeAdjustmentEnabled: Bool {
        didSet { persist(isVolumeAdjustmentEnabled, forKey: Keys.volumeAdjustment) }
    }

    /// 亮度键同理，见 `isVolumeAdjustmentEnabled`。
    @Published public var isBrightnessAdjustmentEnabled: Bool {
        didSet { persist(isBrightnessAdjustmentEnabled, forKey: Keys.brightnessAdjustment) }
    }

    /// 接管音量键时吞掉原始按键事件，从而不让 macOS 画出原生音量 OSD。
    /// 实际接管条件是本开关与 `isVolumeAdjustmentEnabled` 同时为真。
    @Published public var isSystemVolumeHUDHidden: Bool {
        didSet { persist(isSystemVolumeHUDHidden, forKey: Keys.hideSystemVolumeHUD) }
    }

    /// 亮度键同理，见 `isSystemVolumeHUDHidden`。
    @Published public var isSystemBrightnessHUDHidden: Bool {
        didSet { persist(isSystemBrightnessHUDHidden, forKey: Keys.hideSystemBrightnessHUD) }
    }

    /// 亮度调节时是否在灵动刘海右耳显示亮度数字。
    @Published public var isBrightnessPercentageEnabled: Bool {
        didSet { persist(isBrightnessPercentageEnabled, forKey: Keys.brightnessPercentage) }
    }

    @Published public var volumeIconStyle: VolumeIconStyle {
        didSet { persist(volumeIconStyle, forKey: Keys.volumeIconStyle) }
    }

    @Published public var isRightEarBatteryEnabled: Bool {
        didSet { persist(isRightEarBatteryEnabled, forKey: Keys.rightEarBattery) }
    }

    @Published public var volumeBarColorStyle: VolumeBarColorStyle {
        didSet { persist(volumeBarColorStyle, forKey: Keys.volumeBarColorStyle) }
    }

    /// 自定义模式的音量条主色。
    @Published public var volumeBarCustomColor: VolumeBarColor {
        didSet { persist(volumeBarCustomColor, forKey: Keys.volumeBarCustomColor) }
    }

    /// 自定义模式是否启用双色渐变；关闭时仅使用 `volumeBarCustomColor` 单色。
    @Published public var isVolumeBarCustomGradientEnabled: Bool {
        didSet {
            persist(isVolumeBarCustomGradientEnabled, forKey: Keys.volumeBarCustomGradientEnabled)
        }
    }

    /// 自定义渐变模式的第二颜色。
    @Published public var volumeBarCustomGradientEndColor: VolumeBarColor {
        didSet {
            persist(volumeBarCustomGradientEndColor, forKey: Keys.volumeBarCustomGradientEndColor)
        }
    }

    @Published public var songChangeDismissalEffect: IslandNotificationDismissalEffect {
        didSet { persist(songChangeDismissalEffect, forKey: Keys.songChangeDismissalEffect) }
    }

    @Published public var audioOutputChangeDismissalEffect: IslandNotificationDismissalEffect {
        didSet { persist(audioOutputChangeDismissalEffect, forKey: Keys.audioOutputChangeDismissalEffect) }
    }

    private let defaults: UserDefaults?

    /// 传入 `nil` 可创建不持久化、全部默认开启的实例，便于预览与测试。
    public init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        isPowerStatusEnabled = Self.storedBool(forKey: Keys.powerStatus, defaults: defaults)
        isBluetoothConnectionEnabled = Self.storedBool(forKey: Keys.bluetoothConnection, defaults: defaults)
        isSongChangeEnabled = Self.storedBool(forKey: Keys.songChange, defaults: defaults)
        isAudioOutputChangeEnabled = Self.storedBool(forKey: Keys.audioOutputChange, defaults: defaults)
        isVolumeAdjustmentEnabled = Self.storedBool(forKey: Keys.volumeAdjustment, defaults: defaults)
        isBrightnessAdjustmentEnabled = Self.storedBool(
            forKey: Keys.brightnessAdjustment,
            defaults: defaults
        )
        isSystemVolumeHUDHidden = Self.storedBool(forKey: Keys.hideSystemVolumeHUD, defaults: defaults)
        isSystemBrightnessHUDHidden = Self.storedBool(
            forKey: Keys.hideSystemBrightnessHUD,
            defaults: defaults
        )
        isBrightnessPercentageEnabled = Self.storedBool(
            forKey: Keys.brightnessPercentage,
            defaults: defaults
        )
        volumeIconStyle = Self.storedVolumeIconStyle(forKey: Keys.volumeIconStyle, defaults: defaults)
        isRightEarBatteryEnabled = Self.storedBool(forKey: Keys.rightEarBattery, defaults: defaults)
        volumeBarColorStyle = Self.storedVolumeBarColorStyle(
            forKey: Keys.volumeBarColorStyle,
            defaults: defaults
        )
        volumeBarCustomColor = Self.storedVolumeBarColor(
            forKey: Keys.volumeBarCustomColor,
            defaults: defaults,
            fallback: .default
        )
        isVolumeBarCustomGradientEnabled = Self.storedBool(
            forKey: Keys.volumeBarCustomGradientEnabled,
            defaults: defaults
        )
        volumeBarCustomGradientEndColor = Self.storedVolumeBarColor(
            forKey: Keys.volumeBarCustomGradientEndColor,
            defaults: defaults,
            fallback: .default
        )
        songChangeDismissalEffect = Self.storedDismissalEffect(
            forKey: Keys.songChangeDismissalEffect,
            defaults: defaults
        )
        audioOutputChangeDismissalEffect = Self.storedDismissalEffect(
            forKey: Keys.audioOutputChangeDismissalEffect,
            defaults: defaults
        )
    }

    public var enabledNotificationCount: Int {
        [
            isPowerStatusEnabled,
            isBluetoothConnectionEnabled,
            isSongChangeEnabled,
            isAudioOutputChangeEnabled,
            isVolumeAdjustmentEnabled,
            isBrightnessAdjustmentEnabled,
        ].filter { $0 }.count
    }

    private func persist(_ value: Bool, forKey key: String) {
        defaults?.set(value, forKey: key)
    }

    private func persist(_ value: IslandNotificationDismissalEffect, forKey key: String) {
        defaults?.set(value.rawValue, forKey: key)
    }

    private func persist(_ value: VolumeIconStyle, forKey key: String) {
        defaults?.set(value.rawValue, forKey: key)
    }

    private func persist(_ value: VolumeBarColorStyle, forKey key: String) {
        defaults?.set(value.rawValue, forKey: key)
    }

    private func persist(_ value: VolumeBarColor, forKey key: String) {
        defaults?.set(value.components, forKey: key)
    }

    private static func storedBool(forKey key: String, defaults: UserDefaults?) -> Bool {
        guard let defaults, defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }

    private static func storedVolumeIconStyle(forKey key: String, defaults: UserDefaults?) -> VolumeIconStyle {
        guard let rawValue = defaults?.string(forKey: key) else { return .system }
        return VolumeIconStyle(rawValue: rawValue) ?? .system
    }

    private static func storedVolumeBarColorStyle(
        forKey key: String,
        defaults: UserDefaults?
    ) -> VolumeBarColorStyle {
        guard let rawValue = defaults?.string(forKey: key) else { return .standard }
        return VolumeBarColorStyle(rawValue: rawValue) ?? .standard
    }

    private static func storedVolumeBarColor(
        forKey key: String,
        defaults: UserDefaults?,
        fallback: VolumeBarColor
    ) -> VolumeBarColor {
        guard let components = defaults?.array(forKey: key) as? [Double],
              let color = VolumeBarColor(components: components) else {
            return fallback
        }
        return color
    }

    private static func storedDismissalEffect(
        forKey key: String,
        defaults: UserDefaults?
    ) -> IslandNotificationDismissalEffect {
        guard let rawValue = defaults?.string(forKey: key) else { return .standard }
        return IslandNotificationDismissalEffect(rawValue: rawValue) ?? .standard
    }

    public func resetToDefault() {
        isPowerStatusEnabled = true
        isBluetoothConnectionEnabled = true
        isSongChangeEnabled = true
        isAudioOutputChangeEnabled = true
        isVolumeAdjustmentEnabled = true
        isBrightnessAdjustmentEnabled = true
        isSystemVolumeHUDHidden = true
        isSystemBrightnessHUDHidden = true
        isBrightnessPercentageEnabled = true
        volumeIconStyle = .system
        isRightEarBatteryEnabled = true
        volumeBarColorStyle = .standard
        volumeBarCustomColor = .default
        isVolumeBarCustomGradientEnabled = false
        volumeBarCustomGradientEndColor = .default
        songChangeDismissalEffect = .standard
        audioOutputChangeDismissalEffect = .standard
    }

    public var usesDefaultValues: Bool {
        isPowerStatusEnabled
            && isBluetoothConnectionEnabled
            && isSongChangeEnabled
            && isAudioOutputChangeEnabled
            && isVolumeAdjustmentEnabled
            && isBrightnessAdjustmentEnabled
            && isSystemVolumeHUDHidden
            && isSystemBrightnessHUDHidden
            && isBrightnessPercentageEnabled
            && volumeIconStyle == .system
            && isRightEarBatteryEnabled
            && volumeBarColorStyle == .standard
            && volumeBarCustomColor == .default
            && !isVolumeBarCustomGradientEnabled
            && volumeBarCustomGradientEndColor == .default
            && songChangeDismissalEffect == .standard
            && audioOutputChangeDismissalEffect == .standard
    }
}
