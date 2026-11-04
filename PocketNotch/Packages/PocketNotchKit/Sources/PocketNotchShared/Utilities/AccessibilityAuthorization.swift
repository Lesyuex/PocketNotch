import ApplicationServices
import Foundation

/// 「辅助功能」授权提示：整个安装生命周期内只提示一次，避免每次启动重复弹系统授权窗。
public enum AccessibilityAuthorization {
    private static let didPromptDefaultsKey = "com.pocketnotch.permission.accessibilityPromptedOnce"

    /// 从未提示过时触发一次系统授权弹窗；之后无论用户是否授权都不再打扰。
    public static func promptOnceIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didPromptDefaultsKey) else { return }
        defaults.set(true, forKey: didPromptDefaultsKey)
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }
}
