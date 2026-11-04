import AppKit
import PocketNotchShared
import PocketNotchCore
import SwiftUI

/// 「此刻」页剪贴板小卡：无背景容器，始终展示标题区，
/// 有记录时以列表方式按页展示最近条目（每页 4 条，可纵向滚动翻页，新复制在最上），
/// 点条目复制回剪贴板并弹「已复制」提示；
/// 悬停时行尾出现跳转按钮（链接）与删除按钮，图片条目以缩略图方式解码，不碰原图。
struct NowClipboardCardView: View {
    let store: ClipboardStore

    /// 每页容纳的行数。
    private static let pageSize = 3

    @State private var showCopiedToast = false
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Design.contentSpacing) {
            header

            content
        }
        .padding(.horizontal, Design.horizontalPadding)
        .padding(.top, Design.topPadding)
        .frame(
            width: IslandLayoutToken.expandedNowPageClipboardCardWidth,
            height: IslandLayoutToken.expandedNowPageCardHeight,
            alignment: .top
        )
        .overlay(alignment: .bottom) {
            copiedToast
        }
        .onDisappear {
            toastTask?.cancel()
        }
        .onChange(of: store.lastCopiedItemID) { _, newID in
            if newID != nil {
                presentCopiedToast()
            }
        }
    }

    // MARK: - 标题行

    /// 标题行：图标芯片 + 标题 + 数量徽标，量级按 Apple 卡片标题的
    /// 「前导材质芯片 / 语义标题 / 尾部计数徽章」三层结构组织，字号与字距贴合系统层级。
    private var header: some View {
        HStack(spacing: Design.headerSpacing) {
            headerIcon

            Text("clipboard.title")
                .font(.system(size: Design.titleSize, weight: .semibold))
                .tracking(Design.titleTracking)
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)

            Spacer(minLength: 4)

            countBadge
        }
        .frame(height: Design.headerHeight, alignment: .center)
    }

    /// 前导图标芯片：柔和渐变底 + 连续圆角，符号居中光学对齐。
    private var headerIcon: some View {
        Image(systemName: "doc.on.clipboard.fill")
            .font(.system(size: Design.iconGlyphSize, weight: .semibold))
            .foregroundStyle(.white.opacity(0.95))
            .frame(width: Design.iconSize, height: Design.iconSize)
            .background {
                RoundedRectangle(cornerRadius: Design.iconCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.16), .white.opacity(0.07)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: Design.iconCornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }

    /// 数量徽标：胶囊底 + 等宽数字，避免计数跳动时宽度抖动。
    private var countBadge: some View {
        Text("\(store.items.count)")
            .font(.system(size: Design.countSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.62))
            .padding(.horizontal, Design.badgeHorizontalPadding)
            .frame(height: Design.badgeHeight)
            .background {
                Capsule().fill(.white.opacity(0.08))
            }
    }

    // MARK: - 内容区

    /// 内容区：空态时居中提示，否则按页展示列表；条目超过一页的数量时纵向滚动翻页。
    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            emptyHint
        } else if pageCount > 1 {
            pagedScroll
        } else {
            rowsList(store.items)
        }
    }

    /// 某一页的条目列表。
    private func rowsList(_ items: [ClipboardItem]) -> some View {
        VStack(spacing: NowClipboardListLayout.rowSpacing) {
            ForEach(items) { item in
                NowClipboardRowView(
                    item: item,
                    isHighlighted: store.lastCopiedItemID == item.id,
                    onCopy: { store.reuse(item) },
                    onDelete: {
                        withAnimation(.easeOut(duration: 0.18)) {
                            store.remove(item)
                        }
                    },
                    onToggleLock: {
                        withAnimation(.easeOut(duration: 0.18)) {
                            store.toggleLock(item)
                        }
                    },
                    onOpenLink: openInBrowser
                )
                .equatable()
            }
        }
    }

    /// 纵向分页滚动：每页固定 3 行高度，纯靠原生分页驱动，不干预滚动位置，保证跟手。
    private var pagedScroll: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // 页数有限（最多 13 页 × 4 行），非懒堆一次性布局，
            // 避免滚动时每帧做懒加载测量，减少主线程开销。
            VStack(spacing: 0) {
                ForEach(0..<pageCount, id: \.self) { page in
                    rowsList(pageItems(page))
                        .frame(
                            width: NowClipboardListLayout.rowWidth,
                            height: NowClipboardListLayout.pageHeight,
                            alignment: .top
                        )
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollBounceBehavior(.basedOnSize)
        .frame(
            width: NowClipboardListLayout.rowWidth,
            height: NowClipboardListLayout.pageHeight
        )
    }

    private func pageItems(_ page: Int) -> [ClipboardItem] {
        let start = page * Self.pageSize
        guard start < store.items.count else { return [] }
        return Array(store.items[start..<min(start + Self.pageSize, store.items.count)])
    }

    private var pageCount: Int {
        max(1, (store.items.count + Self.pageSize - 1) / Self.pageSize)
    }

    /// 用系统默认浏览器打开链接条目。
    private func openInBrowser(_ item: ClipboardItem) {
        guard case .link(let text) = item.kind,
              let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return }
        NSWorkspace.shared.open(url)
    }

    private var emptyHint: some View {
        HStack(spacing: 5) {
            Image(systemName: "clipboard")
                .font(.system(size: Design.emptyIconSize, weight: .light))
                .foregroundStyle(.white.opacity(0.35))

            Text("clipboard.emptyHint")
                .font(.system(size: Design.emptyTextSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 复制反馈

    private var copiedToast: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark")
                .font(.system(size: 7, weight: .bold))

            Text("clipboard.copied")
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.95))
        .padding(.horizontal, 8)
        .frame(height: 17)
        .background {
            Capsule().fill(.black.opacity(0.55))
        }
        .overlay {
            Capsule().stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .opacity(showCopiedToast ? 1 : 0)
        .scaleEffect(showCopiedToast ? 1 : 0.85, anchor: .bottom)
        .offset(y: showCopiedToast ? -8 : 2)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: showCopiedToast)
    }

    private func presentCopiedToast() {
        toastTask?.cancel()
        withAnimation { showCopiedToast = true }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { showCopiedToast = false }
        }
    }

    private enum Design {
        static let horizontalPadding: CGFloat = 7
        static let topPadding: CGFloat = 8
        static let contentSpacing: CGFloat = 6
        static let headerHeight: CGFloat = 24
        static let headerSpacing: CGFloat = 5
        static let titleSize: CGFloat = 10
        static let titleTracking: CGFloat = 0.2
        static let iconSize: CGFloat = 14
        static let iconCornerRadius: CGFloat = 4.5
        static let iconGlyphSize: CGFloat = 8
        static let countSize: CGFloat = 8
        static let badgeHeight: CGFloat = 12
        static let badgeHorizontalPadding: CGFloat = 4
        static let emptyIconSize: CGFloat = 13
        static let emptyTextSize: CGFloat = 8
    }
}

/// 此刻页剪贴板列表布局参数：由岛内容宽（180 - 水平留白 14）与每页 3 行推出。
private enum NowClipboardListLayout {
    static let rowWidth: CGFloat = 166
    static let rowHeight: CGFloat = 24
    static let rowSpacing: CGFloat = 5
    static let rowCornerRadius: CGFloat = 6
    /// 每页 4 行 + 行距占据的高度（滚动页的高）；配合 10pt 顶部留白，卡内余 15pt 底部呼吸。
    static let pageHeight: CGFloat = rowHeight * 4 + rowSpacing * 3
    static let leadingGlyphSize: CGFloat = 16
    static let actionButtonSize: CGFloat = 18
    static let actionSymbolSize: CGFloat = 8.5
    /// 缩略图最大边长：约 2× 行内前导图的物理尺寸（Retina 下足够清晰）即可。
    static let thumbnailMaxPixelSize: CGFloat = 48
}

/// 列表中的单条剪贴板记录：点击复制回剪贴板；图片条目前导显示缩略图，
/// 其余条目显示类型图标 + 单行预览；悬停时行尾出现跳转按钮（链接）与删除按钮，
/// 行本身不因悬停变亮，仅高亮最近一次复制的行。
private struct NowClipboardRowView: View, Equatable {
    let item: ClipboardItem
    let isHighlighted: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onToggleLock: () -> Void
    let onOpenLink: (ClipboardItem) -> Void

    nonisolated static func == (lhs: NowClipboardRowView, rhs: NowClipboardRowView) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.isHighlighted == rhs.isHighlighted
            && lhs.item.isLocked == rhs.item.isLocked
    }

    @State private var isHovering = false
    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: onCopy) {
            HStack(spacing: 5) {
                leadingGlyph

                Text(previewText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(previewOpacity))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                ZStack(alignment: .trailing) {
                    actions

                    if item.isLocked && !isHovering {
                        lockIcon
                    }
                }
                .animation(.easeOut(duration: 0.15), value: isHovering)
            }
            .padding(.horizontal, 6)
            .frame(width: NowClipboardListLayout.rowWidth, height: NowClipboardListLayout.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: NowClipboardListLayout.rowCornerRadius, style: .continuous)
                    .fill(backgroundFill)
            }
            .contentShape(RoundedRectangle(cornerRadius: NowClipboardListLayout.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(NowClipboardRowPressStyle())
        .contextMenu {
            Button(item.isLocked ? "clipboard.unlock" : "clipboard.lock") {
                onToggleLock()
            }
        }
        .onHover { isHovering = $0 }
        .task(id: item.id) {
            guard case .image(let data, _) = item.kind else { return }
            thumbnail = await Self.loadThumbnail(for: item.id, data: data)
        }
        .help(helpText)
        .accessibilityLabel(helpText)
        .animation(.easeOut(duration: 0.2), value: isHighlighted)
    }

    // MARK: - 行内容

    /// 前导图示：图片条目用缩略图，加载中回退到类型图标；其余条目直接用类型图标。
    @ViewBuilder
    private var leadingGlyph: some View {
        switch item.kind {
        case .image:
            if let t = thumbnail {
                Image(nsImage: t)
                    .resizable()
                    .scaledToFill()
                    .frame(width: NowClipboardListLayout.leadingGlyphSize, height: NowClipboardListLayout.leadingGlyphSize)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
            } else {
                typeSymbol
            }
        case .text, .link:
            typeSymbol
        }
    }

    /// 锁定标识：与删除按钮共用行尾槽位，未悬停时显示，悬停后让位给操作按钮。
    private var lockIcon: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: NowClipboardListLayout.actionSymbolSize, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(
                width: NowClipboardListLayout.actionButtonSize,
                height: NowClipboardListLayout.actionButtonSize
            )
            .accessibilityHidden(true)
    }

    /// 行尾悬停操作：链接条目显示跳转按钮，全部类型显示删除按钮；不占额外槽位，淡入淡出。
    private var actions: some View {
        HStack(spacing: 2) {
            if case .link = item.kind {
                Button(action: openLink) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: NowClipboardListLayout.actionSymbolSize, weight: .semibold))
                        .foregroundStyle(.blue.opacity(0.9))
                        .frame(width: NowClipboardListLayout.actionButtonSize, height: NowClipboardListLayout.actionButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(NowClipboardRowPressStyle())
                .help("clipboard.openInBrowser")
                .accessibilityLabel("clipboard.openInBrowser")
            }

            Button(action: onDelete) {
                Image(systemName: "trash.fill")
                    .font(.system(size: NowClipboardListLayout.actionSymbolSize, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: NowClipboardListLayout.actionButtonSize, height: NowClipboardListLayout.actionButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NowClipboardRowPressStyle())
            .help("clipboard.deleteRecord")
            .accessibilityLabel("clipboard.deleteRecord")
        }
        .opacity(isHovering ? 1 : 0)
        .scaleEffect(isHovering ? 1 : 0.8)
        .allowsHitTesting(isHovering)
        .animation(.spring(response: 0.2, dampingFraction: 0.84), value: isHovering)
    }

    private func openLink() {
        onOpenLink(item)
    }

    // MARK: - 缩略图

    /// 缩略图：后台线程按目标像素解码，NSCache 按原图字节数计代价缓存，避免主线程整图解码卡顿。
    private static func loadThumbnail(for id: UUID, data: Data) async -> NSImage? {
        let key = "now-clipboard-\(id.uuidString)" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        let decode = Task.detached(priority: .userInitiated) {
            Self.decodeThumbnail(from: data)
        }
        guard let image = try? await decode.value else { return nil }
        thumbnails.setObject(image, forKey: key, cost: data.count)
        return image
    }

    private static func decodeThumbnail(from data: Data) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: NowClipboardListLayout.thumbnailMaxPixelSize,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    private static let thumbnails = NSCache<NSString, NSImage>()

    // MARK: - 派生视觉

    private var typeSymbol: some View {
        Image(systemName: symbolName)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(typeTint)
            .frame(width: NowClipboardListLayout.leadingGlyphSize, height: NowClipboardListLayout.leadingGlyphSize)
    }

    /// 类型着色：链接用蓝色提示可跳转，文本/图片用中性白。
    private var typeTint: Color {
        if case .link = item.kind { return .blue.opacity(0.9) }
        return .white.opacity(0.6)
    }

    private var symbolName: String {
        switch item.kind {
        case .text: return "doc.text"
        case .link: return "link"
        case .image: return "photo"
        }
    }

    /// 图片条目的行内预览文案：以「图片」占位，留出缩略图的前导展示。
    private var previewText: String {
        if case .image = item.kind { return L10n.tr("clipboard.imageType") }
        return item.text.replacingOccurrences(of: "\n", with: " ")
    }

    private var previewOpacity: Double {
        if case .image = item.kind { return 0.55 }
        return 0.85
    }

    private var helpText: String {
        switch item.kind {
        case .text, .link: return L10n.tr("clipboard.copyBack")
        case .image: return L10n.tr("clipboard.copyImageBack")
        }
    }

    /// 行底色与待办卡月份格背景一致（.white 0.08），最近复制的行微亮到 0.14。
    private var backgroundFill: Color {
        if isHighlighted { return .white.opacity(0.14) }
        return .white.opacity(0.08)
    }
}

private struct NowClipboardRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}