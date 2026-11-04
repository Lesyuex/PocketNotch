import AppKit
import Combine
import Foundation
import PocketNotchCore
import SwiftUI

public enum LockScreenMusicBackdropStyle: String, CaseIterable, Identifiable, Sendable {
    case clear
    case glass
    case artworkTheme
    case solidColor

    public var id: Self { self }

    public var title: String {
        switch self {
        case .clear: "Clear"
        case .glass: "Glass"
        case .artworkTheme: "封面主题色"
        case .solidColor: "纯色背景"
        }
    }

    public var description: String {
        switch self {
        case .clear: "清透折射材质"
        case .glass: "系统液态玻璃"
        case .artworkTheme: "封面颜色取色"
        case .solidColor: "自定义颜色"
        }
    }
}

public enum MusicSpectrumBarStyle: String, CaseIterable, Identifiable, Sendable {
    case four
    case five
    // 保留 seven 作为持久化/API 标识；该样式的显示数量已调整为 6 条。
    case seven

    public var id: Self { self }

    public var barCount: Int {
        switch self {
        case .four: 4
        case .five: 5
        case .seven: 6
        }
    }

    public var title: String {
        switch self {
        case .four: "4 条"
        case .five: "5 条"
        case .seven: "6 条"
        }
    }
}

/// 频谱目标更新策略。两种模式均使用 1024 点 FFT；流畅模式只提高 FFT 更新频率，
/// 画面本身仍由渲染器按屏幕刷新率补间。
public enum MusicSpectrumUpdateRate: String, CaseIterable, Identifiable, Sendable {
    case standard
    case smooth

    public var id: Self { self }

    public var title: String {
        switch self {
        case .standard: "30 Fps"
        case .smooth: "60 Fps"
        }
    }

    /// 实际 FFT 目标更新频率；流畅模式约 45 Hz，避免 60 Hz FFT 的额外开销。
    public var fftUpdateRate: Double {
        switch self {
        case .standard: 30
        case .smooth: 45
        }
    }

    /// 是否跟随全局屏幕刷新率（显示器变化时自动更新）。
    public var followsDisplayRefreshRate: Bool {
        switch self {
        case .standard: false
        case .smooth: false
        }
    }

    /// 频谱动画目标帧率；标准固定 30 FPS，流畅固定 60 FPS，不跟随屏幕刷新率。
    public var animationFrameRate: Double {
        switch self {
        case .standard: 30
        case .smooth: 60
        }
    }
}

struct MusicSpectrumConfiguration: Equatable, Sendable {
    let style: MusicSpectrumBarStyle
    let updateRate: MusicSpectrumUpdateRate
    let sensitivity: Double
    let attackTime: Double
    let releaseTime: Double
    let rhythmDetail: Double
    let barWidthScale: Double
    let barSpacingScale: Double
    let barCornerRadiusScale: Double

    init(
        style: MusicSpectrumBarStyle,
        updateRate: MusicSpectrumUpdateRate = MediaMonitoringSettings.defaultSpectrumUpdateRate,
        sensitivity: Double,
        attackTime: Double,
        releaseTime: Double,
        rhythmDetail: Double = MediaMonitoringSettings.defaultSpectrumRhythmDetail,
        barWidthScale: Double = 2.5,
        barSpacingScale: Double = 1.6,
        barCornerRadiusScale: Double = 1.0
    ) {
        self.style = style
        self.updateRate = updateRate
        self.sensitivity = sensitivity
        self.attackTime = attackTime
        self.releaseTime = releaseTime
        self.rhythmDetail = rhythmDetail
        self.barWidthScale = barWidthScale
        self.barSpacingScale = barSpacingScale
        self.barCornerRadiusScale = barCornerRadiusScale
    }
}

public struct LockScreenMusicSolidColor: Equatable, Sendable {
    public static let `default` = LockScreenMusicSolidColor(
        red: 0.07,
        green: 0.08,
        blue: 0.11
    )
    public static let defaultText = LockScreenMusicSolidColor(
        red: 1,
        green: 1,
        blue: 1
    )
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    public init(color: Color) {
        let resolvedColor = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(
            red: resolvedColor.redComponent,
            green: resolvedColor.greenComponent,
            blue: resolvedColor.blueComponent
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

/// 媒体模块的用户偏好。设置值即时生效并持久化到 UserDefaults。
@MainActor
public final class MediaMonitoringSettings: ObservableObject {
    public static let defaultSpectrumUpdateRate: MusicSpectrumUpdateRate = .smooth
    public nonisolated static let defaultSpectrumRhythmDetail = 1.0
    public static let compactArtworkCornerRadiusPercentageRange = 0.0...100.0
    public static let lockScreenMusicGlassBlurRange = 0.0...1.0
    public static let musicSpectrumTuningRange = 0.0...1.0
    public static let spectrumAttackReleaseRange = 0.0...1.0
    public nonisolated static let defaultSpectrumAttackTime = 0.7
    public nonisolated static let defaultSpectrumReleaseTime = 0.7
    /// 统一应用于 4/5/6 条频柱的宽度比例。范围经过限制，避免出现过细或挤满容器的布局。
    public nonisolated static let spectrumBarWidthRange = 1.5...3.5
    /// 统一应用于 4/5/6 条频柱的间距比例。
    public nonisolated static let spectrumBarSpacingRange = 1.0...2.2
    /// 统一应用于所有频柱的圆角比例（0 = 直角，1 = 胶囊形）。
    public nonisolated static let spectrumBarCornerRadiusRange = 0.0...1.0

    private enum Keys {
        static let realtimeMusicMonitoringEnabled = "media.realtimeMusicMonitoringEnabled"
        static let compactArtworkRotationEnabled = "media.compactArtworkRotationEnabled"
        static let compactRotatingArtworkCornerRadiusPercentage = "media.compactArtworkCornerRadiusPercentage"
        static let compactStaticArtworkCornerRadiusPercentage = "media.compactStaticArtworkCornerRadiusPercentage"
        static let musicSpectrumBarStyle = "media.musicSpectrumBarStyle"
        static let musicSpectrumUpdateRate = "media.musicSpectrumUpdateRate"
        static let fourBarSpectrumSensitivity = "media.fourBarSpectrumSensitivity"
        static let fourBarSpectrumSmoothnessLegacy = "media.fourBarSpectrumSmoothness"
        static let fourBarSpectrumAttackTime = "media.fourBarSpectrumAttackTime"
        static let fourBarSpectrumReleaseTime = "media.fourBarSpectrumReleaseTime"
        static let fiveBarSpectrumSensitivity = "media.fiveBarSpectrumSensitivity"
        static let fiveBarSpectrumSmoothnessLegacy = "media.fiveBarSpectrumSmoothness"
        static let fiveBarSpectrumAttackTime = "media.fiveBarSpectrumAttackTime"
        static let fiveBarSpectrumReleaseTime = "media.fiveBarSpectrumReleaseTime"
        static let sevenBarSpectrumSensitivity = "media.sevenBarSpectrumSensitivity"
        static let sevenBarSpectrumSmoothnessLegacy = "media.sevenBarSpectrumSmoothness"
        static let sevenBarSpectrumAttackTime = "media.sevenBarSpectrumAttackTime"
        static let sevenBarSpectrumReleaseTime = "media.sevenBarSpectrumReleaseTime"
        static let musicSpectrumRhythmDetail = "media.musicSpectrumRhythmDetail"
        static let fourBarSpectrumWidthScale = "media.fourBarSpectrumWidthScale"
        static let fourBarSpectrumSpacingScale = "media.fourBarSpectrumSpacingScale"
        static let fiveBarSpectrumWidthScale = "media.fiveBarSpectrumWidthScale"
        static let fiveBarSpectrumSpacingScale = "media.fiveBarSpectrumSpacingScale"
        static let sevenBarSpectrumWidthScale = "media.sevenBarSpectrumWidthScale"
        static let sevenBarSpectrumSpacingScale = "media.sevenBarSpectrumSpacingScale"
        static let musicSpectrumCornerRadiusScale = "media.musicSpectrumCornerRadiusScale"
        static let spectrumBarColorMode = "media.spectrumBarColorMode"
        // v2：4/5/6 条频柱共用一套几何设置。
        static let musicSpectrumBarWidthScale = "media.spectrumBarWidthScale"
        static let musicSpectrumBarSpacingScale = "media.spectrumBarSpacingScale"
        static let musicSpectrumBarWidthScaleLegacy = "media.musicSpectrumBarWidthScale"
        static let musicSpectrumBarSpacingScaleLegacy = "media.musicSpectrumBarSpacingScale"
        static let lockScreenMusicEnabled = "media.lockScreenMusicEnabled"
        static let lockScreenMusicBackdropStyle = "media.lockScreenMusicBackdropStyle"
        static let lockScreenMusicGlassBlur = "media.lockScreenMusicGlassBlur"
        static let lockScreenMusicGlassMaterial = "media.lockScreenMusicGlassMaterial"
        static let lockScreenMusicGlassTransparencyLegacy = "media.lockScreenMusicGlassTransparency"
        static let lockScreenMusicSolidColor = "media.lockScreenMusicSolidColor"
        static let lockScreenMusicSolidTextColor = "media.lockScreenMusicSolidTextColor"
        static let lockScreenArtworkGradientEnabled = "media.lockScreenArtworkGradientEnabled"
        static let musicControlAuthorizedApps = "media.musicControlAuthorizedApps"
        static let musicControlDeniedApps = "media.musicControlDeniedApps"
        static let systemAudioCaptureEnabled = "media.systemAudioCaptureEnabled"
        static let bluetoothDeviceMonitoringEnabled = "media.bluetoothDeviceMonitoringEnabled"
    }

    @Published public var isRealtimeMusicMonitoringEnabled: Bool {
        didSet {
            defaults.set(isRealtimeMusicMonitoringEnabled, forKey: Keys.realtimeMusicMonitoringEnabled)
        }
    }

    @Published public var isCompactArtworkRotationEnabled: Bool {
        didSet {
            defaults.set(isCompactArtworkRotationEnabled, forKey: Keys.compactArtworkRotationEnabled)
        }
    }

    @Published public var compactRotatingArtworkCornerRadiusPercentage: Double {
        didSet {
            defaults.set(
                compactRotatingArtworkCornerRadiusPercentage,
                forKey: Keys.compactRotatingArtworkCornerRadiusPercentage
            )
        }
    }

    @Published public var compactStaticArtworkCornerRadiusPercentage: Double {
        didSet {
            defaults.set(
                compactStaticArtworkCornerRadiusPercentage,
                forKey: Keys.compactStaticArtworkCornerRadiusPercentage
            )
        }
    }

    @Published public var musicSpectrumBarStyle: MusicSpectrumBarStyle {
        didSet {
            defaults.set(musicSpectrumBarStyle.rawValue, forKey: Keys.musicSpectrumBarStyle)
        }
    }

    @Published public var musicSpectrumUpdateRate: MusicSpectrumUpdateRate {
        didSet {
            defaults.set(musicSpectrumUpdateRate.rawValue, forKey: Keys.musicSpectrumUpdateRate)
        }
    }

    @Published public var fourBarSpectrumSensitivity: Double {
        didSet {
            defaults.set(fourBarSpectrumSensitivity, forKey: Keys.fourBarSpectrumSensitivity)
        }
    }

    @Published public var fourBarSpectrumAttackTime: Double {
        didSet {
            defaults.set(fourBarSpectrumAttackTime, forKey: Keys.fourBarSpectrumAttackTime)
        }
    }

    @Published public var fourBarSpectrumReleaseTime: Double {
        didSet {
            defaults.set(fourBarSpectrumReleaseTime, forKey: Keys.fourBarSpectrumReleaseTime)
        }
    }

    @Published public var fiveBarSpectrumSensitivity: Double {
        didSet {
            defaults.set(fiveBarSpectrumSensitivity, forKey: Keys.fiveBarSpectrumSensitivity)
        }
    }

    @Published public var fiveBarSpectrumAttackTime: Double {
        didSet {
            defaults.set(fiveBarSpectrumAttackTime, forKey: Keys.fiveBarSpectrumAttackTime)
        }
    }

    @Published public var fiveBarSpectrumReleaseTime: Double {
        didSet {
            defaults.set(fiveBarSpectrumReleaseTime, forKey: Keys.fiveBarSpectrumReleaseTime)
        }
    }

    @Published public var sevenBarSpectrumSensitivity: Double {
        didSet {
            defaults.set(sevenBarSpectrumSensitivity, forKey: Keys.sevenBarSpectrumSensitivity)
        }
    }

    @Published public var sevenBarSpectrumAttackTime: Double {
        didSet {
            defaults.set(sevenBarSpectrumAttackTime, forKey: Keys.sevenBarSpectrumAttackTime)
        }
    }

    @Published public var sevenBarSpectrumReleaseTime: Double {
        didSet {
            defaults.set(sevenBarSpectrumReleaseTime, forKey: Keys.sevenBarSpectrumReleaseTime)
        }
    }

    /// 细微频谱变化的响应程度。仅映射输入死区，目标更新阈值保持固定以避免频繁重启动画。
    @Published public var musicSpectrumRhythmDetail: Double {
        didSet {
            defaults.set(musicSpectrumRhythmDetail, forKey: Keys.musicSpectrumRhythmDetail)
        }
    }

    /// 4/5/6 条频柱共用的宽度比例。
    @Published public var musicSpectrumBarWidthScale: Double {
        didSet { defaults.set(musicSpectrumBarWidthScale, forKey: Keys.musicSpectrumBarWidthScale) }
    }

    /// 4/5/6 条频柱共用的间距比例。
    @Published public var musicSpectrumBarSpacingScale: Double {
        didSet { defaults.set(musicSpectrumBarSpacingScale, forKey: Keys.musicSpectrumBarSpacingScale) }
    }

    // 兼容旧 API：不再单独存储，所有柱数读写同一组值。
    @available(*, deprecated, message: "Use musicSpectrumBarWidthScale")
    public var fourBarSpectrumWidthScale: Double {
        get { musicSpectrumBarWidthScale }
        set { musicSpectrumBarWidthScale = newValue }
    }
    @available(*, deprecated, message: "Use musicSpectrumBarSpacingScale")
    public var fourBarSpectrumSpacingScale: Double {
        get { musicSpectrumBarSpacingScale }
        set { musicSpectrumBarSpacingScale = newValue }
    }
    @available(*, deprecated, message: "Use musicSpectrumBarWidthScale")
    public var fiveBarSpectrumWidthScale: Double {
        get { musicSpectrumBarWidthScale }
        set { musicSpectrumBarWidthScale = newValue }
    }
    @available(*, deprecated, message: "Use musicSpectrumBarSpacingScale")
    public var fiveBarSpectrumSpacingScale: Double {
        get { musicSpectrumBarSpacingScale }
        set { musicSpectrumBarSpacingScale = newValue }
    }
    @available(*, deprecated, message: "Use musicSpectrumBarWidthScale")
    public var sevenBarSpectrumWidthScale: Double {
        get { musicSpectrumBarWidthScale }
        set { musicSpectrumBarWidthScale = newValue }
    }
    @available(*, deprecated, message: "Use musicSpectrumBarSpacingScale")
    public var sevenBarSpectrumSpacingScale: Double {
        get { musicSpectrumBarSpacingScale }
        set { musicSpectrumBarSpacingScale = newValue }
    }

    @Published public var musicSpectrumCornerRadiusScale: Double {
        didSet {
            defaults.set(
                musicSpectrumCornerRadiusScale,
                forKey: Keys.musicSpectrumCornerRadiusScale
            )
        }
    }

    /// 频谱柱取色方案：主色锚定或双色渐变。
    @Published public var spectrumBarColorMode: SpectrumBarColorMode {
        didSet {
            defaults.set(spectrumBarColorMode.rawValue, forKey: Keys.spectrumBarColorMode)
        }
    }

    var musicSpectrumConfiguration: MusicSpectrumConfiguration {
        switch musicSpectrumBarStyle {
        case .four:
            MusicSpectrumConfiguration(
                style: .four,
                updateRate: musicSpectrumUpdateRate,
                sensitivity: fourBarSpectrumSensitivity,
                attackTime: fourBarSpectrumAttackTime,
                releaseTime: fourBarSpectrumReleaseTime,
                rhythmDetail: musicSpectrumRhythmDetail,
                barWidthScale: musicSpectrumBarWidthScale,
                barSpacingScale: musicSpectrumBarSpacingScale,
                barCornerRadiusScale: musicSpectrumCornerRadiusScale
            )
        case .five:
            MusicSpectrumConfiguration(
                style: .five,
                updateRate: musicSpectrumUpdateRate,
                sensitivity: fiveBarSpectrumSensitivity,
                attackTime: fiveBarSpectrumAttackTime,
                releaseTime: fiveBarSpectrumReleaseTime,
                rhythmDetail: musicSpectrumRhythmDetail,
                barWidthScale: musicSpectrumBarWidthScale,
                barSpacingScale: musicSpectrumBarSpacingScale,
                barCornerRadiusScale: musicSpectrumCornerRadiusScale
            )
        case .seven:
            MusicSpectrumConfiguration(
                style: .seven,
                updateRate: musicSpectrumUpdateRate,
                sensitivity: sevenBarSpectrumSensitivity,
                attackTime: sevenBarSpectrumAttackTime,
                releaseTime: sevenBarSpectrumReleaseTime,
                rhythmDetail: musicSpectrumRhythmDetail,
                barWidthScale: musicSpectrumBarWidthScale,
                barSpacingScale: musicSpectrumBarSpacingScale,
                barCornerRadiusScale: musicSpectrumCornerRadiusScale
            )
        }
    }

    @Published public var isLockScreenMusicEnabled: Bool {
        didSet {
            defaults.set(isLockScreenMusicEnabled, forKey: Keys.lockScreenMusicEnabled)
        }
    }

    @Published public var lockScreenMusicBackdropStyle: LockScreenMusicBackdropStyle {
        didSet {
            defaults.set(lockScreenMusicBackdropStyle.rawValue, forKey: Keys.lockScreenMusicBackdropStyle)
        }
    }

    /// Glass 的磨砂程度。0 为完全通透，1 为全磨砂（不透明）；默认值为 100%。
    @Published public var lockScreenMusicGlassBlur: Double {
        didSet {
            defaults.set(lockScreenMusicGlassBlur, forKey: Keys.lockScreenMusicGlassBlur)
        }
    }

    /// 液态玻璃（Clear）采用的玻璃材质变体，默认气泡玻璃。
    @Published public var lockScreenMusicGlassMaterial: LiquidGlassMaterial {
        didSet {
            defaults.set(
                lockScreenMusicGlassMaterial.rawValue,
                forKey: Keys.lockScreenMusicGlassMaterial
            )
        }
    }

    @Published public var lockScreenMusicSolidColor: LockScreenMusicSolidColor {
        didSet {
            defaults.set(
                lockScreenMusicSolidColor.components,
                forKey: Keys.lockScreenMusicSolidColor
            )
        }
    }

    @Published public var lockScreenMusicSolidTextColor: LockScreenMusicSolidColor {
        didSet {
            defaults.set(
                lockScreenMusicSolidTextColor.components,
                forKey: Keys.lockScreenMusicSolidTextColor
            )
        }
    }

    @Published public var isLockScreenArtworkGradientEnabled: Bool {
        didSet {
            defaults.set(
                isLockScreenArtworkGradientEnabled,
                forKey: Keys.lockScreenArtworkGradientEnabled
            )
        }
    }

    /// 已授权 AppleScript（Apple Events）控制的媒体 App 名称，如 "Music"、"Spotify"。
    /// 空数组表示尚未获得任何媒体控制授权。
    @Published public var musicControlAuthorizedApps: [String] {
        didSet {
            defaults.set(musicControlAuthorizedApps, forKey: Keys.musicControlAuthorizedApps)
        }
    }

    /// 用户明确拒绝过的媒体 App 名称，用于在授权窗口展示「已拒绝 / 去系统设置」。
    @Published public var musicControlDeniedApps: [String] {
        didSet {
            defaults.set(musicControlDeniedApps, forKey: Keys.musicControlDeniedApps)
        }
    }

    /// 是否授权 PocketNotch 捕获系统音频（CoreAudio Process Tap）用于频谱显示。
    /// 默认 false：未授权时频谱使用模拟源，绝不在启动时触发系统音频捕获弹窗。
    @Published public var isSystemAudioCaptureEnabled: Bool {
        didSet {
            defaults.set(isSystemAudioCaptureEnabled, forKey: Keys.systemAudioCaptureEnabled)
        }
    }

    /// 是否授权 PocketNotch 监听蓝牙设备连接（IOBluetooth）。默认 false：未授权时不访问
    /// 蓝牙，避免在启动时触发系统蓝牙授权弹窗。
    @Published public var isBluetoothDeviceMonitoringEnabled: Bool {
        didSet {
            defaults.set(isBluetoothDeviceMonitoringEnabled, forKey: Keys.bluetoothDeviceMonitoringEnabled)
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Keys.realtimeMusicMonitoringEnabled) == nil {
            isRealtimeMusicMonitoringEnabled = false
        } else {
            isRealtimeMusicMonitoringEnabled = defaults.bool(forKey: Keys.realtimeMusicMonitoringEnabled)
        }

        if defaults.object(forKey: Keys.compactArtworkRotationEnabled) == nil {
            isCompactArtworkRotationEnabled = false
        } else {
            isCompactArtworkRotationEnabled = defaults.bool(forKey: Keys.compactArtworkRotationEnabled)
        }

        let rotatingCornerRadiusPercentage: Double
        if defaults.object(forKey: Keys.compactRotatingArtworkCornerRadiusPercentage) == nil {
            rotatingCornerRadiusPercentage = 100
        } else {
            rotatingCornerRadiusPercentage = min(
                max(
                    defaults.double(forKey: Keys.compactRotatingArtworkCornerRadiusPercentage),
                    Self.compactArtworkCornerRadiusPercentageRange.lowerBound
                ),
                Self.compactArtworkCornerRadiusPercentageRange.upperBound
            )
        }
        compactRotatingArtworkCornerRadiusPercentage = rotatingCornerRadiusPercentage

        if defaults.object(forKey: Keys.compactStaticArtworkCornerRadiusPercentage) == nil {
            compactStaticArtworkCornerRadiusPercentage = 50
        } else {
            compactStaticArtworkCornerRadiusPercentage = min(
                max(
                    defaults.double(forKey: Keys.compactStaticArtworkCornerRadiusPercentage),
                    Self.compactArtworkCornerRadiusPercentageRange.lowerBound
                ),
                Self.compactArtworkCornerRadiusPercentageRange.upperBound
            )
        }

        let storedSpectrumBarStyle = defaults.string(forKey: Keys.musicSpectrumBarStyle)
            .flatMap(MusicSpectrumBarStyle.init(rawValue:))
            ?? .five
        musicSpectrumBarStyle = storedSpectrumBarStyle
        musicSpectrumUpdateRate = defaults.string(forKey: Keys.musicSpectrumUpdateRate)
            .flatMap(MusicSpectrumUpdateRate.init(rawValue:))
            ?? Self.defaultSpectrumUpdateRate
        fourBarSpectrumSensitivity = Self.storedSpectrumTuning(
            defaults,
            key: Keys.fourBarSpectrumSensitivity,
            defaultValue: 0.5
        )
        let legacyFourSmoothness = Self.storedSpectrumTuningIfPresent(
            defaults,
            key: Keys.fourBarSpectrumSmoothnessLegacy
        )
        fourBarSpectrumAttackTime = Self.storedSpectrumTuning(
            defaults,
            key: Keys.fourBarSpectrumAttackTime,
            defaultValue: legacyFourSmoothness ?? Self.defaultSpectrumAttackTime
        )
        fourBarSpectrumReleaseTime = Self.storedSpectrumTuning(
            defaults,
            key: Keys.fourBarSpectrumReleaseTime,
            defaultValue: legacyFourSmoothness ?? Self.defaultSpectrumReleaseTime
        )
        fiveBarSpectrumSensitivity = Self.storedSpectrumTuning(
            defaults,
            key: Keys.fiveBarSpectrumSensitivity,
            defaultValue: 0.5
        )
        let legacyFiveSmoothness = Self.storedSpectrumTuningIfPresent(
            defaults,
            key: Keys.fiveBarSpectrumSmoothnessLegacy
        )
        fiveBarSpectrumAttackTime = Self.storedSpectrumTuning(
            defaults,
            key: Keys.fiveBarSpectrumAttackTime,
            defaultValue: legacyFiveSmoothness ?? Self.defaultSpectrumAttackTime
        )
        fiveBarSpectrumReleaseTime = Self.storedSpectrumTuning(
            defaults,
            key: Keys.fiveBarSpectrumReleaseTime,
            defaultValue: legacyFiveSmoothness ?? Self.defaultSpectrumReleaseTime
        )
        sevenBarSpectrumSensitivity = Self.storedSpectrumTuning(
            defaults,
            key: Keys.sevenBarSpectrumSensitivity,
            defaultValue: 0.5
        )
        let legacySevenSmoothness = Self.storedSpectrumTuningIfPresent(
            defaults,
            key: Keys.sevenBarSpectrumSmoothnessLegacy
        )
        sevenBarSpectrumAttackTime = Self.storedSpectrumTuning(
            defaults,
            key: Keys.sevenBarSpectrumAttackTime,
            defaultValue: legacySevenSmoothness ?? Self.defaultSpectrumAttackTime
        )
        sevenBarSpectrumReleaseTime = Self.storedSpectrumTuning(
            defaults,
            key: Keys.sevenBarSpectrumReleaseTime,
            defaultValue: legacySevenSmoothness ?? Self.defaultSpectrumReleaseTime
        )
        musicSpectrumRhythmDetail = Self.storedSpectrumTuning(
            defaults,
            key: Keys.musicSpectrumRhythmDetail,
            defaultValue: Self.defaultSpectrumRhythmDetail
        )
        let legacyWidthScale = Self.storedSpectrumTuningIfPresent(
            defaults,
            key: Keys.musicSpectrumBarWidthScaleLegacy
        )
        let legacySpacingScale = Self.storedSpectrumTuningIfPresent(
            defaults,
            key: Keys.musicSpectrumBarSpacingScaleLegacy
        )
        let styleWidthScale: Double?
        let styleSpacingScale: Double?
        switch storedSpectrumBarStyle {
        case .four:
            styleWidthScale = Self.storedSpectrumTuningIfPresent(defaults, key: Keys.fourBarSpectrumWidthScale)
            styleSpacingScale = Self.storedSpectrumTuningIfPresent(defaults, key: Keys.fourBarSpectrumSpacingScale)
        case .five:
            styleWidthScale = Self.storedSpectrumTuningIfPresent(defaults, key: Keys.fiveBarSpectrumWidthScale)
            styleSpacingScale = Self.storedSpectrumTuningIfPresent(defaults, key: Keys.fiveBarSpectrumSpacingScale)
        case .seven:
            styleWidthScale = Self.storedSpectrumTuningIfPresent(defaults, key: Keys.sevenBarSpectrumWidthScale)
            styleSpacingScale = Self.storedSpectrumTuningIfPresent(defaults, key: Keys.sevenBarSpectrumSpacingScale)
        }
        let storedWidthScale = Self.storedSpectrumValueIfPresent(
            defaults,
            key: Keys.musicSpectrumBarWidthScale
        )
        let storedSpacingScale = Self.storedSpectrumValueIfPresent(
            defaults,
            key: Keys.musicSpectrumBarSpacingScale
        )
        musicSpectrumBarWidthScale = Self.migratedBarWidthValue(
            storedWidthScale ?? styleWidthScale ?? legacyWidthScale
        ) ?? 2.5
        musicSpectrumBarSpacingScale = Self.migratedBarSpacingValue(
            storedSpacingScale ?? styleSpacingScale ?? legacySpacingScale
        ) ?? 1.6
        musicSpectrumCornerRadiusScale = Self.storedSpectrumTuning(
            defaults,
            key: Keys.musicSpectrumCornerRadiusScale,
            defaultValue: 1.0
        )
        spectrumBarColorMode = defaults.string(forKey: Keys.spectrumBarColorMode)
            .flatMap(SpectrumBarColorMode.init(rawValue:))
            ?? .anchor

        if defaults.object(forKey: Keys.lockScreenMusicEnabled) == nil {
            isLockScreenMusicEnabled = true
        } else {
            isLockScreenMusicEnabled = defaults.bool(forKey: Keys.lockScreenMusicEnabled)
        }

        let storedBackdropStyle = defaults.string(forKey: Keys.lockScreenMusicBackdropStyle)
        if storedBackdropStyle == "dark" {
            lockScreenMusicBackdropStyle = .solidColor
        } else {
            lockScreenMusicBackdropStyle = storedBackdropStyle
                .flatMap(LockScreenMusicBackdropStyle.init(rawValue:))
                ?? .clear
        }

        let storedGlassBlur: Double
        if defaults.object(forKey: Keys.lockScreenMusicGlassBlur) != nil {
            storedGlassBlur = defaults.double(forKey: Keys.lockScreenMusicGlassBlur)
        } else if defaults.object(forKey: Keys.lockScreenMusicGlassTransparencyLegacy) != nil {
            // Preserve values written by the earlier transparency setting.
            storedGlassBlur = defaults.double(forKey: Keys.lockScreenMusicGlassTransparencyLegacy)
        } else {
            storedGlassBlur = Self.lockScreenMusicGlassBlurRange.upperBound
        }
        lockScreenMusicGlassBlur = min(
            max(storedGlassBlur, Self.lockScreenMusicGlassBlurRange.lowerBound),
            Self.lockScreenMusicGlassBlurRange.upperBound
        )

        lockScreenMusicGlassMaterial = defaults
            .object(forKey: Keys.lockScreenMusicGlassMaterial)
            .flatMap { $0 as? Int }
            .flatMap(LiquidGlassMaterial.init(rawValue:))
            ?? .bubbles

        let storedSolidColorComponents = defaults
            .array(forKey: Keys.lockScreenMusicSolidColor)?
            .compactMap { ($0 as? NSNumber)?.doubleValue }
        lockScreenMusicSolidColor = storedSolidColorComponents
            .flatMap(LockScreenMusicSolidColor.init(components:))
            ?? .default

        let storedSolidTextColorComponents = defaults
            .array(forKey: Keys.lockScreenMusicSolidTextColor)?
            .compactMap { ($0 as? NSNumber)?.doubleValue }
        lockScreenMusicSolidTextColor = storedSolidTextColorComponents
            .flatMap(LockScreenMusicSolidColor.init(components:))
            ?? .defaultText

        if defaults.object(forKey: Keys.lockScreenArtworkGradientEnabled) == nil {
            isLockScreenArtworkGradientEnabled = false
        } else {
            isLockScreenArtworkGradientEnabled = defaults.bool(
                forKey: Keys.lockScreenArtworkGradientEnabled
            )
        }

        musicControlAuthorizedApps = defaults
            .stringArray(forKey: Keys.musicControlAuthorizedApps) ?? []
        musicControlDeniedApps = defaults
            .stringArray(forKey: Keys.musicControlDeniedApps) ?? []
        isSystemAudioCaptureEnabled = defaults.bool(forKey: Keys.systemAudioCaptureEnabled)
        isBluetoothDeviceMonitoringEnabled = defaults.bool(forKey: Keys.bluetoothDeviceMonitoringEnabled)
    }

    private static func storedSpectrumTuning(
        _ defaults: UserDefaults,
        key: String,
        defaultValue: Double
    ) -> Double {
        storedSpectrumTuningIfPresent(defaults, key: key) ?? defaultValue
    }

    private static func storedSpectrumTuningIfPresent(
        _ defaults: UserDefaults,
        key: String
    ) -> Double? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return min(
            max(defaults.double(forKey: key), musicSpectrumTuningRange.lowerBound),
            musicSpectrumTuningRange.upperBound
        )
    }

    private static func storedSpectrumValueIfPresent(
        _ defaults: UserDefaults,
        key: String
    ) -> Double? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.double(forKey: key)
    }

    /// 将旧版 0...1 比例值迁移为新的实际 pt 值；新值（已在实际范围内）原样保留。
    private static func migratedBarWidthValue(_ value: Double?) -> Double? {
        guard let value else { return nil }
        if value >= spectrumBarWidthRange.lowerBound { return min(value, spectrumBarWidthRange.upperBound) }
        let progress = min(max(value / 0.9, 0), 1)
        return spectrumBarWidthRange.lowerBound
            + (spectrumBarWidthRange.upperBound - spectrumBarWidthRange.lowerBound) * progress
    }

    private static func migratedBarSpacingValue(_ value: Double?) -> Double? {
        guard let value else { return nil }
        if value >= spectrumBarSpacingRange.lowerBound {
            return min(value, spectrumBarSpacingRange.upperBound)
        }
        let progress = min(max((value - 0.1) / 0.9, 0), 1)
        return spectrumBarSpacingRange.lowerBound
            + (spectrumBarSpacingRange.upperBound - spectrumBarSpacingRange.lowerBound) * progress
    }

    /// 当前柱数的频谱律动参数是否为默认值。
    public var usesDefaultSpectrumRhythm: Bool {
        let configuration = musicSpectrumConfiguration
        return configuration.sensitivity == 0.5
            && configuration.attackTime == Self.defaultSpectrumAttackTime
            && configuration.releaseTime == Self.defaultSpectrumReleaseTime
            && musicSpectrumRhythmDetail == Self.defaultSpectrumRhythmDetail
            && musicSpectrumUpdateRate == Self.defaultSpectrumUpdateRate
    }

    public func resetSpectrumRhythmToDefault() {
        switch musicSpectrumBarStyle {
        case .four:
            fourBarSpectrumSensitivity = 0.5
            fourBarSpectrumAttackTime = Self.defaultSpectrumAttackTime
            fourBarSpectrumReleaseTime = Self.defaultSpectrumReleaseTime
        case .five:
            fiveBarSpectrumSensitivity = 0.5
            fiveBarSpectrumAttackTime = Self.defaultSpectrumAttackTime
            fiveBarSpectrumReleaseTime = Self.defaultSpectrumReleaseTime
        case .seven:
            sevenBarSpectrumSensitivity = 0.5
            sevenBarSpectrumAttackTime = Self.defaultSpectrumAttackTime
            sevenBarSpectrumReleaseTime = Self.defaultSpectrumReleaseTime
        }
        musicSpectrumRhythmDetail = Self.defaultSpectrumRhythmDetail
        musicSpectrumUpdateRate = Self.defaultSpectrumUpdateRate
    }

    public func resetToDefault() {
        isRealtimeMusicMonitoringEnabled = false
        isCompactArtworkRotationEnabled = false
        compactRotatingArtworkCornerRadiusPercentage = 100
        compactStaticArtworkCornerRadiusPercentage = 50
        musicSpectrumBarStyle = .five
        musicSpectrumUpdateRate = Self.defaultSpectrumUpdateRate
        fourBarSpectrumSensitivity = 0.5
        fourBarSpectrumAttackTime = Self.defaultSpectrumAttackTime
        fourBarSpectrumReleaseTime = Self.defaultSpectrumReleaseTime
        fiveBarSpectrumSensitivity = 0.5
        fiveBarSpectrumAttackTime = Self.defaultSpectrumAttackTime
        fiveBarSpectrumReleaseTime = Self.defaultSpectrumReleaseTime
        sevenBarSpectrumSensitivity = 0.5
        sevenBarSpectrumAttackTime = Self.defaultSpectrumAttackTime
        sevenBarSpectrumReleaseTime = Self.defaultSpectrumReleaseTime
        musicSpectrumRhythmDetail = Self.defaultSpectrumRhythmDetail
        musicSpectrumBarWidthScale = 2.5
        musicSpectrumBarSpacingScale = 1.6
        musicSpectrumCornerRadiusScale = 1.0
        spectrumBarColorMode = .anchor
        isLockScreenMusicEnabled = true
        lockScreenMusicBackdropStyle = .clear
        lockScreenMusicGlassBlur = Self.lockScreenMusicGlassBlurRange.upperBound
        lockScreenMusicGlassMaterial = .bubbles
        lockScreenMusicSolidColor = .default
        lockScreenMusicSolidTextColor = .defaultText
        isLockScreenArtworkGradientEnabled = false
    }

    /// 仅恢复锁屏音乐相关偏好到默认值。
    public func resetLockScreenToDefault() {
        isLockScreenMusicEnabled = true
        lockScreenMusicBackdropStyle = .clear
        lockScreenMusicGlassBlur = Self.lockScreenMusicGlassBlurRange.upperBound
        lockScreenMusicGlassMaterial = .bubbles
        lockScreenMusicSolidColor = .default
        lockScreenMusicSolidTextColor = .defaultText
        isLockScreenArtworkGradientEnabled = false
    }

    public var usesDefaultLockScreenValues: Bool {
        isLockScreenMusicEnabled
            && lockScreenMusicBackdropStyle == .clear
            && lockScreenMusicGlassBlur == Self.lockScreenMusicGlassBlurRange.upperBound
            && lockScreenMusicGlassMaterial == .bubbles
            && lockScreenMusicSolidColor == .default
            && lockScreenMusicSolidTextColor == .defaultText
            && !isLockScreenArtworkGradientEnabled
    }

    /// 视觉与行为偏好是否全部等于默认值（用于禁用“恢复默认”按钮）。
    public var usesDefaultVisualPreferences: Bool {
        isRealtimeMusicMonitoringEnabled == false
            && !isCompactArtworkRotationEnabled
            && compactRotatingArtworkCornerRadiusPercentage == 100
            && compactStaticArtworkCornerRadiusPercentage == 50
            && musicSpectrumBarStyle == .five
            && musicSpectrumUpdateRate == Self.defaultSpectrumUpdateRate
            && fourBarSpectrumSensitivity == 0.5
            && fourBarSpectrumAttackTime == 0.5
            && fourBarSpectrumReleaseTime == 0.5
            && fiveBarSpectrumSensitivity == 0.5
            && fiveBarSpectrumAttackTime == 0.5
            && fiveBarSpectrumReleaseTime == 0.5
            && sevenBarSpectrumSensitivity == 0.5
            && sevenBarSpectrumAttackTime == 0.5
            && sevenBarSpectrumReleaseTime == 0.5
            && musicSpectrumRhythmDetail == Self.defaultSpectrumRhythmDetail
            && musicSpectrumBarWidthScale == 2.5
            && musicSpectrumBarSpacingScale == 1.6
            && musicSpectrumCornerRadiusScale == 1.0
            && spectrumBarColorMode == .anchor
            && isLockScreenMusicEnabled
            && lockScreenMusicBackdropStyle == .clear
            && lockScreenMusicGlassBlur == Self.lockScreenMusicGlassBlurRange.upperBound
            && lockScreenMusicGlassMaterial == .bubbles
            && lockScreenMusicSolidColor == .default
            && lockScreenMusicSolidTextColor == .defaultText
            && !isLockScreenArtworkGradientEnabled
    }
}
