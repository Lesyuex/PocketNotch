import AppKit
import PocketNotchShared
import PocketNotchCore
import ImageIO
import SwiftUI

/// 「剪贴板」标签页：历史条目以卡片形式横向排列、最新在最左，
/// 每条带类型图标（文本/链接/图片），点击卡片直接复制回剪贴板并弹「已复制」提示。
struct ClipboardExpandedView: View {
    let store: ClipboardStore

    @State private var showCopiedToast = false
    @State private var toastTask: Task<Void, Never>?
    /// 当前处于悬停状态的卡片 id：用于其它卡片同时做轻微压缩的联动动画。
    @State private var hoveringItemID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if store.items.isEmpty {
                emptyState
            } else {
                cardStrip
            }
        }
        .padding(.top, ClipboardExpandedLayout.topInset)
        .padding(.bottom, ClipboardExpandedLayout.bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    // MARK: - 卡片横排

    private var cardStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: ClipboardExpandedLayout.cardSpacing) {
                ForEach(store.items) { item in
                    card(for: item)
                }
            }
            .padding(.horizontal, ClipboardExpandedLayout.stripInsets)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// 构造单张卡片，方便类型检查器收敛复杂闭包。
    @ViewBuilder
    private func card(for item: ClipboardItem) -> some View {
        ClipboardCardView(
            item: item,
            isHighlighted: store.lastCopiedItemID == item.id,
            isSiblingHovered: hoveringItemID != nil,
            onHoverChanged: { hovered in
                if hovered {
                    hoveringItemID = item.id
                } else if hoveringItemID == item.id {
                    hoveringItemID = nil
                }
            },
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
            }
        )
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.white.opacity(0.42))

            Text("clipboard.empty")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.66))

            Text("clipboard.emptyDetail")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 复制反馈

    private var copiedToast: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))

            Text("clipboard.copied")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.96))
        .padding(.horizontal, 10)
        .frame(height: 20)
        .background {
            Capsule().fill(.white.opacity(0.16))
        }
        .overlay {
            Capsule().stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .opacity(showCopiedToast ? 1 : 0)
        .scaleEffect(showCopiedToast ? 1 : 0.85, anchor: .bottom)
        .offset(y: showCopiedToast ? -6 : 2)
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
}

/// 「剪贴板」标签页布局与样式参数。
private enum ClipboardExpandedLayout {
    static let topInset: CGFloat = 6
    static let bottomInset: CGFloat = 12
    static let stripInsets: CGFloat = 16
    static let cardWidth: CGFloat = 148
    static let cardHeight: CGFloat = 92
    static let cardSpacing: CGFloat = 12
    static let cornerRadius: CGFloat = 12
    static let bottomFrostHeight: CGFloat = 36
    static let bottomFrostBlur: CGFloat = 16
}

/// 剪贴板图片缩略图缓存：按条目 id 缓存降采样后的位图，NSCache 在内存紧张时自动逐出。
/// 避免每帧 body 重算（悬停/高亮/滚动）时对原图重复解码全尺寸位图。
private enum ClipboardThumbnailCache {
    private final class Key: NSObject {
        let id: UUID
        init(_ id: UUID) { self.id = id }
        override var hash: Int { id.hashValue }
        override func isEqual(_ object: Any?) -> Bool {
            (object as? Key)?.id == id
        }
    }

    private static let cache = NSCache<Key, NSImage>()

    /// 以约 2×卡片最长边的像素上限解码缩略图（Retina 足够清晰），
    /// 单张图片内存从全尺寸位图（可达数十 MB）降到约 0.2MB。
    static func thumbnail(for item: ClipboardItem) -> NSImage? {
        guard case .image(let data, _) = item.kind else { return nil }

        let key = Key(item.id)
        if let cached = cache.object(forKey: key) { return cached }

        let maxPixel = CGFloat(ClipboardExpandedLayout.cardWidth) * 2
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }
}

/// 单条剪贴板历史卡片：内容预览 + 底部类型/时间行，点击复制回剪贴板，
    /// 悬停时右上角出现删除按钮。
private struct ClipboardCardView: View {
    let item: ClipboardItem
    let isHighlighted: Bool
    let isSiblingHovered: Bool
    let onHoverChanged: (Bool) -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onToggleLock: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack {
            Button(action: onCopy) {
                VStack(alignment: .leading, spacing: 6) {
                    preview

                    bottomRow
                }
                .padding(9)
                .frame(
                    width: ClipboardExpandedLayout.cardWidth,
                    height: ClipboardExpandedLayout.cardHeight,
                    alignment: .leading
                )
                .background {
                    cardBackground
                }
                .overlay {
                    cardShape.stroke(borderColor, lineWidth: 1)
                }
                .contentShape(cardShape)
            }
            .buttonStyle(ClipboardCardButtonStyle())

            linkTypeButton

            lockBadge

            deleteButton
        }
        .scaleEffect(isSiblingHovered && !isHovering ? 0.97 : 1)
        .onHover { hovered in
            isHovering = hovered
            onHoverChanged(hovered)
        }
        .contextMenu {
            Button(item.isLocked ? "clipboard.unlock" : "clipboard.lock") {
                onToggleLock()
            }
        }
        .help(helpText)
        .accessibilityLabel(helpText)
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .animation(.easeOut(duration: 0.2), value: isHighlighted)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ClipboardExpandedLayout.cornerRadius, style: .continuous)
    }

    /// 卡片底色：图片条目直接以图片作为背景，其余条目用半透明白填充；
    /// 底部叠一层向上渐隐的毛玻璃，保证底部文字在图片上也能清晰可读。
    @ViewBuilder
    private var cardBackground: some View {
        ZStack(alignment: .bottom) {
            baseFill

            bottomFrost

            cardShape.fill(stateTint)
        }
        .clipShape(cardShape)
    }

    @ViewBuilder
    private var baseFill: some View {
        if let image = ClipboardThumbnailCache.thumbnail(for: item) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(
                    width: ClipboardExpandedLayout.cardWidth,
                    height: ClipboardExpandedLayout.cardHeight
                )
        } else {
            cardShape.fill(backgroundFill)
        }
    }

    /// 底部向上渐隐的毛玻璃：图片条目用自身模糊副本，向下最实、向上渐隐到透明；
    /// 文本/链接条目用底部加深渐变，保证底部文字对比度。
    @ViewBuilder
    private var bottomFrost: some View {
        ZStack {
            if let image = ClipboardThumbnailCache.thumbnail(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: ClipboardExpandedLayout.cardWidth,
                        height: ClipboardExpandedLayout.bottomFrostHeight,
                        alignment: .bottom
                    )
                    .blur(radius: ClipboardExpandedLayout.bottomFrostBlur)
            }

            if case .image = item.kind {
                LinearGradient(
                    colors: [.black.opacity(0.45), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
            } else {
                LinearGradient(
                    colors: [.black.opacity(0.28), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
            }
        }
        .frame(height: ClipboardExpandedLayout.bottomFrostHeight)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .mask(
            LinearGradient(
                colors: [.black, .clear],
                startPoint: .bottom,
                endPoint: .top
            )
        )
    }

    /// 底部信息行：类型图标 + 类型（左），复制时间（右）。链接类型的左侧让位给独立的跳转按钮。
    private var bottomRow: some View {
        HStack(spacing: 4) {
            if case .link = item.kind {
                Spacer(minLength: 0)
            } else {
                typeSymbol
                    .frame(width: 14, height: 14)

                Text(typeLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(typeTint)

                Spacer(minLength: 0)
            }

            Text(timeText)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.56))
        }
    }

    /// 链接类型的跳转按钮：叠放在左下角类型区域，本身即真实按钮（渲染唯一的蓝色「链接」），
    /// 点击用默认浏览器打开。
    @ViewBuilder
    private var linkTypeButton: some View {
        if case .link = item.kind {
            Button(action: openInBrowser) {
                HStack(spacing: 4) {
                    typeSymbol

                    Text(typeLabel)
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(typeTint)
                .contentShape(Rectangle())
            }
            .buttonStyle(ClipboardLinkOpenButtonStyle())
            .padding(9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .help("clipboard.openInBrowser")
            .accessibilityLabel("clipboard.openInBrowser")
        }
    }

    /// 用系统默认浏览器打开链接。
    private func openInBrowser() {
        guard case .link(let text) = item.kind,
              let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// 锁定标识：与删除按钮共用右上角槽位，未悬停时显示，悬停后让位给删除按钮。
    @ViewBuilder
    private var lockBadge: some View {
        if item.isLocked && !isHovering {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .padding(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// 悬停时出现在右上角的删除按钮：红色垃圾桶图标，点击删除该条历史。
    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.red)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
        .buttonStyle(ClipboardDeleteButtonStyle())
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .opacity(isHovering ? 1 : 0)
        .scaleEffect(isHovering ? 1 : 0.7)
        .allowsHitTesting(isHovering)
        .help("clipboard.deleteRecord")
        .accessibilityLabel("clipboard.deleteRecord")
        .animation(.spring(response: 0.24, dampingFraction: 0.8), value: isHovering)
    }

    private var typeSymbol: some View {
        Image(systemName: symbolName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(typeTint)
    }

    /// 类型着色：链接用蓝色提示可跳转，文本/图片用中性白。
    private var typeTint: Color {
        if case .link = item.kind { return .blue.opacity(0.88) }
        return .white.opacity(0.62)
    }

    private var symbolName: String {
        switch item.kind {
        case .text: return "doc.text"
        case .link: return "link"
        case .image: return "photo"
        }
    }

    private var typeLabel: String {
        switch item.kind {
        case .text: return L10n.tr("clipboard.textType")
        case .link: return L10n.tr("clipboard.linkType")
        case .image: return L10n.tr("clipboard.imageType")
        }
    }

    /// 内容预览：图片条目直接用图片本身撑满（背景即内容），文本/链接允许换行，
    /// 行数由可用高度决定，超高时以省略号截断。
    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .image:
            Spacer(minLength: 0)
        case .text, .link:
            GeometryReader { proxy in
                Text(previewText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(max(Int((proxy.size.height - 2) / 13), 1))
                    .truncationMode(.tail)
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: .topLeading
                    )
            }
        }
    }

    /// 单行预览：换行折叠成空格，避免撑坏卡片高度。
    private var previewText: String {
        item.text.replacingOccurrences(of: "\n", with: " ")
    }

    private var timeText: String {
        Self.timeFormatter.string(from: item.copiedAt)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var helpText: String {
        switch item.kind {
        case .text, .link: return L10n.tr("clipboard.copyBack")
        case .image: return L10n.tr("clipboard.copyImageBack")
        }
    }

    private var backgroundFill: Color {
        if isHighlighted { return .white.opacity(0.10) }
        return .white.opacity(isHovering ? 0.07 : 0.035)
    }

    /// 图片卡片上的悬停/高亮压暗层，保证交互反馈在图片背景上同样可见。
    private var stateTint: Color {
        if isHighlighted { return .black.opacity(0.16) }
        return .black.opacity(isHovering ? 0.10 : 0)
    }

    private var borderColor: Color {
        if isHighlighted { return .white.opacity(0.5) }
        return .white.opacity(isHovering ? 0.14 : 0.06)
    }
}

private struct ClipboardDeleteButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.86)
            .animation(
                reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.9),
                value: configuration.isPressed
            )
    }
}

private struct ClipboardLinkOpenButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.94)
            .animation(
                reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.9),
                value: configuration.isPressed
            )
    }
}

private struct ClipboardCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.97)
            .animation(
                reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.9),
                value: configuration.isPressed
            )
    }
}