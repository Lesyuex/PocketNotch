import AppKit
import CoreGraphics

public extension NSScreen {
    /// CoreGraphics 提供的稳定显示器 UUID，可跨屏幕排序变化与重新连接保持一致。
    var pocketnotchDisplayIdentifier: String {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? NSNumber else {
            return "screen-\(localizedName)-\(Int(frame.midX))-\(Int(frame.midY))"
        }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        guard let displayUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        else { return "display-\(displayID)" }

        return CFUUIDCreateString(nil, displayUUID) as String
    }

    var isBuiltInDisplay: Bool {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? NSNumber else {
            return false
        }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        return CGDisplayIsBuiltin(displayID) != 0
    }

    /// 是否为带刘海机型（内置屏幕顶部有安全区）。
    ///
    /// 外接显示器也可能因为菜单栏/安全区返回非 0 的 `safeAreaInsets.top`，
    /// 但那不是物理刘海。这里必须限制为内置屏，避免外接屏误走硬件刘海布局。
    var hasNotch: Bool {
        isBuiltInDisplay && safeAreaInsets.top > 0
    }

    /// 刘海高度（无刘海时为 0）。
    var notchHeight: CGFloat {
        hasNotch ? safeAreaInsets.top : 0
    }

    /// 实测刘海缺口宽度：两侧安全区之间的空档。无刘海或系统未提供时返回 nil。
    /// 比设备档案里的静态 notchWidth 准，覆盖不在档案表里的新机型。
    var notchWidthMeasured: CGFloat? {
        guard hasNotch,
              let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea else { return nil }
        let width = right.minX - left.maxX
        return width > 0 ? width : nil
    }
}
