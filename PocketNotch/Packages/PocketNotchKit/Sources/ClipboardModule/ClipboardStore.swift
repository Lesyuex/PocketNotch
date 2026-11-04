import AppKit
import Foundation
import PocketNotchCore
import Observation
import os.lock

/// 剪贴板历史：最多保留 50 条（新在前），重复内容自动去重并置顶；锁定条目始终置顶、
/// 不会被新内容替换或挤出上限，随历史一起持久化，重启应用后自动恢复。
/// 支持文本、链接与图片三种类型；通过轮询系统剪贴板的 changeCount 感知外部复制，
/// 点选某条会复制回系统剪贴板，历史顺序保持不变。展开页标签切换由用户在「此刻」页标题区手动发起。
@MainActor
@Observable
final class ClipboardStore {
    static let maxItems = 50

    private(set) var items: [ClipboardItem] = []
    /// 最近一次复制命中的条目 id，驱动行内短暂高亮反馈。
    private(set) var lastCopiedItemID: UUID?

    private var pollingTimer: DispatchSourceTimer?
    /// 后台轮询独立队列 + 快照锁：主线程只在剪贴板真正变化时才被唤醒。
    private let clipboardQueue = DispatchQueue(label: "pocketnotch.clipboard-poll", qos: .utility)
    private let changeCountLock = OSAllocatedUnfairLock(initialState: 0)
    private var highlightGeneration = 0
    private var saveTask: Task<Void, Never>?
    private let pasteboard: NSPasteboard
    private let expansionRequest: ExpandedTabRequestController?

    init(
        pasteboard: NSPasteboard = .general,
        expansionRequest: ExpandedTabRequestController? = nil
    ) {
        self.pasteboard = pasteboard
        self.expansionRequest = expansionRequest
        self.items = Self.loadPersisted()
    }

    func start() {
        guard pollingTimer == nil else { return }
        // 后台轮询 changeCount，只有真的变了才回主线程入账；
        // 空闲时主线程零唤醒（原实现 0.6s 一次 Task 上主循环）。
        changeCountLock.withLock { $0 = pasteboard.changeCount }
        let pasteboard = self.pasteboard
        let source = DispatchSource.makeTimerSource(queue: clipboardQueue)
        source.schedule(deadline: .now(), repeating: 0.6, leeway: .milliseconds(100))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let latest = pasteboard.changeCount
            let changed = self.changeCountLock.withLock { $0 != latest }
            self.changeCountLock.withLock { $0 = latest }
            guard changed else { return }
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        source.resume()
        pollingTimer = source
    }

    func stop() {
        pollingTimer?.cancel()
        pollingTimer = nil
    }

    /// 检查外部复制：系统剪贴板内容变了，按「图片文件 > 文本/链接 > 图片数据」顺序收录。
    /// （changeCount 的判别已由后台轮询完成，这里只负责入账最新内容。）
    func refresh() {
        if let image = readImageFileURL() {
            addImage(data: image.data, filename: image.filename)
            return
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            add(text)
            return
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            addImage(data: data)
        }
    }

    /// 收录一条文本：自动识别链接，重复内容移除旧条目后插到顶部，超量时丢弃最旧。
    @discardableResult
    func add(_ text: String) -> ClipboardItem {
        insert(ClipboardItem(id: UUID(), kind: Self.detect(text), copiedAt: .now))
    }

    /// 收录一条图片数据。
    @discardableResult
    func addImage(data: Data, filename: String = "图片") -> ClipboardItem {
        insert(ClipboardItem(id: UUID(), kind: .image(data, filename: filename), copiedAt: .now))
    }

    /// 把某条历史复制回系统剪贴板（列表顺序保持不变），随即高亮该行。
    func reuse(_ item: ClipboardItem) {
        pasteboard.clearContents()
        switch item.kind {
        case .text(let text), .link(let text):
            pasteboard.setString(text, forType: .string)
        case .image(let data, _):
            pasteboard.setData(data, forType: .png)
        }
        // 吸收自己写入造成的 changeCount 变化，避免下一轮重复收录。
        changeCountLock.withLock { $0 = pasteboard.changeCount }
        highlightGeneration += 1
        let generation = highlightGeneration
        lastCopiedItemID = item.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard generation == highlightGeneration else { return }
            lastCopiedItemID = nil
        }
    }

    func clear() {
        items.removeAll()
        lastCopiedItemID = nil
        scheduleSave()
    }

    /// 从历史中移除某条。
    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        if lastCopiedItemID == item.id {
            lastCopiedItemID = nil
        }
        scheduleSave()
    }

    /// 锁定/取消锁定某条：锁定项始终排在最前，且不会被新复制内容替换或挤出上限。
    func toggleLock(_ item: ClipboardItem) {
        guard let current = items.first(where: { $0.id == item.id }) else { return }
        let locked = !current.isLocked
        if locked {
            // 锁定后只保留这一条同内容记录，避免锁定项与未锁定副本并存。
            items.removeAll { $0.id != current.id && $0.dedupKey == current.dedupKey }
        }
        guard let index = items.firstIndex(where: { $0.id == current.id }) else { return }
        items[index] = ClipboardItem(
            id: current.id,
            kind: current.kind,
            copiedAt: current.copiedAt,
            isLocked: locked
        )
        sortItems()
        trimExcess()
        scheduleSave()
    }

    /// 判定文本类型：http/https 链接归为链接（去除首尾空白后再收录，保证 URL 可直接打开），
    /// 其余归为文本。
    static func detect(_ text: String) -> ClipboardItem.Kind {
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: candidate),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            return .link(candidate)
        }
        return .text(candidate)
    }

    private func insert(_ item: ClipboardItem) -> ClipboardItem {
        // 锁定项不被同内容的新复制替换，保持原条目与锁定状态。
        if let locked = items.first(where: { $0.isLocked && $0.dedupKey == item.dedupKey }) {
            return locked
        }
        items.removeAll { !$0.isLocked && $0.dedupKey == item.dedupKey }
        items.append(item)
        sortItems()
        trimExcess()
        scheduleSave()
        return item
    }

    /// 锁定项在前；同组内按复制时间从新到旧。
    private func sortItems() {
        items = Self.ordered(items)
    }

    private static func ordered(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.sorted {
            if $0.isLocked != $1.isLocked { return $0.isLocked }
            return $0.copiedAt > $1.copiedAt
        }
    }

    /// 超量时优先淘汰最旧的未锁定项；全部锁定则不再挤出。
    private func trimExcess() {
        while items.count > Self.maxItems,
              let index = items.lastIndex(where: { !$0.isLocked }) {
            items.remove(at: index)
        }
    }

    /// 「此刻」页剪贴板标题区的激活按钮：请求展开页切换到剪贴板标签。
    func requestClipboardTab() {
        expansionRequest?.request(.clipboard)
    }

    /// 剪贴板里是图片文件 URL 时读出其数据；非图片文件一律不收录，避免把文件路径当文本。
    private func readImageFileURL() -> (data: Data, filename: String)? {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        for url in urls where Self.imageFileExtensions.contains(url.pathExtension.lowercased()) {
            if let data = try? Data(contentsOf: url) {
                return (data, url.lastPathComponent)
            }
        }
        return nil
    }

    private static let imageFileExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tiff", "bmp", "heic", "webp",
    ]

    // MARK: - 持久化

    /// 历史存档路径：Application Support/PocketNotch/clipboard-history.json。
    private static func archiveURL() -> URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("PocketNotch/clipboard-history.json")
    }

    /// 变更后 0.4s 内合并写入，避免频繁复制时反复落盘。
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            self.persist(self.items)
        }
    }

    private func persist(_ items: [ClipboardItem]) {
        let snapshot = items.map {
            PersistedClipboardItem(
                id: $0.id,
                kind: PersistedClipboardItem.Kind($0.kind),
                copiedAt: $0.copiedAt,
                isLocked: $0.isLocked
            )
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: Self.archiveURL(), options: .atomic)
    }

    /// 启动时恢复历史；文件缺失或损坏时回退为空列表，并裁剪到上限。
    private static func loadPersisted() -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: archiveURL()),
              let snapshot = try? JSONDecoder().decode([PersistedClipboardItem].self, from: data)
        else { return [] }
        let prefix = Array(snapshot.prefix(maxItems))
        return ordered(prefix.map { item in
            ClipboardItem(
                id: item.id,
                kind: .init(item.kind),
                copiedAt: item.copiedAt,
                isLocked: item.isLocked ?? false
            )
        })
    }
}

/// 剪贴板条目的类型。
enum ClipboardItemType {
    case text
    case link
    case image
}

/// 一条剪贴板历史记录：文本/链接保留原文，图片保留像素数据用于回写剪贴板与去重。
struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    let kind: Kind
    let copiedAt: Date
    let isLocked: Bool

    enum Kind: Equatable {
        case text(String)
        case link(String)
        case image(Data, filename: String)

        var type: ClipboardItemType {
            switch self {
            case .text: return .text
            case .link: return .link
            case .image: return .image
            }
        }
    }

    init(
        id: UUID = UUID(),
        kind: Kind,
        copiedAt: Date = .now,
        isLocked: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.copiedAt = copiedAt
        self.isLocked = isLocked
    }

    /// 单行展示文本：文本/链接为原文，图片为文件名。
    var text: String {
        switch kind {
        case .text(let text), .link(let text): return text
        case .image(_, let filename): return filename
        }
    }

    /// 去重键：文本/链接用原文，图片用像素数据。
    var dedupKey: String {
        switch kind {
        case .text(let text), .link(let text): return "text:" + text
        case .image(let data, _): return "image:" + data.base64EncodedString()
        }
    }
}

/// 剪贴板历史的持久化 DTO：与 `ClipboardItem` 一一对应，便于 Codable 归档。
fileprivate struct PersistedClipboardItem: Codable {
    let id: UUID
    let kind: Kind
    let copiedAt: Date
    /// 旧存档没有该字段；nil 视为未锁定。
    let isLocked: Bool?

    enum Kind: Codable {
        case text(String)
        case link(String)
        case image(image: Data, filename: String)

        private enum CodingKeys: String, CodingKey {
            case type, text, url, image, filename
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "text":
                self = .text(try container.decode(String.self, forKey: .text))
            case "link":
                self = .link(try container.decode(String.self, forKey: .url))
            case "image":
                self = .image(
                    image: try container.decode(Data.self, forKey: .image),
                    filename: try container.decode(String.self, forKey: .filename)
                )
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "未知剪贴板类型"
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .link(let url):
                try container.encode("link", forKey: .type)
                try container.encode(url, forKey: .url)
            case .image(let image, let filename):
                try container.encode("image", forKey: .type)
                try container.encode(image, forKey: .image)
                try container.encode(filename, forKey: .filename)
            }
        }
    }
}

extension ClipboardItem.Kind {
    /// 由持久化 DTO 还原为运行时的剪贴板类型。
    fileprivate init(_ persisted: PersistedClipboardItem.Kind) {
        switch persisted {
        case .text(let text): self = .text(text)
        case .link(let url): self = .link(url)
        case .image(let image, let filename): self = .image(image, filename: filename)
        }
    }
}

extension PersistedClipboardItem.Kind {
    /// 转为运行时剪贴板类型的快照。
    fileprivate init(_ kind: ClipboardItem.Kind) {
        switch kind {
        case .text(let text): self = .text(text)
        case .link(let url): self = .link(url)
        case .image(let image, let filename): self = .image(image: image, filename: filename)
        }
    }
}