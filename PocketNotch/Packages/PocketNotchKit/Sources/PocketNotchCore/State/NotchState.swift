/// 岛的交互状态。
public enum NotchState: Equatable {
    case expanded   // 完整展开
    case dragging   // 拖拽中（Shelf 接管高亮）
}
