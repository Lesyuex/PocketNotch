import SwiftUI

public struct CompactIslandLayout<Left: View, Right: View>: View {
    public var layout: ResolvedCompactIslandLayout
    public var sideHorizontalOffset: CGFloat
    public var sideVerticalOffset: CGFloat
    @ViewBuilder public var left: () -> Left
    @ViewBuilder public var right: () -> Right

    public init(
        layout: ResolvedCompactIslandLayout,
        sideHorizontalOffset: CGFloat = 0,
        sideVerticalOffset: CGFloat = 0,
        @ViewBuilder left: @escaping () -> Left,
        @ViewBuilder right: @escaping () -> Right
    ) {
        self.layout = layout
        self.sideHorizontalOffset = sideHorizontalOffset
        self.sideVerticalOffset = sideVerticalOffset
        self.left = left
        self.right = right
    }

    public var body: some View {
        HStack(spacing: 0) {
            leftSlot
            Color.clear
                .frame(width: layout.centerNotchWidth)
            rightSlot
        }
        .frame(width: layout.islandWidth, height: layout.islandHeight)
    }

    private var leftSlot: some View {
        CompactIslandSideSlot(
            size: layout.sideRegionSize,
            contentSize: layout.leadingContentSize,
            outerInset: layout.containerOuterInset,
            edge: .leading,
            content: left
        )
        .offset(x: -sideHorizontalOffset, y: sideVerticalOffset)
    }

    private var rightSlot: some View {
        CompactIslandSideSlot(
            size: layout.sideRegionSize,
            contentSize: layout.trailingContentSize,
            outerInset: layout.containerOuterInset,
            edge: .trailing,
            content: right
        )
        .offset(x: sideHorizontalOffset, y: sideVerticalOffset)
    }
}

private struct CompactIslandSideSlot<Content: View>: View {
    enum Edge {
        case leading
        case trailing
    }

    let size: CGSize
    let contentSize: CGSize
    let outerInset: CGFloat
    let edge: Edge
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: alignment) {
            Color.clear

            content()
                .frame(
                    width: contentSize.width,
                    height: contentSize.height,
                    alignment: contentAlignment
                )
                .padding(outerPaddingEdge, outerInset)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// 这里接收的是矩形容器内实际偏移：透明肩部宽度 + 可见侧壁间距。
    /// 因此内容不会进入 mask 的透明区域，所有间距仍完全计入 Island 容器。
    private var alignment: Alignment {
        switch edge {
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    private var contentAlignment: Alignment {
        switch edge {
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    private var outerPaddingEdge: SwiftUI.Edge.Set {
        switch edge {
        case .leading: .leading
        case .trailing: .trailing
        }
    }

}

struct CompactIslandIndicatorView: View {
    var body: some View {
        TimelineView(.animation) { context in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    MeterBar(
                        height: barHeight(index: index, date: context.date)
                    )
                }
            }
            .frame(width: 22, height: 20)
            .opacity(0.88)
        }
    }

    private func barHeight(index: Int, date: Date) -> CGFloat {
        let phase = date.timeIntervalSinceReferenceDate * 2.8 + Double(index) * 0.72
        return 7 + CGFloat((sin(phase) + 1) * 0.5) * 9
    }
}

private struct MeterBar: View {
    var height: CGFloat

    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.82))
            .frame(width: 3, height: height)
    }
}
