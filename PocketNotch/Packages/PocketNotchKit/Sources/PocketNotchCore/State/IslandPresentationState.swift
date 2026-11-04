import CoreGraphics

/// Island 的呈现阶段，覆盖隐藏态、灵动态、展开态及两端过渡。
public enum IslandPresentationPhase: Equatable, Sendable {
    case hidden
    case idle
    case hover
    case expanding
    case expanded
    case interactive
    case collapsing
}

public enum IslandPresentationTransition: Equatable, Sendable {
    case compact
    case expanding
    case expanded
    case collapsing
}

/// Compact 形态分为无内容的默认刘海和有两侧内容的灵动态。
public enum IslandCompactForm: Equatable, Sendable {
    case resting
    case dynamic
}

/// 纯状态推导器。视图层仍持有动画所需的呈现值，但阶段语义集中在这里。
public enum IslandPresentationStateMachine {
    public static func phase(
        transition: IslandPresentationTransition,
        isHovered: Bool,
        isExpandedContentVisible: Bool
    ) -> IslandPresentationPhase {
        switch transition {
        case .compact:
            return isHovered ? .hover : .idle
        case .expanding:
            return .expanding
        case .expanded:
            return isExpandedContentVisible ? .interactive : .expanded
        case .collapsing:
            return .collapsing
        }
    }

    public static func compactForm(showsCompactContent: Bool) -> IslandCompactForm {
        showsCompactContent ? .dynamic : .resting
    }
}
