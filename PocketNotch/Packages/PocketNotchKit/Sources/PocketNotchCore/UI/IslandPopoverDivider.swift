import SwiftUI

/// 岛内 popover 公用分隔线：统一材质与弱化透明度，
/// 供待办时间/列表弹层与媒体设备弹层共用。
public struct IslandPopoverDivider: View {
    private let verticalPadding: CGFloat

    public init(verticalPadding: CGFloat = 2) {
        self.verticalPadding = verticalPadding
    }

    public var body: some View {
        Rectangle()
            .fill(.white.opacity(0.05))
            .frame(height: 1)
            .padding(.vertical, verticalPadding)
    }
}