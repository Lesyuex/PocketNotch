import PocketNotchCore
import SwiftUI

/// 音量条已解析的填充样式：纯色或双色线性渐变。
/// 持有 `VolumeBarColor`（可比较、可持久化），需要渲染时才转成 SwiftUI 样式。
enum VolumeBarFillStyle {
    case solid(VolumeBarColor)
    case gradient(VolumeBarColor, VolumeBarColor)

    /// 转成可填入形状的样式。渐变统一沿水平方向，随填充宽度收缩。
    var shapeStyle: AnyShapeStyle {
        switch self {
        case .solid(let color):
            AnyShapeStyle(color.color)
        case .gradient(let start, let end):
            AnyShapeStyle(
                LinearGradient(
                    colors: [start.color, end.color],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }
}

/// 把「音量条颜色」设置解析为最终填充。渲染端只消费解析结果，不依赖设置实体。
enum VolumeBarFillResolver {
    /// 渐变预设：当前应用图标主题的渐变色。开发期从 App 图标一次性取色后写死，
    /// 不实时读取图标（图标不变，默认渐变也不应随运行波动）。
    static let appIconGradientStart = VolumeBarColor(red: 0.993, green: 0.731, blue: 0.535)
    static let appIconGradientEnd = VolumeBarColor(red: 0.194, green: 0.131, blue: 0.130)

    static func resolve(
        style: VolumeBarColorStyle,
        palette: [Color],
        hasActiveMedia: Bool,
        customColor: VolumeBarColor,
        usesCustomGradient: Bool,
        customGradientEndColor: VolumeBarColor
    ) -> VolumeBarFillStyle {
        switch style {
        case .standard:
            return .solid(.default)
        case .coverTheme:
            // 只在媒体播放且已取到封面主色时采用主题色，否则回退默认白。
            guard hasActiveMedia, let primary = palette.first else { return .solid(.default) }
            let primaryColor = VolumeBarColor(color: primary)
            if usesCustomGradient, let secondary = palette.dropFirst().first {
                return .gradient(primaryColor, VolumeBarColor(color: secondary))
            }
            return .solid(primaryColor)
        case .gradient:
            return .gradient(appIconGradientStart, appIconGradientEnd)
        case .custom:
            if usesCustomGradient {
                return .gradient(customColor, customGradientEndColor)
            }
            return .solid(customColor)
        }
    }
}