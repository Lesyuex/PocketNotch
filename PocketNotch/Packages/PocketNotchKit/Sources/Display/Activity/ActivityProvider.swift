import Foundation

/// 一种 Activity 的标识。遵循文档语义：
/// Activity 表示用户持续关注的信息（Music / Weather / Stock），
/// 生命周期较长、可轮换、没有 Session、没有「完成 / 失败」概念。
public enum ActivityKind: String, CaseIterable, Hashable, Sendable {
    case music
    case weather
    case stock

    public var displayName: String {
        switch self {
        case .music: "音乐"
        case .weather: "天气"
        case .stock: "股票"
        }
    }
}

/// 一种 Activity 的当前快照。
///
/// `ActivityStore` 只负责提供「当前有哪些 Activity、是否 active、数据、更新时间」，
/// 是否显示、何时显示、是否抢占 Agent 属于 `DisplayScheduler` 的职责。
public struct ActivityContent: Sendable, Equatable {
    public let kind: ActivityKind
    public let isActive: Bool
    public let updatedAt: Date
    /// 任意业务负载（音乐标题、天气温度、股票指数等）。Display 层不透传语义。
    public let payload: [String: Sendable]

    public init(kind: ActivityKind, isActive: Bool, updatedAt: Date, payload: [String: Sendable] = [:]) {
        self.kind = kind
        self.isActive = isActive
        self.updatedAt = updatedAt
        self.payload = payload
    }

    /// 相等性只比较结构化字段，忽略不透明 payload（负载不参与调度判断）。
    public static func == (lhs: ActivityContent, rhs: ActivityContent) -> Bool {
        lhs.kind == rhs.kind
            && lhs.isActive == rhs.isActive
            && lhs.updatedAt == rhs.updatedAt
    }
}

/// 让 `ActivityStore` 与具体业务解耦的只读查询契约。
/// 模块（Music / Weather / Stock）实现它并把自己的状态喂给 Store。
@MainActor
public protocol ActivityProviding {
    var kind: ActivityKind { get }
    func snapshot() -> ActivityContent
}