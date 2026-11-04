import SwiftUI

public struct IslandBackgroundMetrics: Equatable, Sendable {
    public var hiddenWidth: CGFloat
    public var hiddenHeight: CGFloat
    public var collapsedWidth: CGFloat
    public var collapsedHeight: CGFloat
    public var expandedWidth: CGFloat
    public var expandedHeight: CGFloat
    public var topShoulderWidthRatio: CGFloat
    public var topShoulderDepthRatio: CGFloat
    public var hiddenTopCornerRatio: CGFloat

    public init(
        hiddenWidth: CGFloat = 300,
        hiddenHeight: CGFloat = 38,
        collapsedWidth: CGFloat = 300,
        collapsedHeight: CGFloat = 72,
        expandedWidth: CGFloat = 420,
        expandedHeight: CGFloat = 176,
        topShoulderWidthRatio: CGFloat = 0.12,
        topShoulderDepthRatio: CGFloat = 0.38,
        hiddenTopCornerRatio: CGFloat = 0.46
    ) {
        self.hiddenWidth = hiddenWidth
        self.hiddenHeight = hiddenHeight
        self.collapsedWidth = collapsedWidth
        self.collapsedHeight = collapsedHeight
        self.expandedWidth = expandedWidth
        self.expandedHeight = expandedHeight
        self.topShoulderWidthRatio = topShoulderWidthRatio
        self.topShoulderDepthRatio = topShoulderDepthRatio
        self.hiddenTopCornerRatio = hiddenTopCornerRatio
    }

    public static let `default` = IslandBackgroundMetrics()

    public var hiddenSize: CGSize {
        CGSize(width: hiddenWidth, height: hiddenHeight)
    }

    public var collapsedSize: CGSize {
        CGSize(width: collapsedWidth, height: collapsedHeight)
    }

    public var expandedSize: CGSize {
        CGSize(width: expandedWidth, height: expandedHeight)
    }

    public static func interpolated(
        from start: IslandBackgroundMetrics,
        to end: IslandBackgroundMetrics,
        progress: CGFloat
    ) -> IslandBackgroundMetrics {
        let progress = clamp(progress, 0, 1)
        func interpolate(_ start: CGFloat, _ end: CGFloat) -> CGFloat {
            start + (end - start) * progress
        }

        return IslandBackgroundMetrics(
            hiddenWidth: interpolate(start.hiddenWidth, end.hiddenWidth),
            hiddenHeight: interpolate(start.hiddenHeight, end.hiddenHeight),
            collapsedWidth: interpolate(start.collapsedWidth, end.collapsedWidth),
            collapsedHeight: interpolate(start.collapsedHeight, end.collapsedHeight),
            expandedWidth: interpolate(start.expandedWidth, end.expandedWidth),
            expandedHeight: interpolate(start.expandedHeight, end.expandedHeight),
            topShoulderWidthRatio: interpolate(
                start.topShoulderWidthRatio,
                end.topShoulderWidthRatio
            ),
            topShoulderDepthRatio: interpolate(
                start.topShoulderDepthRatio,
                end.topShoulderDepthRatio
            ),
            hiddenTopCornerRatio: interpolate(
                start.hiddenTopCornerRatio,
                end.hiddenTopCornerRatio
            )
        )
    }

    public static func resolved(
        hiddenIslandSize: CGSize,
        notchPhysicalWidth: CGFloat,
        expandedModuleCount: Int,
        showsCompactContent: Bool = true,
        preferredRestingHeight: CGFloat? = nil,
        preferredRestingWidth: CGFloat? = nil,
        preferredCompactOuterInset: CGFloat? = nil,
        preferredCompactVerticalInset: CGFloat? = nil,
        preferredEarHeight: CGFloat? = nil,
        preferredCompactWidth: CGFloat? = nil,
        preferredExpandedContentHeight: CGFloat? = nil,
        preferredExpandedTotalHeight: CGFloat? = nil,
        preferredExpandedContentWidth: CGFloat? = nil,
        minimumExpandedContentHeight: CGFloat = IslandLayoutToken.expandedContentHeight,
        expandedContentTopInset: CGFloat = IslandLayoutToken.expandedContentTopInset,
        expandedContentBottomInset: CGFloat = IslandLayoutToken.expandedContentVerticalInset
    ) -> IslandBackgroundMetrics {
        var metrics = PocketNotchTheme.islandBackgroundMetrics
        let hasPhysicalNotch = notchPhysicalWidth > 0
        let measuredNotchHeight = hasPhysicalNotch && hiddenIslandSize.height > 0
            ? hiddenIslandSize.height
            : 0
        // 隐藏态与灵动态共用同一个岛体高度，内容出现/消失时岛高不再跳变。
        let baseIslandHeight = IslandAppearanceConstraints.resolvedRestingHeight(
            preferredHeight: preferredRestingHeight,
            physicalNotchHeight: measuredNotchHeight,
            defaultIslandHeight: hiddenIslandSize.height
        )
        // 耳朵（内容槽）高度独立于岛高：未设置时默认 24。内容高度只取耳朵，
        // 不随岛高变化，因此调高岛高不会撑大耳朵，也不会改变岛宽。
        let requestedEarHeight = preferredEarHeight.map {
            clamp(
                $0,
                IslandAppearanceConstraints.minimumCompactHeight,
                IslandAppearanceConstraints.maximumEarHeight
            )
        }
        let earHeight = requestedEarHeight ?? IslandAppearanceConstraints.defaultCompactHeight
        // 岛高只需装得下用户显式设置的耳朵；未设置耳朵时沿用隐藏态高度，不额外抬高。
        let resolvedIslandHeight = max(
            baseIslandHeight,
            (requestedEarHeight ?? 0) + IslandAppearanceConstraints.minimumCompactVerticalInset * 2
        )
        if !showsCompactContent {
            metrics.hiddenHeight = resolvedIslandHeight
            let restingBodyWidth = IslandAppearanceConstraints.resolvedRestingWidth(
                preferredWidth: preferredRestingWidth,
                physicalNotchWidth: notchPhysicalWidth,
                restingHeight: resolvedIslandHeight
            )
            let shoulderWidth = NotchShapeSpec.restingShoulderWidth(forHeight: resolvedIslandHeight)
            metrics.hiddenWidth = restingBodyWidth + shoulderWidth * 2
        } else {
            let islandHeight = resolvedIslandHeight
            let restingBodyWidth = IslandAppearanceConstraints.resolvedRestingWidth(
                preferredWidth: preferredRestingWidth,
                physicalNotchWidth: notchPhysicalWidth,
                restingHeight: islandHeight
            )
            let contentHeight = earHeight
            let verticalInset = min(
                max(
                    (islandHeight - earHeight) / 2,
                    IslandAppearanceConstraints.minimumCompactVerticalInset
                ),
                IslandAppearanceConstraints.maximumCompactVerticalInset
            )
            let layout = ResolvedCompactIslandLayout.resolve(
                contentHeight: contentHeight,
                minimumIslandHeight: islandHeight,
                notchPhysicalWidth: notchPhysicalWidth,
                restingBodyWidth: restingBodyWidth,
                preferredCompactOuterInset: preferredCompactOuterInset,
                preferredCompactVerticalInset: verticalInset,
                preferredCompactWidth: preferredCompactWidth,
                fitsAutomaticContentToMinimumHeight: false
            )
            metrics.hiddenHeight = layout.islandHeight
            metrics.hiddenWidth = layout.islandWidth
        }

        metrics.collapsedWidth = metrics.hiddenWidth + 72
        metrics.collapsedHeight = metrics.hiddenHeight + 34

        // 展开页使用稳定、克制的独立画布，内容在背板完成拉伸后再入场。
        // 不按注册模块数量无限放大，避免仅注册后台模块就让 Island 突然占据大半屏幕。
        _ = expandedModuleCount
        if let preferredExpandedContentWidth {
            // 简约模式按内容比例计算宽度，至少覆盖物理刘海，避免大面积留白。
            metrics.expandedWidth = max(preferredExpandedContentWidth, metrics.hiddenWidth)
        } else {
            // 其余标签页与「此刻」页共享同一展开宽度：此刻页内容折叠出的整窗宽度为基准。
            metrics.expandedWidth = max(
                IslandLayoutToken.expandedNowPageTotalWidth,
                metrics.hiddenWidth + 240
            )
        }
        let expandedContentHeight = clamp(
            preferredExpandedContentHeight ?? IslandLayoutToken.expandedContentHeight,
            minimumExpandedContentHeight,
            IslandLayoutToken.maximumExpandedContentHeight
        )
        if let preferredExpandedTotalHeight {
            // 「此刻」页以含顶部刘海的整窗高度为目标，倒推内容画布高度，
            // 保证即使隐藏态高度随设置变化，整窗总高也严格等于目标值。
            let derivedContentHeight = clamp(
                preferredExpandedTotalHeight
                    - metrics.hiddenHeight
                    - expandedContentTopInset
                    - expandedContentBottomInset,
                0,
                IslandLayoutToken.maximumExpandedContentHeight
            )
            metrics.expandedHeight = metrics.hiddenHeight
                + derivedContentHeight
                + expandedContentTopInset
                + expandedContentBottomInset
        } else {
            metrics.expandedHeight = metrics.hiddenHeight
                + expandedContentHeight
                + expandedContentTopInset
                + expandedContentBottomInset
        }
        return metrics
    }
}

public func clamp(_ value: CGFloat, _ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
    min(max(value, minValue), maxValue)
}

/// 隐藏态布局的统一解析结果。中心缺口始终等于物理刘海宽度；总长度的变化
/// 只分配给 compact 两侧区域，内容保持锚定在 Island 外侧边缘。
public struct ResolvedCompactIslandLayout: Equatable, Sendable {
    /// 包含左右肩部的最终容器/路径宽度，仅供渲染与画布布局使用。
    public let islandWidth: CGFloat
    /// 用户配置与业务规则使用的主体宽度，不包含肩部。
    public let bodyWidth: CGFloat
    public let islandHeight: CGFloat
    public let centerNotchWidth: CGFloat
    public let sideRegionWidth: CGFloat
    /// 单侧肩部宽度；保留 wallInset 别名兼容已有布局语义。
    public let shoulderWidth: CGFloat
    public var wallInset: CGFloat { shoulderWidth }
    public let contentHeight: CGFloat
    /// 去除肩部、隐藏态主体和两侧边距后，左右平分得到的单耳宽度。
    public let leadingContentWidth: CGFloat
    public let trailingContentWidth: CGFloat
    public let verticalInset: CGFloat
    public let innerGap: CGFloat
    /// 内容与黑色可见侧壁之间的设计间距。
    public let outerInset: CGFloat

    /// 内容相对矩形 Island 容器边缘的实际偏移。路径在外侧含透明肩部，
    /// 因此实际偏移必须同时包含肩部宽度和可见间距。
    public var containerOuterInset: CGFloat { shoulderWidth + outerInset }

    public var sideRegionSize: CGSize {
        CGSize(width: sideRegionWidth, height: islandHeight)
    }

    public var leadingContentSize: CGSize {
        CGSize(width: leadingContentWidth, height: contentHeight)
    }

    public var trailingContentSize: CGSize {
        CGSize(width: trailingContentWidth, height: contentHeight)
    }

    public static func resolve(
        contentHeight: CGFloat,
        minimumIslandHeight: CGFloat = IslandAppearanceConstraints.defaultFloatingRestingHeight,
        notchPhysicalWidth: CGFloat,
        restingBodyWidth preferredRestingBodyWidth: CGFloat? = nil,
        preferredCompactOuterInset: CGFloat? = nil,
        preferredCompactVerticalInset: CGFloat? = nil,
        preferredCompactWidth: CGFloat? = nil,
        fitsAutomaticContentToMinimumHeight: Bool = false
    ) -> ResolvedCompactIslandLayout {
        let requestedContentHeight = max(
            contentHeight,
            IslandAppearanceConstraints.minimumCompactHeight
        )
        let clampedPreferredInset = clamp(
            preferredCompactVerticalInset ?? IslandAppearanceConstraints.defaultCompactVerticalInset,
            IslandAppearanceConstraints.minimumCompactVerticalInset,
            IslandAppearanceConstraints.maximumCompactVerticalInset
        )
        let resolvedContentHeight: CGFloat
        let verticalInset: CGFloat
        let height: CGFloat
        if fitsAutomaticContentToMinimumHeight {
            height = max(minimumIslandHeight, 1)
            verticalInset = IslandAppearanceConstraints.minimumCompactVerticalInset
            resolvedContentHeight = max(
                height - verticalInset * 2,
                IslandAppearanceConstraints.minimumCompactHeight
            )
        } else {
            let desiredIslandHeight = requestedContentHeight + clampedPreferredInset * 2
            height = max(desiredIslandHeight, max(minimumIslandHeight, 1))
            verticalInset = min(
                max(
                    (height - requestedContentHeight) / 2,
                    IslandAppearanceConstraints.minimumCompactVerticalInset
                ),
                IslandAppearanceConstraints.maximumCompactVerticalInset
            )
            resolvedContentHeight = height - verticalInset * 2
        }
        let centerWidth = IslandAppearanceConstraints.resolvedNotchWidth(
            physicalNotchWidth: notchPhysicalWidth
        )
        let outerInset = IslandAppearanceConstraints.resolvedCompactOuterInset(
            preferredInset: preferredCompactOuterInset,
            compactHeight: height,
            wallInset: NotchShapeSpec.insetMin
        )

        _ = preferredRestingBodyWidth
        let computedDefaultBodyWidth = IslandAppearanceConstraints.defaultCompactBodyWidth(
            physicalNotchWidth: notchPhysicalWidth
        )
        let finitePreferredWidth = preferredCompactWidth.flatMap(\.finiteLayoutValue)
        let requestedBodyWidth = finitePreferredWidth ?? computedDefaultBodyWidth
        let bodyWidth = clamp(
            requestedBodyWidth,
            computedDefaultBodyWidth,
            IslandAppearanceConstraints.maximumCompactWidth
        )
        let shoulderWidth = NotchShapeSpec.shoulderWidth(forBodyWidth: bodyWidth)
        // compact 两侧内容宽度随内容高度变化（如方形封面），因此宽度预算必须按当前
        // 内容高度推导；中心缺口装不下内容预算时岛向中心方向加宽，内容随之外扩但
        // 始终与物理刘海保留安全间隙，绝不压缩内容槽造成遮挡。
        let squareSideContentWidth = max(
            resolvedContentHeight * CompactIslandContentSpec.leadingWidthHeightRatio,
            resolvedContentHeight,
            CompactIslandContentSpec.defaultSideContentWidth
        )
        // 一档：内容槽保持方形（=耳朵高度），宽度增长的空间全部落在内容与物理刘海
        // 之间的内侧间距，外侧间距不变。二档（股票/媒体等宽内容，宽度 ≥ 345）：
        // 外侧间距保持，宽度增长让内容槽变宽以容纳宽内容。
        let expandedEarWidth = (
            bodyWidth
                - centerWidth
                - outerInset * 2
                - IslandAppearanceConstraints.minimumCompactInnerGap * 2
        ) / 2
        let sideContentWidth = bodyWidth >= CompactIslandTier.secondTierMinimumWidth
            ? max(squareSideContentWidth, expandedEarWidth)
            : squareSideContentWidth
        let minimumSideRegionWidth = shoulderWidth
            + outerInset
            + sideContentWidth
            + IslandAppearanceConstraints.minimumCompactInnerGap
        let islandWidth = max(
            bodyWidth + shoulderWidth * 2,
            centerWidth + minimumSideRegionWidth * 2
        )
        let resolvedBodyWidth = islandWidth - shoulderWidth * 2
        let sideRegionWidth = (islandWidth - centerWidth) / 2
        let earWidth = sideContentWidth
        let innerGap = max(
            IslandAppearanceConstraints.minimumCompactInnerGap,
            sideRegionWidth - shoulderWidth - outerInset - earWidth
        )

        return ResolvedCompactIslandLayout(
            islandWidth: islandWidth,
            bodyWidth: resolvedBodyWidth,
            islandHeight: height,
            centerNotchWidth: centerWidth,
            sideRegionWidth: sideRegionWidth,
            shoulderWidth: shoulderWidth,
            contentHeight: resolvedContentHeight,
            leadingContentWidth: earWidth,
            trailingContentWidth: earWidth,
            verticalInset: verticalInset,
            innerGap: innerGap,
            outerInset: outerInset
        )
    }
}

// compact 两侧内容（封面/旋律条）的尺寸与间距规则——全部由统一布局结果推导。
// 总长度增长时，内容保持距外侧边缘为用户设置值，多出的空间留在内容与物理刘海之间。
public enum CompactIslandContentSpec {
    /// 自动长度下内容与物理刘海之间的最低安全间隙。
    public static let innerGap = IslandAppearanceConstraints.minimumCompactInnerGap
    public static let defaultSideContentWidth: CGFloat = 24
    public static let leadingWidthHeightRatio =
        defaultSideContentWidth / IslandAppearanceConstraints.defaultCompactHeight

    public static func verticalInset(forHeight height: CGFloat) -> CGFloat {
        IslandAppearanceConstraints.resolvedCompactVerticalInset(
            preferred: nil,
            islandHeight: height
        )
    }

    public static func resolvedContentHeight(for proposedHeight: CGFloat) -> CGFloat {
        let v = verticalInset(forHeight: proposedHeight)
        return IslandAppearanceConstraints.compactContentHeight(islandHeight: proposedHeight, verticalInset: v)
    }

    // 左耳需要容纳横向状态符号；额外宽度只向物理刘海方向增长，外侧间距不变。
    public static func leadingContentWidth(forHeight height: CGFloat) -> CGFloat {
        max(
            resolvedContentHeight(for: height) * leadingWidthHeightRatio,
            defaultSideContentWidth
        )
    }

    // 右耳文字内容仍在圆形视口内自适应。
    public static func trailingContentWidth(forHeight height: CGFloat) -> CGFloat {
        max(resolvedContentHeight(for: height), defaultSideContentWidth)
    }

    public static func cornerRadius(forHeight height: CGFloat) -> CGFloat {
        resolvedContentHeight(for: height) * 0.27
    }

    public static func outerInset(forHeight height: CGFloat, wallInset: CGFloat) -> CGFloat {
        IslandAppearanceConstraints.resolvedCompactOuterInset(
            preferredInset: nil,
            compactHeight: height,
            wallInset: wallInset
        )
    }

    public static func sideRegionWidth(forHeight height: CGFloat, wallInset: CGFloat) -> CGFloat {
        wallInset
            + outerInset(forHeight: height, wallInset: wallInset)
            + max(leadingContentWidth(forHeight: height), trailingContentWidth(forHeight: height))
            + IslandAppearanceConstraints.minimumCompactInnerGap
    }
}

private extension CGFloat {
    var finiteLayoutValue: CGFloat? { isFinite ? self : nil }
}

// 刘海/背板形状的唯一几何真相来源。规则说明与推导见 docs/NOTCH-SHAPE.md。
// 收起态（hidden）落码于 makeHiddenScreenNotchPath；后续展开态背板必须复用同一套“顶内凹 + 底外凸 + 竖直侧壁”规则。
public enum NotchShapeSpec {
    // 灵动态单侧肩部保持原有比例与 18–28 pt 安全范围，但作为独立预算维护。
    // 由主体宽度求外轮廓时使用解析式，避免“总宽决定肩部、肩部又决定总宽”的迭代。
    public static let insetRatio: CGFloat = 0.0545
    public static let insetMin: CGFloat = 18
    public static let insetMax: CGFloat = 28
    // 隐藏态与灵动态必须共享完全相同的“收紧”曲率，不能再由各自高度推导，
    // 否则内容出现后高度变化会让肩部弧度悄悄改变。展开时肩部与底角分别平滑过渡到展开半径。
    public static let compactCornerRadius: CGFloat = 5
    public static let compactBottomCornerRadius: CGFloat = 12
    public static let expandedCornerRadius: CGFloat = 22
    public static let expandedBottomCornerRadius: CGFloat = 30

    // 保留原有公开名称作为兼容别名；新的路径统一通过 expansionProgress 插值。
    public static let cornerRadiusRatio: CGFloat = 0.35
    public static let cornerRadiusMin = compactCornerRadius
    public static let cornerRadiusMax = expandedCornerRadius
    public static let topConcaveRatio = cornerRadiusRatio
    public static let topConcaveMin = compactCornerRadius
    public static let topConcaveMax = expandedCornerRadius
    public static let bottomConvexRatio = cornerRadiusRatio
    public static let bottomConvexMin = compactBottomCornerRadius
    public static let bottomConvexMax = expandedBottomCornerRadius

    /// 将动画进度转为首尾速度为零的曲率进度。默认展开插值已不再套用它——
    /// 背板尺寸与圆角必须吃同一条弹簧的原始进度（含过冲），否则会出现
    /// 「长开先动、圆角后追」的两层违和。保留该函数仅作外部急停工具。
    public static func easedExpansionProgress(_ progress: CGFloat) -> CGFloat {
        let normalized = clamp(progress, 0, 1)
        return normalized * normalized * (3 - 2 * normalized)
    }

    public static func cornerRadius(
        forHeight height: CGFloat,
        expansionProgress: CGFloat = 0
    ) -> CGFloat {
        let progress = max(expansionProgress, 0)
        let interpolatedRadius = compactCornerRadius
            + (expandedCornerRadius - compactCornerRadius) * progress
        return min(interpolatedRadius, max(height, 0) / 2)
    }

    public static func topConcaveRadius(
        forHeight height: CGFloat,
        expansionProgress: CGFloat = 0
    ) -> CGFloat {
        cornerRadius(forHeight: height, expansionProgress: expansionProgress)
    }

    public static func bottomConvexRadius(
        forHeight height: CGFloat,
        expansionProgress: CGFloat = 0
    ) -> CGFloat {
        let progress = max(expansionProgress, 0)
        let interpolatedRadius = compactBottomCornerRadius
            + (expandedBottomCornerRadius - compactBottomCornerRadius) * progress
        return min(interpolatedRadius, max(height, 0) / 2)
    }

    public static func restingShoulderWidth(forHeight height: CGFloat) -> CGFloat {
        topConcaveRadius(forHeight: height)
    }

    public static func shoulderWidth(forOuterWidth outerWidth: CGFloat) -> CGFloat {
        clamp(outerWidth * insetRatio, insetMin, insetMax)
    }

    public static func shoulderWidth(forBodyWidth bodyWidth: CGFloat) -> CGFloat {
        let denominator = max(1 - insetRatio * 2, 0.001)
        return clamp(bodyWidth * insetRatio / denominator, insetMin, insetMax)
    }

    public static func outerWidth(forBodyWidth bodyWidth: CGFloat) -> CGFloat {
        bodyWidth + shoulderWidth(forBodyWidth: bodyWidth) * 2
    }

    public static func bodyWidth(forOuterWidth outerWidth: CGFloat) -> CGFloat {
        outerWidth - shoulderWidth(forOuterWidth: outerWidth) * 2
    }
}

public func makePlainIslandPath(width: CGFloat, height: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.addRect(CGRect(x: 0, y: 0, width: width, height: height))
    return path
}

public func makeRestingNotchMaskPath(
    width: CGFloat,
    height: CGFloat,
    expansionProgress: CGFloat = 0
) -> CGPath {
    // width 包含两侧肩部；竖直主体位于 [shoulderWidth, width - shoulderWidth]。
    // 主体宽度已按“物理刘海 + 左右各 3 pt”解析，肩部只负责曲线延展。
    let shoulderRadius = NotchShapeSpec.topConcaveRadius(
        forHeight: height,
        expansionProgress: expansionProgress
    )
    let bottomCornerRadius = NotchShapeSpec.bottomConvexRadius(
        forHeight: height,
        expansionProgress: expansionProgress
    )
    return makeConcaveShoulderNotchPath(
        width: width,
        height: height,
        wallInset: shoulderRadius,
        shoulderRadius: shoulderRadius,
        bottomCornerRadius: bottomCornerRadius
    )
}

public func makeTopShoulderIslandPath(
    width: CGFloat,
    height: CGFloat,
    shoulderWidthRatio: CGFloat = 0.12,
    shoulderDepthRatio: CGFloat = 0.38
) -> CGPath {
    let shoulderWidth = clamp(width * shoulderWidthRatio, 28, min(width * 0.22, 92))
    let shoulderDepth = clamp(height * shoulderDepthRatio, 12, min(height * 0.58, 56))
    let leftBodyX = shoulderWidth
    let rightBodyX = width - shoulderWidth

    let path = CGMutablePath()
    path.move(to: CGPoint(x: leftBodyX, y: height))
    path.addLine(to: CGPoint(x: leftBodyX, y: shoulderDepth))
    path.addCurve(
        to: CGPoint(x: 0, y: 0),
        control1: CGPoint(x: leftBodyX, y: shoulderDepth * 0.38),
        control2: CGPoint(x: leftBodyX * 0.38, y: 0)
    )
    path.addLine(to: CGPoint(x: width, y: 0))
    path.addCurve(
        to: CGPoint(x: rightBodyX, y: shoulderDepth),
        control1: CGPoint(x: width - shoulderWidth * 0.38, y: 0),
        control2: CGPoint(x: rightBodyX, y: shoulderDepth * 0.38)
    )
    path.addLine(to: CGPoint(x: rightBodyX, y: height))
    path.addLine(to: CGPoint(x: leftBodyX, y: height))
    path.closeSubpath()
    return path
}

public func makeHiddenScreenNotchPath(
    width: CGFloat,
    height: CGFloat,
    shoulderWidthRatio: CGFloat = 0.12,
    shoulderDepthRatio: CGFloat = 0.38,
    topCornerRatio: CGFloat = 0.46,
    expansionProgress: CGFloat = 0
) -> CGPath {
    // 经典刘海形（方案 G3a-ii，规则见 docs/NOTCH-SHAPE.md）：
    //   满宽略宽平顶 + 顶部两角【内凹】(quad, 圆心在壁顶) + 竖直侧壁 + 底部两角【外凸】
    //   ────────╮        ╭────────
    //           ╰────────╯
    // 顶角内凹让刘海平滑融入屏幕；底角外凸是可见的圆角。四条竖直/水平边均相切，无折点。
    let inset = NotchShapeSpec.shoulderWidth(forOuterWidth: width)
    return makeConcaveShoulderNotchPath(
        width: width,
        height: height,
        wallInset: inset,
        shoulderRadius: NotchShapeSpec.topConcaveRadius(
            forHeight: height,
            expansionProgress: expansionProgress
        ),
        bottomCornerRadius: NotchShapeSpec.bottomConvexRadius(
            forHeight: height,
            expansionProgress: expansionProgress
        )
    )
}

private func makeConcaveShoulderNotchPath(
    width: CGFloat,
    height: CGFloat,
    wallInset: CGFloat,
    shoulderRadius: CGFloat,
    bottomCornerRadius: CGFloat,
    topOverscan: CGFloat = 0
) -> CGPath {
    let wallL = wallInset
    let wallR = width - wallInset
    let topY = -max(topOverscan, 0)

    let path = CGMutablePath()
    path.move(to: CGPoint(x: wallL - shoulderRadius, y: topY))
    path.addLine(to: CGPoint(x: wallR + shoulderRadius, y: topY))
    // 右上内凹角（圆心在右壁顶 wallR,0）
    path.addQuadCurve(to: CGPoint(x: wallR, y: shoulderRadius),
                      control: CGPoint(x: wallR, y: topY))
    path.addLine(to: CGPoint(x: wallR, y: height - bottomCornerRadius))
    // 右下外凸圆角
    path.addQuadCurve(to: CGPoint(x: wallR - bottomCornerRadius, y: height),
                      control: CGPoint(x: wallR, y: height))
    path.addLine(to: CGPoint(x: wallL + bottomCornerRadius, y: height))
    // 左下外凸圆角
    path.addQuadCurve(to: CGPoint(x: wallL, y: height - bottomCornerRadius),
                      control: CGPoint(x: wallL, y: height))
    path.addLine(to: CGPoint(x: wallL, y: shoulderRadius))
    // 左上内凹角（圆心在左壁顶 wallL,0）
    path.addQuadCurve(to: CGPoint(x: wallL - shoulderRadius, y: topY),
                      control: CGPoint(x: wallL, y: topY))
    path.closeSubpath()
    return path
}

public enum IslandBackgroundState: Equatable, Sendable {
    case hidden
    case collapsed
    case expanded
}

public struct NotchShape: Shape {
    public var state: IslandBackgroundState
    public var metrics: IslandBackgroundMetrics
    public var expansionProgress: CGFloat
    public var compactMorphProgress: CGFloat
    public var rendersInFullBounds: Bool

    public init(
        state: IslandBackgroundState,
        metrics: IslandBackgroundMetrics = .default,
        expansionProgress: CGFloat? = nil,
        compactMorphProgress: CGFloat = 1,
        rendersInFullBounds: Bool = false
    ) {
        self.state = state
        self.metrics = metrics
        self.expansionProgress = expansionProgress
            ?? IslandBackgroundPath.defaultExpansionProgress(for: state)
        self.compactMorphProgress = compactMorphProgress
        self.rendersInFullBounds = rendersInFullBounds
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(expansionProgress, compactMorphProgress) }
        set {
            expansionProgress = newValue.first
            compactMorphProgress = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        Path(
            IslandBackgroundPath.makePath(
                for: state,
                in: rect,
                metrics: metrics,
                expansionProgress: expansionProgress,
                compactMorphProgress: compactMorphProgress,
                rendersInFullBounds: rendersInFullBounds
            )
        )
    }
}

public enum IslandBackgroundPath {
    public static func defaultExpansionProgress(for state: IslandBackgroundState) -> CGFloat {
        state == .expanded ? 1 : 0
    }

    public static func makePath(
        for state: IslandBackgroundState,
        in rect: CGRect,
        metrics: IslandBackgroundMetrics = .default,
        expansionProgress: CGFloat? = nil,
        compactMorphProgress: CGFloat = 1,
        rendersInFullBounds: Bool = false
    ) -> CGPath {
        let targetSize = size(for: state, metrics: metrics)
        let width = rendersInFullBounds ? rect.width : min(targetSize.width, rect.width)
        let height = rendersInFullBounds ? rect.height : min(targetSize.height, rect.height)
        let originX = rect.midX - width / 2
        let rawProgress = expansionProgress ?? defaultExpansionProgress(for: state)
        // 尺寸与圆角共用同一条弹簧的原始进度：圆角起步、过冲、收敛的时间
        // 与岛体长开完全一致，不再额外套 smoothstep（否则展开期圆角跟随滞后、
        // 过冲被裁剪，观感像两层材质）。下限钳 0 防止欠冲时圆角小于紧凑半径。
        let curveProgress = max(rawProgress, 0)
        // 所有状态共用同一套进度插值曲率：收缩态按住/展开动画全程渐变，
        // 展开终态自然收敛到 expandedCornerRadius / expandedBottomCornerRadius，
        // 从灵动态进入展开态不会出现曲率瞬间跳变。
        let shoulderRadius = NotchShapeSpec.topConcaveRadius(
            forHeight: height,
            expansionProgress: rawProgress
        )
        let bottomCornerRadius = NotchShapeSpec.bottomConvexRadius(
            forHeight: height,
            expansionProgress: rawProgress
        )

        // resting 与 dynamic 沿同一组路径命令连续形变；展开终态都收敛到 shoulderRadius。
        let restingWallInset = shoulderRadius
        let dynamicCompactWallInset = NotchShapeSpec.shoulderWidth(forOuterWidth: width)
        let dynamicWallInset = dynamicCompactWallInset
            + (shoulderRadius - dynamicCompactWallInset) * curveProgress
        let wallInset = restingWallInset
            + (dynamicWallInset - restingWallInset) * clamp(compactMorphProgress, 0, 1)
        let basePath = makeConcaveShoulderNotchPath(
            width: width,
            height: height,
            wallInset: wallInset,
            shoulderRadius: shoulderRadius,
            bottomCornerRadius: bottomCornerRadius,
            // 肩部必须在屏幕顶边以水平切线起步。把曲线起点上移做 overscan
            // 会让屏幕边缘裁掉圆弧开头，小半径下尤其像被截断。
            topOverscan: 0
        )

        var transform = CGAffineTransform(translationX: originX, y: rect.minY)
        return basePath.copy(using: &transform) ?? basePath
    }

    public static func size(for state: IslandBackgroundState, metrics: IslandBackgroundMetrics = .default) -> CGSize {
        switch state {
        case .hidden:
            return metrics.hiddenSize
        case .collapsed:
            return metrics.collapsedSize
        case .expanded:
            return metrics.expandedSize
        }
    }
}
