import CoreGraphics

/// 刘海机型的通用基准。
///
/// 缺口宽度优先通过 `NSScreen.notchWidthMeasured` 实时实测，覆盖所有机型；
/// 这里只保留无法实测时的兜底宽度，以及内容避让所需的间距参数。
public enum NotchDeviceProfile {
    public static let fallbackNotchWidth: CGFloat = 210
    public static let clearanceRatio: CGFloat = 0.18
    public static let minClearance: CGFloat = 4
    public static let maxClearance: CGFloat = 14

    public static func clearance(for notchHeight: CGFloat) -> CGFloat {
        min(maxClearance, max(minClearance, notchHeight * clearanceRatio))
    }
}
