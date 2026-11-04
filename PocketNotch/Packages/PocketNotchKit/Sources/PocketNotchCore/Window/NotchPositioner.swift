import AppKit
import PocketNotchShared

/// 刘海尺寸探测与定位；无刘海机型/外接屏降级为顶部居中悬浮胶囊。
public struct NotchPositioner {
    public static let fallbackHiddenHeight: CGFloat = 32

    public init() {}

    public func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.hasNotch }) ?? NSScreen.main
    }

    public func hasNotch(on screen: NSScreen?) -> Bool {
        screen?.hasNotch ?? false
    }

    /// 计算面板在屏幕顶部居中的 frame，并把左右边缘对齐到同一像素网格。
    /// 收起时窗口宽度会从展开画布切回 compact；若分别舍入 origin 和 width，
    /// 最终中心可能偏移半个像素，视觉上会像 Island 向左轻移。
    public func frame(on screen: NSScreen, size: CGSize) -> NSRect {
        NotchWindowLayout.pixelAlignedTopCenteredFrame(
            in: screen.frame,
            size: size,
            backingScaleFactor: screen.backingScaleFactor
        )
    }

    public func contentTopInset(on screen: NSScreen) -> CGFloat {
        guard screen.hasNotch else { return 0 }
        return screen.notchHeight + NotchDeviceProfile.clearance(for: screen.notchHeight)
    }

    public func notchWidth(on screen: NSScreen) -> CGFloat {
        // 优先实测（覆盖不在档案表里的机型，如 Mac17,2），拿不到再回落静态档案值。
        if screen.hasNotch {
            return screen.notchWidthMeasured ?? NotchDeviceProfile.fallbackNotchWidth
        }
        // 无刘海屏（如外接屏）以内置刘海屏为基准模拟等宽刘海，保持跨屏视觉一致。
        return Self.referenceNotchWidth() ?? 0
    }

    /// 内置刘海屏的基准宽度。无内置刘海屏（Mac mini、无刘海 MacBook）时返回 nil。
    public static func referenceNotchWidth() -> CGFloat? {
        guard let notchScreen = referenceNotchScreen() else { return nil }
        return notchScreen.notchWidthMeasured ?? NotchDeviceProfile.fallbackNotchWidth
    }

    public static func referenceNotchScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.hasNotch })
    }

    public func menuBarHeight(on screen: NSScreen) -> CGFloat {
        let screenSpecificHeight = screen.frame.maxY - screen.visibleFrame.maxY
        if screenSpecificHeight > 0 {
            return Self.visualMenuBarHeight(
                reservedHeight: screenSpecificHeight,
                backingScaleFactor: screen.backingScaleFactor
            )
        }
        return Self.resolvedHiddenHeight(
            notchHeight: 0,
            menuBarHeight: NSStatusBar.system.thickness
        )
    }

    static func visualMenuBarHeight(
        reservedHeight: CGFloat,
        backingScaleFactor: CGFloat
    ) -> CGFloat {
        guard reservedHeight.isFinite, reservedHeight > 0 else {
            return fallbackHiddenHeight
        }
        let scale = backingScaleFactor.isFinite && backingScaleFactor > 0
            ? backingScaleFactor
            : 1
        let reservedPixels = floor(reservedHeight * scale)
        return max(reservedPixels - 1, 1) / scale
    }

    static func resolvedHiddenHeight(
        notchHeight: CGFloat,
        menuBarHeight: CGFloat
    ) -> CGFloat {
        if notchHeight.isFinite, notchHeight > 0 { return notchHeight }
        if menuBarHeight.isFinite, menuBarHeight > 0 { return menuBarHeight }
        return fallbackHiddenHeight
    }

    public static var fallbackHiddenIslandSize: CGSize {
        var metrics = PocketNotchTheme.islandBackgroundMetrics
        metrics.hiddenHeight = fallbackHiddenHeight
        metrics.hiddenWidth = IslandAppearanceConstraints.automaticRestingBodyWidth(
            physicalNotchWidth: 0
        )
        return metrics.hiddenSize
    }

    public func hiddenIslandSize(on screen: NSScreen) -> CGSize {
        var metrics = PocketNotchTheme.islandBackgroundMetrics
        metrics.hiddenHeight = Self.resolvedHiddenHeight(
            notchHeight: screen.notchHeight,
            menuBarHeight: menuBarHeight(on: screen)
        )

        guard screen.hasNotch else {
            // 有内置刘海屏时，外接/无刘海屏的隐藏岛按内置刘海等宽等高模拟，
            // 让窗口换屏前后外观一致；完全没有刘海屏才回落浮动悬浮岛基准。
            if let reference = Self.referenceNotchScreen() {
                metrics.hiddenHeight = Self.resolvedHiddenHeight(
                    notchHeight: reference.notchHeight,
                    menuBarHeight: menuBarHeight(on: reference)
                )
                metrics.hiddenWidth = IslandAppearanceConstraints.automaticRestingBodyWidth(
                    physicalNotchWidth: Self.referenceNotchWidth() ?? 0
                )
                return metrics.hiddenSize
            }
            // 无任何刘海屏（Mac mini、无刘海 MacBook）的隐藏岛高度回落到系统菜单栏高度；
            // 菜单栏高度也拿不到时，resolvedHiddenHeight 再兜底默认 32。
            metrics.hiddenHeight = Self.resolvedHiddenHeight(
                notchHeight: 0,
                menuBarHeight: menuBarHeight(on: screen)
            )
            // 无刘海屏把约束默认的「模拟刘海」宽度作为唯一基准上报，
            // 与解析出的中心缺口 / resting 主体宽度（fallback 200）保持一致，
            // 不再返回 300pt 的材质默认宽度。
            metrics.hiddenWidth = IslandAppearanceConstraints.automaticRestingBodyWidth(
                physicalNotchWidth: 0
            )
            return metrics.hiddenSize
        }

        metrics.hiddenWidth = clamp(notchWidth(on: screen), 210, 230)
        // 刘海屏严格使用系统实测的安全区高度，让 Island 底边与物理刘海底边对齐。
        // clearance 只适用于内容避让，不能叠加到黑色背板高度，否则 Island 会高出刘海。
        return metrics.hiddenSize
    }
}
