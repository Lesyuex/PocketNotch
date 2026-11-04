import Foundation

/// 屏幕亮度提供方：读取当前亮度、执行亮度键命令。
/// 私有/脆弱 API（CoreDisplay）只能出现在 `SystemDisplayBrightnessService` 内。
protocol BrightnessProviding: AnyObject {
    func currentBrightness() -> Double?
    /// 返回 true 表示 PocketNotch 已完成调节，调用方可以吞掉亮度键事件。
    func perform(_ command: BrightnessCommand) -> Bool
}

extension BrightnessProviding {
    func currentBrightness() -> Double? { nil }
}