import Foundation
import Observation

/// 下一轮展开优先切换标签的请求中心。
///
/// 模块（如剪贴板）在收到新内容时调用 `request(_:)`，Core 在展开开始时消费一次
/// 并把展开页切到对应标签；请求带过期时间，避免陈旧内容长期占用默认标签。
/// 依赖关系保持单向：Feature 模块 → PocketNotchCore，Core 不感知具体模块。
@MainActor
@Observable
public final class ExpandedTabRequestController {
    /// 待消费的标签请求；`nil` 表示无请求。
    public private(set) var pendingTab: ExpandedIslandTab?

    /// 过期时长：请求只在短暂窗口内有效，超时后自动清除。
    public let expiryInterval: TimeInterval

    private var expiryTask: Task<Void, Never>?

    public init(
        pendingTab: ExpandedIslandTab? = nil,
        expiryInterval: TimeInterval = 5
    ) {
        self.pendingTab = pendingTab
        self.expiryInterval = expiryInterval
    }

    /// 记录一个待消费的标签请求，并重建过期计时。
    public func request(_ tab: ExpandedIslandTab) {
        pendingTab = tab
        restartExpiry()
    }

    /// 展开开始时消费请求：返回待打开的标签并清除，同时停掉过期计时。
    @discardableResult
    public func consume() -> ExpandedIslandTab? {
        expiryTask?.cancel()
        expiryTask = nil
        defer { pendingTab = nil }
        return pendingTab
    }

    /// 取消当前请求，直接离开 pending 状态。
    public func cancel() {
        expiryTask?.cancel()
        expiryTask = nil
        pendingTab = nil
    }

    private func restartExpiry() {
        expiryTask?.cancel()
        guard expiryInterval > 0 else { return }
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.nanoseconds(for: self?.expiryInterval ?? 0))
            guard !Task.isCancelled else { return }
            self?.pendingTab = nil
        }
        expiryTask = task
    }

    private static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        UInt64(min(max(interval, 0), Double(UInt64.max) / 1_000_000_000) * 1_000_000_000)
    }
}