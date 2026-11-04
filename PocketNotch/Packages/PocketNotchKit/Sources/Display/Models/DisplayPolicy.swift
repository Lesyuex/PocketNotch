import Foundation

/// 展示策略：决定「此刻该展示哪一类内容」。
///
/// 设计文档第十四章：本阶段只定义类别关系（Transient Notification > Agent > Activity），
/// 不实现成固定数值 priority，也不确定最终优先级数值。
/// 该协议允许未来插入更细的 `DisplayPolicy` 实现。
///
/// 策略返回一个**有序的赢家组**（同一优先级内的所有候选，按展示先后排序），
/// 由 `DisplayScheduler` 在组内用轮换索引挑选当前展示项，从而支持
/// 多个 Agent / 多个 Activity 的轮换（设计文档第九、十六章）。
public protocol DisplayPolicy {
    /// 对给定候选集，返回此刻应当展示的候选**组**（组内顺序即展示轮换顺序）。
    /// 空数组表示无可展示内容。
    func selectGroup(from candidates: [DisplayCandidate]) -> [DisplayCandidate]
}

/// 类别关系策略：Notification > Agent > Activity。
///
/// - 只要存在瞬时通知，就优先展示通知，并隐藏其它常驻内容。
/// - 否则，只要有 Agent 处于 Agent Display Pool（Running），就展示 Agent 组。
/// - 否则展示 Activity 组。
///
/// 重要：这里比较的是「类别」，而非固定数值。实现上没有魔法数字。
public struct CategoryDisplayPolicy: DisplayPolicy {
    public init() {}

    public func selectGroup(from candidates: [DisplayCandidate]) -> [DisplayCandidate] {
        let active = candidates.filter(\.isActive)
        guard !active.isEmpty else { return [] }

        // 类别优先级顺序，仅表达「类别关系」，不绑定具体数值。
        func rank(_ source: DisplaySource) -> Int {
            switch source {
            case .notification: 3
            case .agent: 2
            case .activity: 1
            }
        }

        // 找出最高类别。
        let topRank = active.map { rank($0.source) }.max() ?? 0
        // 取该类别内的所有候选作为赢家组，按「更新时间 → id」稳定排序以支持轮换。
        return active
            .filter { rank($0.source) == topRank }
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt < $1.updatedAt }
                return $0.id < $1.id
            }
    }
}
