import Combine
import Foundation

public enum HoverHapticIntensity: String, CaseIterable, Identifiable, Sendable {
    case none
    case light
    case medium
    case strong

    public var id: Self { self }
}

/// Island 展开交互的统一用户偏好，并即时持久化到 UserDefaults。
@MainActor
public final class NotchInteractionSettings: ObservableObject {
    public static let defaultHoverRevealDelay: TimeInterval = 0.3
    public static let hoverRevealDelayRange: ClosedRange<TimeInterval> = 0.1...1

    private enum Keys {
        static let hoverRevealDelay = "interaction.island.hoverRevealDelay"
        static let hoverHapticIntensity = "interaction.island.hoverHapticIntensity"
        static let clickEnabled = "interaction.island.clickEnabled"
        static let hiddenInScreenCapture = "interaction.island.hiddenInScreenCapture"
        static let minimalMode = "interaction.island.minimalMode"
        static let hoverTriggerEnabled = "interaction.island.hoverTriggerEnabled"
    }

    public var hideDelay: TimeInterval
    public var startsHidden: Bool

    public var hoverRevealDelay: TimeInterval {
        get { storedHoverRevealDelay }
        set { setHoverRevealDelay(newValue) }
    }

    @Published public var isClickEnabled: Bool {
        didSet { defaults?.set(isClickEnabled, forKey: Keys.clickEnabled) }
    }

    @Published public var hoverHapticIntensity: HoverHapticIntensity {
        didSet { defaults?.set(hoverHapticIntensity.rawValue, forKey: Keys.hoverHapticIntensity) }
    }

    @Published public var isHiddenInScreenCapture: Bool {
        didSet { defaults?.set(isHiddenInScreenCapture, forKey: Keys.hiddenInScreenCapture) }
    }

    @Published public var isMinimalModeEnabled: Bool {
        didSet { defaults?.set(isMinimalModeEnabled, forKey: Keys.minimalMode) }
    }

    /// 是否启用悬停触发展开。
    @Published public var isHoverTriggerEnabled: Bool {
        didSet { defaults?.set(isHoverTriggerEnabled, forKey: Keys.hoverTriggerEnabled) }
    }

    private let defaults: UserDefaults?
    private var storedHoverRevealDelay: TimeInterval

    /// 传入 `nil` 可创建不持久化的实例，便于状态机测试与预览。
    public init(
        defaults: UserDefaults? = .standard,
        hideDelay: TimeInterval = 0,
        startsHidden: Bool = true,
        hoverRevealDelay: TimeInterval = 0.3,
        isClickEnabled: Bool = true,
        hoverHapticIntensity: HoverHapticIntensity = .light,
        isHiddenInScreenCapture: Bool = true,
        isMinimalModeEnabled: Bool = false,
        isHoverTriggerEnabled: Bool = true
    ) {
        self.defaults = defaults
        self.hideDelay = hideDelay
        self.startsHidden = startsHidden
        self.storedHoverRevealDelay = Self.storedHoverRevealDelay(
            defaults: defaults,
            fallback: hoverRevealDelay
        )
        self.isClickEnabled = Self.storedClickEnabled(
            defaults: defaults,
            fallback: isClickEnabled
        )
        self.hoverHapticIntensity = Self.storedHoverHapticIntensity(
            defaults: defaults,
            fallback: hoverHapticIntensity
        )
        self.isHiddenInScreenCapture = Self.storedHiddenInScreenCapture(
            defaults: defaults,
            fallback: isHiddenInScreenCapture
        )
        self.isMinimalModeEnabled = Self.storedMinimalModeEnabled(
            defaults: defaults,
            fallback: isMinimalModeEnabled
        )
        self.isHoverTriggerEnabled = Self.storedHoverTriggerEnabled(
            defaults: defaults,
            fallback: isHoverTriggerEnabled
        )

        if let defaults,
           defaults.object(forKey: Keys.hoverRevealDelay) != nil,
           defaults.double(forKey: Keys.hoverRevealDelay) != self.hoverRevealDelay {
            defaults.set(self.hoverRevealDelay, forKey: Keys.hoverRevealDelay)
        }
    }

    public func resetToDefaults() {
        setHoverRevealDelay(Self.defaultHoverRevealDelay)
        isClickEnabled = true
        hoverHapticIntensity = .light
        isHiddenInScreenCapture = true
        isMinimalModeEnabled = false
        isHoverTriggerEnabled = true
    }

    public func setHoverRevealDelay(_ delay: TimeInterval) {
        let normalizedDelay = Self.normalizedHoverRevealDelay(delay)
        guard storedHoverRevealDelay != normalizedDelay else {
            defaults?.set(normalizedDelay, forKey: Keys.hoverRevealDelay)
            return
        }

        objectWillChange.send()
        storedHoverRevealDelay = normalizedDelay
        defaults?.set(normalizedDelay, forKey: Keys.hoverRevealDelay)
    }

    private static func storedHoverRevealDelay(
        defaults: UserDefaults?,
        fallback: TimeInterval
    ) -> TimeInterval {
        guard let defaults,
              defaults.object(forKey: Keys.hoverRevealDelay) != nil
        else {
            return normalizedHoverRevealDelay(fallback)
        }

        return normalizedHoverRevealDelay(defaults.double(forKey: Keys.hoverRevealDelay))
    }

    private static func storedClickEnabled(
        defaults: UserDefaults?,
        fallback: Bool
    ) -> Bool {
        guard let defaults,
              defaults.object(forKey: Keys.clickEnabled) != nil
        else { return fallback }
        return defaults.bool(forKey: Keys.clickEnabled)
    }

    private static func storedHoverHapticIntensity(
        defaults: UserDefaults?,
        fallback: HoverHapticIntensity
    ) -> HoverHapticIntensity {
        guard let rawValue = defaults?.string(forKey: Keys.hoverHapticIntensity) else {
            return fallback
        }
        return HoverHapticIntensity(rawValue: rawValue) ?? fallback
    }

    private static func storedHiddenInScreenCapture(
        defaults: UserDefaults?,
        fallback: Bool
    ) -> Bool {
        guard let defaults,
              defaults.object(forKey: Keys.hiddenInScreenCapture) != nil
        else { return fallback }
        return defaults.bool(forKey: Keys.hiddenInScreenCapture)
    }

    private static func storedMinimalModeEnabled(
        defaults: UserDefaults?,
        fallback: Bool
    ) -> Bool {
        guard let defaults,
              defaults.object(forKey: Keys.minimalMode) != nil
        else { return fallback }
        return defaults.bool(forKey: Keys.minimalMode)
    }

    private static func storedHoverTriggerEnabled(
        defaults: UserDefaults?,
        fallback: Bool
    ) -> Bool {
        guard let defaults,
              defaults.object(forKey: Keys.hoverTriggerEnabled) != nil
        else { return fallback }
        return defaults.bool(forKey: Keys.hoverTriggerEnabled)
    }

    private static func normalizedHoverRevealDelay(_ delay: TimeInterval) -> TimeInterval {
        guard delay.isFinite else { return defaultHoverRevealDelay }
        return min(max(delay, hoverRevealDelayRange.lowerBound), hoverRevealDelayRange.upperBound)
    }
}
