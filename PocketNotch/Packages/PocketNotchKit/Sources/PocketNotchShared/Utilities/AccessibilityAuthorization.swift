import ApplicationServices
import Foundation

/// 「数据访问」授权：接管系统音量/亮度键所依赖的「辅助功能」权限。
public enum AccessibilityAuthorization {
    /// 检查当前授权状态，未授权时触发系统授权弹窗；已授权时静默。
    /// 用户明确拒绝后 macOS 不会再弹窗，需引导前往系统设置手动开启。
    public static func promptIfNotTrusted() {
        guard !AXIsProcessTrusted() else { return }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }
}
