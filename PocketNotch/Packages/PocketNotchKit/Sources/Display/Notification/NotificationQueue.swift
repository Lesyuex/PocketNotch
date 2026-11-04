import Foundation
import Combine

/// 通知队列：先进先出，管理通知的生命周期（创建 → 展示 → 过期）。
///
/// 设计文档第十、十一章：
/// - 通知进入队列，展示一段时间后自动结束。
/// - 通知结束只是移除展示项，绝不改变 Agent / Session 的真实状态。
@MainActor
public final class NotificationQueue: ObservableObject {
    @Published public private(set) var activeNotifications: [PocketNotchNotification] = []
    @Published public private(set) var current: PocketNotchNotification?

    private let now: () -> Date
    private var expiryTasks: [UUID: Task<Void, Never>] = [:]

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// 入队一条通知（需先通过去重）。返回是否真正入队。
    @discardableResult
    public func enqueue(_ notification: PocketNotchNotification) -> Bool {
        guard !activeNotifications.contains(where: { $0.id == notification.id }) else {
            return false
        }
        activeNotifications.append(notification)
        scheduleExpiry(notification)
        advanceIfNeeded()
        return true
    }

    /// 手动结束一条通知（如用户点击关闭）。
    public func dismiss(_ id: UUID) {
        expiryTasks.removeValue(forKey: id)?.cancel()
        activeNotifications.removeAll { $0.id == id }
        advanceIfNeeded()
    }

    /// 当前应展示的通知（队首）。
    public func peek() -> PocketNotchNotification? {
        activeNotifications.first
    }

    /// 清空队列（不改变任何业务状态）。
    public func clear() {
        expiryTasks.values.forEach { $0.cancel() }
        expiryTasks.removeAll()
        activeNotifications.removeAll()
        current = nil
    }

    // MARK: - Internals

    private func advanceIfNeeded() {
        current = activeNotifications.first
    }

    private func scheduleExpiry(_ notification: PocketNotchNotification) {
        let id = notification.id
        let delay = max(notification.duration, 0)
        expiryTasks[id] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            // 到期的通知直接从队列移除；不触碰任何 Agent / Session 状态。
            self.activeNotifications.removeAll { $0.id == id }
            self.expiryTasks.removeValue(forKey: id)
            self.advanceIfNeeded()
        }
    }
}