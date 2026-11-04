import Foundation

/// 接收拖入项并写入 ShelfStore（后续对接 NSItemProvider）。
@MainActor
public final class ShelfDropReceiver {
    private let store: ShelfStore

    public init(store: ShelfStore) {
        self.store = store
    }

    public func receive(urls: [URL]) {
        urls.forEach { store.add($0) }
    }
}
