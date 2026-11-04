import SwiftUI

public struct IslandCompactModuleTransitionConfiguration: Equatable, Sendable {
    public let insertionScale: CGFloat?
    public let removalScale: CGFloat?
    public let enterDuration: TimeInterval
    public let enterDelay: TimeInterval
    public let exitDuration: TimeInterval

    public static let standard = Self(
        insertionScale: 0.94,
        removalScale: 0.97,
        enterDuration: 0.17,
        enterDelay: 0.03,
        exitDuration: 0.11
    )

    public static let reducedMotion = Self(
        insertionScale: nil,
        removalScale: nil,
        enterDuration: 0.14,
        enterDelay: 0,
        exitDuration: 0.14
    )

    public static func resolved(reduceMotion: Bool) -> Self {
        reduceMotion ? .reducedMotion : .standard
    }
}

/// Island 动画参数的唯一入口。
public enum IslandAnimationToken {
    public static let hover = Animation.spring(
        response: 0.34,
        dampingFraction: 0.88,
        blendDuration: 0.04
    )

    public static let compactMorph = Animation.spring(
        response: 0.34,
        dampingFraction: 0.88,
        blendDuration: 0.04
    )

    public static let compactTierResize = Animation.spring(
        response: 0.42,
        dampingFraction: 1,
        blendDuration: 0.08
    )

    public static let expandedPageResize = Animation.spring(
        response: 0.38,
        dampingFraction: 1,
        blendDuration: 0.06
    )

    public static let compactTierContent = Animation.easeOut(duration: 0.18)

    public static let compactResidentModuleExit = Animation.easeOut(duration: 0.16)
    public static let compactResidentModuleEnter = Animation.easeOut(duration: 0.21)

    public static let hoverExit = Animation.spring(
        response: 0.28,
        dampingFraction: 0.94,
        blendDuration: 0.03
    )

    public static let hoverMaterial = hover

    public static let hoverGlow = Animation.easeOut(duration: 0.14)
    public static let hoverColor = Animation.easeOut(duration: 0.29)

    /// 展开背板：先快、减速、轻微回弹、停止。response 0.40 / damping 0.64
    /// 过冲约 7%，介于快冲（9.5%）与悠长（4%）之间——有劲道但不生硬。
    /// 顶部锚点始终固定。
    public static let expandBackground = Animation.spring(
        response: 0.40,
        dampingFraction: 0.64,
        blendDuration: 0.08
    )

    /// 收起合拢：比展开稍快、阻尼更高，关合干脆但不过分生硬、不拖尾。
    public static let collapseBackground = Animation.spring(
        response: 0.30,
        dampingFraction: 0.90,
        blendDuration: 0.04
    )

    /// 弹回灵动宽度的回弹动画：比关合稍韧，单次过冲可见，
    /// 与快关合形成「关得快、弹得韧」的节奏对比。
    public static let compactBounce = Animation.spring(
        response: 0.36,
        dampingFraction: 0.7,
        blendDuration: 0.04
    )

    /// 挤压的预备动作：把弹性通道快速压向底点，本身不产生跳变，
    /// 交接时仍带向内速度，回弹弹簧由此起步形成更深的谷底。
    public static let compactBounceAnticipation = Animation.spring(
        response: 0.23,
        dampingFraction: 0.85,
        blendDuration: 0.03
    )

    /// 档位回缩（二档 → 一档）的压缩预备：沿用收起回弹的蓄力手感，
    /// 但把回缩速度放慢一点点，回弹弹簧参数保持一致。
    public static let compactTierShrinkAnticipation = Animation.spring(
        response: 0.29,
        dampingFraction: 0.85,
        blendDuration: 0.03
    )

    /// 档位回缩（二档 → 一档）的回弹：与收起回弹同阻尼（保留 Q 弹过冲），
    /// 但把回弹速度放慢一点点。
    public static let compactTierShrinkBounce = Animation.spring(
        response: 0.40,
        dampingFraction: 0.7,
        blendDuration: 0.04
    )

    /// Q 弹挤压的底点宽度（相对灵动宽度的比例）。作用于叠加在几何之上的
    /// 弹性通道，不再让几何折返：底点越深，回弹行程越长。
    public static let compactSquashWidthRatio: CGFloat = 0.82

    /// 回弹过冲换算为宽度拉伸的比例：进度过冲 × 该系数 = 宽度过冲。
    /// 直接线性挂 0.06 会让弹簧的 ~10% 过冲只得到 0.6% 拉伸（不可见），
    /// 因此这里用更大的增益，让拉伸真正被眼睛看到。
    public static let compactBounceStretchGain: CGFloat = 0.4

    /// 高度方向的挤压/拉伸：比宽度克制，保持贴顶锚点与岛的比例感。
    public static let compactSquashHeightRatio: CGFloat = 0.95
    public static let compactBounceHeightStretchGain: CGFloat = 0.12

    public static let interactiveSettle = Animation.spring(
        response: 0.35,
        dampingFraction: 0.94,
        blendDuration: 0.03
    )

    public static let collapseMaterial = Animation.spring(
        response: 0.32,
        dampingFraction: 0.93,
        blendDuration: 0.02
    )

    public static let compactContentExit = Animation.easeOut(duration: 0.16)
    public static let compactContentEnter = Animation.easeOut(duration: 0.18)

    /// 展开时左右耳内容向中心退缩的比例：随淡出同步缩小，像被长开的背板
    /// 吞回刘海，而不是凭空淡掉，保持「同一块材质」的连续性。
    public static let compactContentRetreatScale: CGFloat = 0.96

    public static let compactModuleEnter = Animation
        .timingCurve(
            0.23,
            1,
            0.32,
            1,
            duration: IslandCompactModuleTransitionConfiguration.standard.enterDuration
        )
        .delay(IslandCompactModuleTransitionConfiguration.standard.enterDelay)
    public static let compactModuleExit = Animation
        .timingCurve(
            0.23,
            1,
            0.32,
            1,
            duration: IslandCompactModuleTransitionConfiguration.standard.exitDuration
        )

    public static let expandedContentEnter = Animation.spring(
        response: 0.38,
        dampingFraction: 0.95,
        blendDuration: 0.04
    )

    /// 锁屏 / 开锁符号换形：轻微回弹，像锁扣真正弹开。
    public static let screenLock = Animation.spring(
        response: 0.32,
        dampingFraction: 0.72,
        blendDuration: 0.04
    )

    /// 锁屏岛先从中心快速伸展到略宽于目标的过冲点。高阻尼只负责抵达，
    /// 避免第一段自行来回摆动，把清晰的弹性留给随后的回弹通道。
    public static let screenLockPresentation = Animation.spring(
        response: 0.24,
        dampingFraction: 0.88,
        blendDuration: 0.02
    )

    /// 从显式过冲点回到目标尺寸。较低阻尼产生一次清晰的反向越界，
    /// 让锁屏展开有橡胶般的 Q 弹，同时保持顶部边缘固定。
    public static let screenLockRebound = Animation.spring(
        response: 0.32,
        dampingFraction: 0.58,
        blendDuration: 0.02
    )

    public static let screenLockOvershootScaleX: CGFloat = 1.055

    public static let reducedMotion = Animation.easeOut(duration: 0.14)

    public static let compactActivationDelayNanoseconds: UInt64 = 16_000_000

    /// 展开页入场门控：逐帧观测展开进度超过该阈值即让展开页入场（内容已基本
    /// 被背板盖住），弹簧参数再调也不与背景运动脱节。
    public static let expandedContentEnterProgressThreshold: CGFloat = 0.35
    /// 展开页入场轮询的兜底期限：观测进度因环境（测试、打断）迟迟不涨时，
    /// 到点后仍入场，避免内容永远不出现。
    public static let expandedContentEnterDeadline: TimeInterval = 0.4

    /// 弹性通道起步时机：背板接近灵动宽度后才开始挤压，这样谷底落在
    /// 灵动宽度附近（而不是几何仍很宽时被比例缩放），观感才像「岛被捏了一下」。
    public static let compactBounceStartDelayNanoseconds: UInt64 = 190_000_000
    /// 挤压后交给回弹弹簧的时刻。取挤压弹簧尚未静止的时刻，交接保留向内速度。
    public static let compactBounceAnticipationDurationNanoseconds: UInt64 = 180_000_000
    /// 回弹弹簧起步后、左右耳开始恢复的延迟：内容在回弹拉伸段入场，
    /// 骑着弹回复位一起出现，不再等回弹完全收敛（消除收起尾段的空岛等待）。
    /// 此时宽度比例已 ≥ 1，不会挤压耳内内容。
    public static let compactContentReboundRideDelayNanoseconds: UInt64 = 120_000_000
    public static let compactContentRecoveryDelayNanoseconds: UInt64 = 170_000_000
    public static let compactContentRecoveryDurationNanoseconds: UInt64 = 150_000_000
    public static let reducedMotionDurationNanoseconds: UInt64 = 140_000_000
    public static let compactResidentModuleExitDurationNanoseconds: UInt64 = 130_000_000
}

public extension AnyTransition {
    static func islandCompactModule(reduceMotion: Bool) -> AnyTransition {
        let configuration = IslandCompactModuleTransitionConfiguration.resolved(
            reduceMotion: reduceMotion
        )
        guard let insertionScale = configuration.insertionScale,
              let removalScale = configuration.removalScale else {
            return .opacity
        }
        return .asymmetric(
            insertion: .scale(scale: insertionScale).combined(with: .opacity),
            removal: .scale(scale: removalScale).combined(with: .opacity)
        )
    }
}
