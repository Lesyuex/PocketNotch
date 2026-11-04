import SwiftUI

/// compact 耳与「此刻」页之间的元素几何接力。
///
/// 展开瞬间，耳内封面不再原地淡出、页面封面不再原地淡入：一个「旅行副本」
/// 从耳内封面起飞，随背板长开落位到页面封面的槽位。机制：
///
/// 1. 两端各自用 `islandHandoffSource` / `islandHandoffDestination` 持续上报
///    自身在接力坐标空间的 frame（`frame(in:)` 按帧求值，画布生长带来的
///    漂移会被自动修正，无需冻结）。
/// 2. Core 用与背板同源的 `expansionProgress` 派生接力进度 h，把副本在两端
///    frame 之间插值。h 是纯函数——展开中途反向收起时 h 沿原路退回，
///    接力天然连续可逆，不依赖任何任务编排。
/// 3. 两端静态封面通过环境值 `islandHandoffProgress` 让位/接管：
///    起飞窗口内耳内封面淡出、副本淡入；落位窗口内副本淡出、页面封面淡入。
public enum IslandHandoffSpace {
    /// 接力几何的统一坐标空间，声明在 `IslandContentLayer` 根部。
    /// 该空间在过渡期间保持稳定（过渡中变化的内层画布不作为参照）。
    public static let coordinateSpaceName = "islandContentHandoffSpace"
}

/// 接力飞行进度参数（h = expansionProgress / flightProgressSpan）。
public enum IslandContentHandoffToken {
    /// 飞行占展开进度的跨度：h = 1（落位）对应的 expansionProgress。
    /// 下限由背板 mask 决定：此刻页封面槽约在 p≈0.46 才被背板露出，
    /// 0.6 保证落位时槽位已完全进入轮廓且留有余量。
    public static let flightProgressSpan: CGFloat = 0.6
    /// 源端交叉淡化窗口（h 单位）：起飞时耳内封面淡出、副本淡入。
    public static let sourceFadeWindow: CGFloat = 0.12
    /// 目的端交叉淡化窗口（h 单位）：落位时副本淡出、页面封面淡入。
    public static let destinationFadeWindow: CGFloat = 0.12
}

/// 一个可接力元素的描述，由模块提供（如媒体模块提供封面），Core 消费。
public struct IslandContentHandoffDescriptor {
    /// 与模块 id 一致；两端 frame 上报与资格判断都以它为键。
    public let id: String
    /// 当前是否具备接力条件（如媒体正在播放且有真实封面）。
    public let isEligible: @MainActor () -> Bool
    /// 源端（compact 耳）封面的圆角。入参为耳内封面的实际渲染宽度。
    public let sourceCornerRadius: @MainActor (CGFloat) -> CGFloat
    /// 目的端封面的圆角。
    public let destinationCornerRadius: CGFloat
    /// 旅行副本内容：按目的端尺寸与插值圆角构建（图片解码尺寸恒定、命中
    /// 缓存；调用频繁，务必保持轻量）。
    public let destinationContent: @MainActor (CGSize, CGFloat) -> AnyView

    public init(
        id: String,
        isEligible: @escaping @MainActor () -> Bool,
        sourceCornerRadius: @escaping @MainActor (CGFloat) -> CGFloat,
        destinationCornerRadius: CGFloat,
        destinationContent: @escaping @MainActor (CGSize, CGFloat) -> AnyView
    ) {
        self.id = id
        self.isEligible = isEligible
        self.sourceCornerRadius = sourceCornerRadius
        self.destinationCornerRadius = destinationCornerRadius
        self.destinationContent = destinationContent
    }
}

struct IslandHandoffSourceFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(
        value: inout [String: CGRect],
        nextValue: () -> [String: CGRect]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct IslandHandoffDestinationFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(
        value: inout [String: CGRect],
        nextValue: () -> [String: CGRect]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct IslandHandoffProgressKey: EnvironmentKey {
    /// `nil` 表示当前没有进行中的接力；非 nil 时为 0...1 的接力进度。
    static let defaultValue: CGFloat? = nil
}

public extension EnvironmentValues {
    /// 接力进度。模块两端视图据此让位/接管自己的静态封面。
    var islandHandoffProgress: CGFloat? {
        get { self[IslandHandoffProgressKey.self] }
        set { self[IslandHandoffProgressKey.self] = newValue }
    }
}

private struct IslandHandoffSourceReporter: ViewModifier {
    let id: String
    let isActive: Bool

    func body(content: Content) -> some View {
        content.background {
            if isActive {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: IslandHandoffSourceFrameKey.self,
                        value: [id: proxy.frame(in: .named(IslandHandoffSpace.coordinateSpaceName))]
                    )
                }
            }
        }
    }
}

private struct IslandHandoffDestinationReporter: ViewModifier {
    let id: String

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: IslandHandoffDestinationFrameKey.self,
                    value: [id: proxy.frame(in: .named(IslandHandoffSpace.coordinateSpaceName))]
                )
            }
        }
    }
}

public extension View {
    /// 上报接力源端（compact 耳内元素）的 frame。`isActive` 为 false 时不参与接力。
    func islandHandoffSource(id: String, isActive: Bool = true) -> some View {
        modifier(IslandHandoffSourceReporter(id: id, isActive: isActive))
    }

    /// 上报接力目的端（此刻页封面槽）的 frame。
    func islandHandoffDestination(id: String) -> some View {
        modifier(IslandHandoffDestinationReporter(id: id))
    }

    /// 接力期间静态元素的让位/接管门控（透明度 + 命中测试）。
    func islandHandoffGate(_ role: IslandHandoffGate.Role) -> some View {
        modifier(IslandHandoffGate(role: role))
    }
}

/// 接力期间两端静态封面的让位/接管门控。
///
/// 刻意做成「自己读环境值的叶子修饰器」：接力进度逐帧变化时，只有这一小片
/// 视图重新求值。若让宿主视图（如含 Core Animation 光栅化的旋转封面、
/// 带时间线的媒体卡）直接读环境值，逐帧失效会连带宿主每帧重算乃至重绘，
/// 打爆 ProMotion 的帧预算。
public struct IslandHandoffGate: ViewModifier {
    public enum Role {
        /// 源端（compact 耳）：起飞窗口内淡出让位。
        case source
        /// 目的端（页面封面槽）：落位窗口内浮现接管，接管前不可命中。
        case destination
    }

    let role: Role
    @Environment(\.islandHandoffProgress) private var progress

    public func body(content: Content) -> some View {
        content
            .opacity(gate)
            .allowsHitTesting(gate > 0.999)
    }

    private var gate: CGFloat {
        switch role {
        case .source:
            guard let progress else { return 1 }
            let window = IslandContentHandoffToken.sourceFadeWindow
            return progress <= 0 ? 1 : max(0, 1 - progress / window)
        case .destination:
            guard let progress else { return 1 }
            let window = IslandContentHandoffToken.destinationFadeWindow
            return progress >= 1 ? 1 : max(0, (progress - (1 - window)) / window)
        }
    }
}
