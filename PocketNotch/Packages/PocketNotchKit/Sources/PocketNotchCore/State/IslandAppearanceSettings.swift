import Combine
import Foundation

/// 交互模式（展开态）的背板背景风格。
/// 新增背景样式时在此扩展 case，运行时与设置预览分别按 case 接入渲染。
public enum ExpandedBackgroundStyle: String, CaseIterable, Identifiable, Sendable {
    /// 纯黑色背板，与紧凑态同源，全系统可用。
    case standard
    /// 毛玻璃：黑色实体区与毛玻璃区两块材质分区相接，毛玻璃区透出背后
    /// 窗口的墙纸模糊；顶部黑色区域占比由「毛玻璃区域」控制。
    case frosted
    /// 液态玻璃：整块底板替换为真正的 Liquid Glass（macOS 26+ 私有
    /// `NSGlassEffectView` 实时折射身后内容；低版本回退到仿液态）。
    /// 顶部黑色区域占比与毛玻璃共用「毛玻璃区域」调节。
    case liquidGlass
    /// 仿液态：整块底板替换为纯 SwiftUI 模拟的液态玻璃观感，全系统可用，
    /// 与 `liquidGlass` 共享可读性深洗、rim 与黑色区域调节。
    case simulatedLiquid

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .standard: "默认"
        case .frosted: "毛玻璃"
        case .liquidGlass: "液态玻璃"
        case .simulatedLiquid: "仿液态"
        }
    }

    /// 是否支持「毛玻璃区域」调节（顶部保留黑色盖板的比例）。
    /// 纯黑标准样式无分区，其余材质样式均支持。
    public var supportsFrostedRegion: Bool {
        self != .standard
    }
}

/// Island 的 resting（默认）、compact（灵动）与 expanded（展开）外观偏好。
///
/// `nil` 表示自动模式：高度跟随物理刘海，其余尺寸由当前高度和形状自动推导。
/// 用户拖动任一滑块后保存对应覆盖值；最终值仍由统一约束和布局解析器校正，
/// 避免内容进入圆角、覆盖物理刘海或压缩两侧内容区域。
@MainActor
public final class IslandAppearanceSettings: ObservableObject {
    private enum Keys {
        static let customRestingHeight = "appearance.island.compact.customHeight"
        static let customRestingWidth = "appearance.island.compact.customWidth"
        static let customCompactWidth = "appearance.island.customIslandWidth"
        static let customEarHeight = "appearance.island.compact.customEarHeight"
        static let customCompactVerticalInset = "appearance.island.compact.customVerticalInset"
        static let customCompactOuterInset = "appearance.island.compact.customOuterInset"
        static let expandedBackgroundStyle = "appearance.island.expandedBackgroundStyle"
        static let expandedBackgroundFrostedRegion = "appearance.island.expandedFrostedRegion"
        static let expandedLiquidGlassMaterial = "appearance.island.expandedLiquidGlassMaterial"
        static let didMigrateLegacyCompactWidth = "appearance.island.didMigrateLegacyCompactWidth"
    }

    /// 岛体总高度（隐藏态与灵动态共用，也由「耳朵大小」滑块驱动）。
    /// `nil` 表示自动（跟随物理刘海/菜单栏）。
    @Published public var customRestingHeight: CGFloat? {
        didSet { persist(customRestingHeight, forKey: Keys.customRestingHeight) }
    }

    @Published public var customRestingWidth: CGFloat? {
        didSet { persist(customRestingWidth, forKey: Keys.customRestingWidth) }
    }

    @Published public var customCompactWidth: CGFloat? {
        didSet { persist(customCompactWidth, forKey: Keys.customCompactWidth) }
    }

    /// 灵动模式左右耳内容槽高度（12–36）。与岛高解耦：调高岛高不会撑大耳朵。
    /// `nil` 表示自动（默认 24）。
    @Published public var customEarHeight: CGFloat? {
        didSet { persist(customEarHeight, forKey: Keys.customEarHeight) }
    }

    @Published public var customCompactVerticalInset: CGFloat? {
        didSet { persist(customCompactVerticalInset, forKey: Keys.customCompactVerticalInset) }
    }

    /// 灵动模式耳朵内容槽与岛外侧边缘的间距（1–10）。计入宽度预算：
    /// 间距变大时岛宽随之变宽，耳朵保持方形不被压窄。`nil` 表示自动（默认 4）。
    @Published public var customCompactOuterInset: CGFloat? {
        didSet { persist(customCompactOuterInset, forKey: Keys.customCompactOuterInset) }
    }

    /// 交互模式（展开态）背景风格。
    @Published public var expandedBackgroundStyle: ExpandedBackgroundStyle {
        didSet { defaults.set(expandedBackgroundStyle.rawValue, forKey: Keys.expandedBackgroundStyle) }
    }

    /// 毛玻璃区域占岛面的比例（0 = 整岛纯黑，1 = 整个岛都是毛玻璃）。
    @Published public var expandedBackgroundFrostedRegion: CGFloat {
        didSet {
            let clamped = min(
                max(expandedBackgroundFrostedRegion, Self.frostedRegionBounds.lowerBound),
                Self.frostedRegionBounds.upperBound
            )
            if clamped != expandedBackgroundFrostedRegion {
                expandedBackgroundFrostedRegion = clamped
                return
            }
            defaults.set(Double(clamped), forKey: Keys.expandedBackgroundFrostedRegion)
        }
    }

    /// 毛玻璃区域的可调范围与默认值。下限 1%——材质永远留一线，不允许整岛
    /// 调到纯黑（纯黑是 `standard` 样式的事）。
    public static let frostedRegionBounds: ClosedRange<CGFloat> = 0.01...1
    public static let defaultFrostedRegion: CGFloat = 0.01

    /// 液态玻璃的材质变体（常规 / 清澈 / Dock / 气泡）。只对 `liquidGlass`
    /// 样式生效；`simulatedLiquid` 是纯 SwiftUI 仿制，不经过系统玻璃。
    @Published public var expandedLiquidGlassMaterial: LiquidGlassMaterial {
        didSet { defaults.set(expandedLiquidGlassMaterial.rawValue, forKey: Keys.expandedLiquidGlassMaterial) }
    }

    public static let defaultLiquidGlassMaterial: LiquidGlassMaterial = .regular

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        expandedBackgroundStyle = Self.storedExpandedBackgroundStyle(defaults: defaults)
        expandedBackgroundFrostedRegion = Self.storedFrostedRegion(defaults: defaults)
        expandedLiquidGlassMaterial = Self.storedLiquidGlassMaterial(defaults: defaults)
        customRestingHeight = Self.storedValue(forKey: Keys.customRestingHeight, defaults: defaults)
        // 隐藏态宽度上限依赖当前屏幕的物理刘海宽度，解析时按刘海钳制；
        // 初始化阶段保留原始值，避免用兜底刘海宽把用户设置意外改小。
        customRestingWidth = Self.storedValue(forKey: Keys.customRestingWidth, defaults: defaults)
        let rawCompactWidth = Self.storedValue(forKey: Keys.customCompactWidth, defaults: defaults)
        let storedCompactWidth = Self.migratedCompactWidth(rawCompactWidth, defaults: defaults)
        // 与隐藏态宽度一致：灵动态宽度下限依赖当前屏幕实测刘海（如 185+64=249），
        // 由布局解析器按刘海钳制；初始化阶段只夹上界，避免再用「无刘海兜底」的 264
        // 把带刘海机器的存值意外顶大。
        customCompactWidth = storedCompactWidth.map {
            min($0, IslandAppearanceConstraints.maximumCompactWidth)
        }
        customEarHeight = Self.storedValue(forKey: Keys.customEarHeight, defaults: defaults).map {
            clamp(
                $0,
                IslandAppearanceConstraints.minimumCompactHeight,
                IslandAppearanceConstraints.maximumEarHeight
            )
        }
        customCompactVerticalInset = nil
        customCompactOuterInset = Self.storedValue(forKey: Keys.customCompactOuterInset, defaults: defaults).map {
            clamp(
                $0,
                IslandAppearanceConstraints.minimumCompactOuterInset,
                IslandAppearanceConstraints.maximumCompactOuterInset
            )
        }

        if customCompactWidth != rawCompactWidth {
            persist(customCompactWidth, forKey: Keys.customCompactWidth)
        }
    }

    public var usesAutomaticRestingHeight: Bool { customRestingHeight == nil }
    public var usesAutomaticRestingWidth: Bool { customRestingWidth == nil }
    public var usesAutomaticCompactWidth: Bool { customCompactWidth == nil }
    public var usesAutomaticCompactVerticalInset: Bool { customCompactVerticalInset == nil }
    public var usesAutomaticCompactOuterInset: Bool { customCompactOuterInset == nil }
    public var usesAutomaticEarHeight: Bool { customEarHeight == nil }

    public var usesAutomaticRestingLayout: Bool {
        usesAutomaticRestingHeight && usesAutomaticRestingWidth
    }

    /// 灵动态宽度/间距/耳朵可独立，恢复默认需一并清掉。
    public var usesAutomaticCompactLayout: Bool {
        usesAutomaticCompactWidth
            && usesAutomaticCompactVerticalInset
            && usesAutomaticCompactOuterInset
            && usesAutomaticEarHeight
    }

    public var usesAutomaticLayout: Bool {
        usesAutomaticRestingLayout && usesAutomaticCompactLayout
    }

    public func resolvedRestingHeight(
        physicalNotchHeight: CGFloat,
        defaultIslandHeight: CGFloat = IslandAppearanceConstraints.defaultFloatingRestingHeight
    ) -> CGFloat {
        IslandAppearanceConstraints.resolvedRestingHeight(
            preferredHeight: customRestingHeight,
            physicalNotchHeight: physicalNotchHeight,
            defaultIslandHeight: defaultIslandHeight
        )
    }

    public func resolvedRestingWidth(
        physicalNotchWidth: CGFloat,
        restingHeight: CGFloat
    ) -> CGFloat {
        IslandAppearanceConstraints.resolvedRestingWidth(
            preferredWidth: customRestingWidth,
            physicalNotchWidth: physicalNotchWidth,
            restingHeight: restingHeight
        )
    }

    public func setCustomRestingHeight(_ height: CGFloat, physicalNotchHeight: CGFloat) {
        customRestingHeight = IslandAppearanceConstraints.resolvedRestingHeight(
            preferredHeight: height,
            physicalNotchHeight: physicalNotchHeight
        )
    }

    public func setCustomRestingWidth(
        _ width: CGFloat,
        physicalNotchWidth: CGFloat,
        restingHeight: CGFloat
    ) {
        customRestingWidth = IslandAppearanceConstraints.resolvedRestingWidth(
            preferredWidth: width,
            physicalNotchWidth: physicalNotchWidth,
            restingHeight: restingHeight
        )
    }

    /// 灵动模式耳朵（内容槽）高度，独立于岛高：`customEarHeight` 未设置时默认 24。
    public func resolvedEarHeight() -> CGFloat {
        clamp(
            customEarHeight ?? IslandAppearanceConstraints.defaultCompactHeight,
            IslandAppearanceConstraints.minimumCompactHeight,
            IslandAppearanceConstraints.maximumEarHeight
        )
    }

    /// 隐藏态与灵动态共用的岛体高度：不小于用户设定高度，且必须装得下耳朵
    /// （耳朵 + 2×最小上下间距）。调高岛高时耳朵不变，多出的空间全部变成上下间距。
    public func resolvedIslandHeight(
        physicalNotchHeight: CGFloat,
        defaultIslandHeight: CGFloat = IslandAppearanceConstraints.defaultFloatingRestingHeight
    ) -> CGFloat {
        max(
            resolvedRestingHeight(
                physicalNotchHeight: physicalNotchHeight,
                defaultIslandHeight: defaultIslandHeight
            ),
            resolvedEarHeight() + IslandAppearanceConstraints.minimumCompactVerticalInset * 2
        )
    }

    /// 耳朵落在当前岛高里的实际上下间距（耳朵垂直居中）。
    public func resolvedCompactVerticalInset(islandHeight: CGFloat) -> CGFloat {
        clamp(
            (islandHeight - resolvedEarHeight()) / 2,
            IslandAppearanceConstraints.minimumCompactVerticalInset,
            IslandAppearanceConstraints.maximumCompactVerticalInset
        )
    }

    public func resolvedCompactVerticalInset() -> CGFloat {
        IslandAppearanceConstraints.resolvedCompactVerticalInset(
            preferred: customCompactVerticalInset,
            islandHeight: 0
        )
    }

    /// 灵动模式耳朵内容槽到岛外侧边缘的间距（独立几何预算，默认 4，范围 1–10）。
    public func resolvedCompactOuterInset() -> CGFloat {
        IslandAppearanceConstraints.resolvedCompactOuterInset(
            preferredInset: customCompactOuterInset,
            compactHeight: 0,
            wallInset: 0
        )
    }

    /// 设置「耳朵高度」：只改耳朵，岛高保持不变（若岛高装不下耳朵则解析时抬到耳朵 + 2×间距）。
    public func setCustomEarHeight(_ earHeight: CGFloat) {
        customEarHeight = clamp(
            earHeight,
            IslandAppearanceConstraints.minimumCompactHeight,
            IslandAppearanceConstraints.maximumEarHeight
        )
    }

    /// 灵动态「耳朵上下间距」：岛高 = 耳朵高度 + 2×间距，并写回隐藏态共用高度。
    /// 高度受物理刘海/浮动下限与 48 上限约束，因此间距的有效范围随耳朵高度收窄。
    public func setCompactVerticalInset(
        _ inset: CGFloat,
        physicalNotchHeight: CGFloat
    ) {
        let clampedInset = clamp(
            inset,
            IslandAppearanceConstraints.minimumCompactVerticalInset,
            IslandAppearanceConstraints.maximumCompactVerticalInset
        )
        customCompactVerticalInset = clampedInset
        setCustomRestingHeight(
            resolvedEarHeight() + clampedInset * 2,
            physicalNotchHeight: physicalNotchHeight
        )
    }

    /// 灵动态「耳朵上下间距」可调范围：由隐藏态高度范围与当前耳朵高度共同决定。
    public func compactVerticalInsetRange(
        physicalNotchHeight: CGFloat
    ) -> ClosedRange<CGFloat> {
        let ear = resolvedEarHeight()
        let lower = max(
            IslandAppearanceConstraints.minimumCompactVerticalInset,
            (IslandAppearanceConstraints.minimumRestingHeight(
                physicalNotchHeight: physicalNotchHeight
            ) - ear) / 2
        )
        let upper = min(
            IslandAppearanceConstraints.maximumCompactVerticalInset,
            (IslandAppearanceConstraints.maximumRestingHeight(
                physicalNotchHeight: physicalNotchHeight
            ) - ear) / 2
        )
        return lower...max(lower, upper)
    }

    public func setCustomCompactVerticalInset(_ inset: CGFloat) {
        customCompactVerticalInset = clamp(
            inset,
            IslandAppearanceConstraints.minimumCompactVerticalInset,
            IslandAppearanceConstraints.maximumCompactVerticalInset
        )
    }

    public func resetRestingHeightToAutomatic() { customRestingHeight = nil }
    public func resetRestingWidthToAutomatic() { customRestingWidth = nil }
    public func resetCompactWidthToAutomatic() { customCompactWidth = nil }
    public func resetCompactVerticalInsetToAutomatic() { customCompactVerticalInset = nil }
    public func resetCompactOuterInsetToAutomatic() { customCompactOuterInset = nil }

    public func resetRestingToAutomatic() {
        customRestingHeight = nil
        customRestingWidth = nil
    }

    /// 灵动态页：耳朵高度、宽度、上下间距与外侧间距一起恢复默认。
    public func resetCompactToAutomatic() {
        customRestingHeight = nil
        customCompactWidth = nil
        customCompactVerticalInset = nil
        customCompactOuterInset = nil
        customEarHeight = nil
    }

    public func resetAllToAutomatic() {
        customRestingHeight = nil
        customRestingWidth = nil
        customCompactWidth = nil
        customCompactVerticalInset = nil
        customCompactOuterInset = nil
        customEarHeight = nil
    }

    private func persist(_ value: CGFloat?, forKey key: String) {
        guard let value, value.isFinite else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(Double(value), forKey: key)
    }

    private static func storedValue(forKey key: String, defaults: UserDefaults) -> CGFloat? {
        guard let stored = defaults.object(forKey: key) as? NSNumber,
              stored.doubleValue.isFinite else {
            return nil
        }
        return CGFloat(stored.doubleValue)
    }

    /// 一次性迁移：旧版本把「无实测刘海」兜底宽度（264）写成用户设置，带刘海机器会被顶到
    /// 264、掩盖按实测刘海推导的默认值（如 249）。仅迁移等于该兜底值的存值回自动模式，
    /// 之后按真实刘海重新解析；用标记保证只跑一次，避免用户主动选回 264 时被反复清掉。
    private static func migratedCompactWidth(
        _ storedCompactWidth: CGFloat?,
        defaults: UserDefaults
    ) -> CGFloat? {
        guard !defaults.bool(forKey: Keys.didMigrateLegacyCompactWidth) else {
            return storedCompactWidth
        }
        defaults.set(true, forKey: Keys.didMigrateLegacyCompactWidth)
        guard storedCompactWidth == IslandAppearanceConstraints.legacyFallbackCompactWidth else {
            return storedCompactWidth
        }
        return nil
    }

    private static func storedExpandedBackgroundStyle(defaults: UserDefaults) -> ExpandedBackgroundStyle {
        guard let rawValue = defaults.string(forKey: Keys.expandedBackgroundStyle) else {
            return .standard
        }
        return ExpandedBackgroundStyle(rawValue: rawValue) ?? .standard
    }

    private static func storedLiquidGlassMaterial(defaults: UserDefaults) -> LiquidGlassMaterial {
        guard defaults.object(forKey: Keys.expandedLiquidGlassMaterial) != nil else {
            return defaultLiquidGlassMaterial
        }
        let stored = defaults.integer(forKey: Keys.expandedLiquidGlassMaterial)
        return LiquidGlassMaterial(rawValue: stored) ?? defaultLiquidGlassMaterial
    }

    private static func storedFrostedRegion(defaults: UserDefaults) -> CGFloat {
        if defaults.object(forKey: Keys.expandedBackgroundFrostedRegion) == nil,
           let legacy = defaults.object(forKey: "appearance.island.expandedBackgroundGaussianRange") {
            // 旧「高斯范围」与新「毛玻璃区域」比例同向，平移即可。
            let value = (legacy as? Double).map { CGFloat($0) } ?? defaultFrostedRegion
            let clamped = min(max(value, frostedRegionBounds.lowerBound), frostedRegionBounds.upperBound)
            defaults.set(Double(clamped), forKey: Keys.expandedBackgroundFrostedRegion)
            return clamped
        }
        // 0 是合法值（纯黑），必须用是否存在过存储来判断默认值。
        guard defaults.object(forKey: Keys.expandedBackgroundFrostedRegion) != nil else {
            return defaultFrostedRegion
        }
        let stored = defaults.double(forKey: Keys.expandedBackgroundFrostedRegion)
        return min(max(CGFloat(stored), frostedRegionBounds.lowerBound), frostedRegionBounds.upperBound)
    }
}

/// 与设置 UI、背景和内容布局共用的安全范围。
public enum IslandAppearanceConstraints {
    /// 岛体总高度（隐藏态与灵动态共用）：继续完整覆盖物理刘海；
    /// 无刘海屏自动跟随系统，手动值限制为 32–48 pt。
    public static let floatingMinimumRestingHeight: CGFloat = 32
    public static let defaultFloatingRestingHeight: CGFloat = 32
    public static let maximumRestingHeight: CGFloat = 48

    /// 灵动态左右耳内容槽高度由统一岛高扣掉上下间距得到，不再单独存储。
    /// 「耳朵高度」滑块可调 12–36 pt；下限即内容槽兜底高度 `minimumCompactHeight`。
    public static let minimumCompactHeight: CGFloat = 12
    public static let defaultCompactHeight: CGFloat = 24
    /// 「耳朵高度」滑块上限（内容槽高度，岛高 = 耳朵 + 2×上下间距）。
    public static let maximumEarHeight: CGFloat = 36

    /// 内容槽高度（「耳朵大小」）= 岛高 − 上下间距×2。
    public static func compactContentHeight(islandHeight: CGFloat, verticalInset: CGFloat) -> CGFloat {
        let inset = resolvedCompactVerticalInset(
            preferred: verticalInset,
            islandHeight: islandHeight
        )
        return max(islandHeight - inset * 2, minimumCompactHeight)
    }

    public static func compactContentHeight(islandHeight: CGFloat) -> CGFloat {
        compactContentHeight(islandHeight: islandHeight, verticalInset: defaultCompactVerticalInset)
    }

    /// 所有可配置宽度均表示两条可见侧壁之间的主体宽度，不包含左右肩部。
    /// 隐藏态以系统刘海宽度为基准；无法取得刘海时默认 200 pt。
    public static let fallbackNotchWidth: CGFloat = 200
    public static let defaultRestingHorizontalInset: CGFloat = 0
    public static let defaultRestingHorizontalInsets: CGFloat = defaultRestingHorizontalInset * 2
    public static let defaultRestingWidth: CGFloat = 200
    public static let defaultFloatingRestingBodyWidth = defaultRestingWidth
    /// 隐藏态可调最大主体宽度 = 灵动态默认宽度（无刘海时用兜底刘海宽）。
    public static let maximumRestingWidth: CGFloat = fallbackNotchWidth + defaultCompactSideWidthBudget * 2

    /// 外侧边距不对外开放调节，固定为默认值；左右内容与 Island 外边缘之间的
    /// 间距始终计入容器内部。
    public static let minimumCompactOuterInset: CGFloat = 1
    public static let defaultCompactOuterInset: CGFloat = 4
    public static let maximumCompactOuterInset: CGFloat = 10

    /// 灵动态「耳朵上下间距」可调范围 1–18：拖间距即改岛高（岛高 = 耳朵 + 2×间距），
    /// 有效范围会随耳朵高度收窄，保证调高岛高时耳朵不被撑大。
    public static let minimumCompactVerticalInset: CGFloat = 1
    public static let defaultCompactVerticalInset: CGFloat = 4
    /// 上下间距上限：需覆盖（岛高上限 48 − 耳朵下限 12）的一半。
    public static let maximumCompactVerticalInset: CGFloat = 18
    public static let defaultCompactVerticalInsets: CGFloat = defaultCompactVerticalInset * 2

    /// 灵动态宽度同样表示主体宽度，不包含左右肩部。
    /// 默认/最小可调宽度 = 物理刘海宽 + 两侧「耳朵 + 间距」预算（无刘海时用兜底刘海宽）。
    public static let minimumCompactWidth: CGFloat = fallbackNotchWidth + defaultCompactSideWidthBudget * 2
    public static let defaultCompactWidth: CGFloat = fallbackNotchWidth + defaultCompactSideWidthBudget * 2
    /// 历史版本把「无实测刘海」的兜底宽度（200+64=264）当作灵动态宽度下限并写入用户设置，
    /// 带刘海机器因此被顶到 264、掩盖按实测刘海推导的默认值（如 185+64=249）。
    /// 该值仅用于把旧存值一次性迁回自动模式，不再作为运行时下限。
    public static let legacyFallbackCompactWidth: CGFloat =
        fallbackNotchWidth + defaultCompactSideWidthBudget * 2
    /// 灵动态宽度上限对齐二档长度（股票/媒体等二档内容所需的最小宽度）。
    public static let maximumCompactWidth: CGFloat = CompactIslandTier.secondTierMinimumWidth
    public static let minimumCompactInnerGap: CGFloat = 4

    public static func minimumRestingHeight(physicalNotchHeight: CGFloat) -> CGFloat {
        physicalNotchHeight > 0 ? physicalNotchHeight : floatingMinimumRestingHeight
    }

    public static func maximumRestingHeight(physicalNotchHeight: CGFloat) -> CGFloat {
        max(maximumRestingHeight, minimumRestingHeight(physicalNotchHeight: physicalNotchHeight))
    }

    public static func resolvedRestingHeight(
        preferredHeight: CGFloat?,
        physicalNotchHeight: CGFloat,
        defaultIslandHeight: CGFloat = defaultFloatingRestingHeight
    ) -> CGFloat {
        let automaticHeight: CGFloat
        if physicalNotchHeight.isFinite, physicalNotchHeight > 0 {
            automaticHeight = physicalNotchHeight
        } else if defaultIslandHeight.isFinite, defaultIslandHeight > 0 {
            automaticHeight = defaultIslandHeight
        } else {
            automaticHeight = defaultFloatingRestingHeight
        }
        guard let preferredHeight = preferredHeight.flatMap(\.finiteValue) else {
            return automaticHeight
        }

        let minimum = minimumRestingHeight(physicalNotchHeight: physicalNotchHeight)
        let maximum = maximumRestingHeight(physicalNotchHeight: physicalNotchHeight)
        return clamp(preferredHeight, minimum, maximum)
    }

    public static func resolvedNotchWidth(physicalNotchWidth: CGFloat) -> CGFloat {
        physicalNotchWidth > 0 ? physicalNotchWidth : fallbackNotchWidth
    }

    /// 隐藏态可见主体（两条竖直侧壁之间）的宽度，不包含肩部。
    public static func automaticRestingBodyWidth(physicalNotchWidth: CGFloat) -> CGFloat {
        guard physicalNotchWidth > 0 else { return defaultRestingWidth }
        return physicalNotchWidth + defaultRestingHorizontalInsets
    }

    /// 单侧「耳朵 + 两侧间距」预算：耳朵默认高 + 默认外间距 + 最小内间距。
    public static let defaultCompactSideWidthBudget: CGFloat =
        defaultCompactHeight + defaultCompactOuterInset + minimumCompactInnerGap

    /// 灵动态默认主体宽度，同时作为隐藏态最大可调宽度与灵动态最小可调宽度：
    /// = 物理刘海宽 + 2×(耳朵默认高 + 默认外间距 + 最小内间距)。
    public static func defaultCompactBodyWidth(physicalNotchWidth: CGFloat) -> CGFloat {
        resolvedNotchWidth(physicalNotchWidth: physicalNotchWidth)
            + defaultCompactSideWidthBudget * 2
    }

    public static func minimumRestingWidth(
        physicalNotchWidth: CGFloat,
        restingHeight: CGFloat
    ) -> CGFloat {
        _ = restingHeight
        return automaticRestingBodyWidth(physicalNotchWidth: physicalNotchWidth)
    }

    /// 返回隐藏态主体宽度；肩部只在最终渲染尺寸中追加。
    public static func automaticRestingWidth(
        physicalNotchWidth: CGFloat,
        restingHeight: CGFloat
    ) -> CGFloat {
        minimumRestingWidth(
            physicalNotchWidth: physicalNotchWidth,
            restingHeight: restingHeight
        )
    }

    public static func resolvedRestingWidth(
        preferredWidth: CGFloat?,
        physicalNotchWidth: CGFloat,
        restingHeight: CGFloat
    ) -> CGFloat {
        let minimum = minimumRestingWidth(
            physicalNotchWidth: physicalNotchWidth,
            restingHeight: restingHeight
        )
        let automatic = automaticRestingWidth(
            physicalNotchWidth: physicalNotchWidth,
            restingHeight: restingHeight
        )
        let requested = preferredWidth.flatMap(\.finiteValue) ?? automatic
        return clamp(
            requested,
            minimum,
            defaultCompactBodyWidth(physicalNotchWidth: physicalNotchWidth)
        )
    }

    public static func maximumCompactVerticalInset(compactHeight: CGFloat) -> CGFloat {
        _ = compactHeight
        return maximumCompactVerticalInset
    }

    public static func resolvedCompactVerticalInset(
        preferred: CGFloat?,
        islandHeight: CGFloat
    ) -> CGFloat {
        let requested = preferred ?? defaultCompactVerticalInset
        let clamped = clamp(
            requested,
            minimumCompactVerticalInset,
            maximumCompactVerticalInset
        )
        let maxFeasible = max((islandHeight - minimumCompactHeight) / 2, minimumCompactVerticalInset)
        if islandHeight.isFinite && islandHeight > 0 {
            return min(clamped, maxFeasible)
        }
        return clamped
    }

    public static func resolvedCompactOuterInset(
        preferredInset: CGFloat?,
        compactHeight: CGFloat,
        wallInset: CGFloat
    ) -> CGFloat {
        // 外侧间距属于 Island 自身的几何预算，不能通过扩大内容或视图尺寸
        // 放到容器之外。侧壁曲率只负责背景轮廓，不再抬高内容的自动边距。
        _ = compactHeight
        _ = wallInset
        let requested = preferredInset.flatMap(\.finiteValue) ?? defaultCompactOuterInset
        return clamp(requested, minimumCompactOuterInset, maximumCompactOuterInset)
    }
}

private extension CGFloat {
    var finiteValue: CGFloat? {
        isFinite ? self : nil
    }
}
