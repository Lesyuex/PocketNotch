import Foundation
import Observation

public struct ShelfItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL

    public init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
    }

    public var name: String { url.lastPathComponent }
}

/// 当前会话内的文件暂存列表。
@Observable
@MainActor
public final class ShelfStore {
    public private(set) var items: [ShelfItem] = []

    public init() {}

    @discardableResult
    public func add(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let normalizedURL = url.standardizedFileURL
        guard !items.contains(where: { $0.url.standardizedFileURL == normalizedURL }) else {
            return false
        }
        items.append(ShelfItem(url: normalizedURL))
        return true
    }

    @discardableResult
    public func add(contentsOf urls: [URL]) -> Int {
        urls.reduce(into: 0) { count, url in
            if add(url) {
                count += 1
            }
        }
    }

    public func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
    }

    public func remove(ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
    }

    public func clear() {
        items.removeAll()
    }
}
