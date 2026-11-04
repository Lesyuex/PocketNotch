import SwiftUI

struct IslandGlowColorPreferenceKey: PreferenceKey {
    static let defaultValue: Color? = nil

    static func reduce(value: inout Color?, nextValue: () -> Color?) {
        if let color = nextValue() {
            value = color
        }
    }
}

public extension View {
    /// 由岛内内容向容器提供动态发光色；未提供时容器使用主题默认色。
    func islandGlowColor(_ color: Color?) -> some View {
        preference(key: IslandGlowColorPreferenceKey.self, value: color)
    }
}
