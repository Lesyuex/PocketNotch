import Foundation
import Combine

/// 通知存储：保存已入队与已消费的通知（用于统计、去重历史）。
///
/// 与 `NotificationQueue` 的差异：Queue 只关注「当前在展示队列里的」，
/// Store 关注「已经发生过的」通知记录。
@MainActor
public final class NotificationStore: ObservableObject {
    @Published public private(set) var history: [PocketNotchNotification] = []

    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public func record(_ notification: PocketNotchNotification) {
        history.append(notification)
    }

    public func clear() {
        history.removeAll()
    }
}