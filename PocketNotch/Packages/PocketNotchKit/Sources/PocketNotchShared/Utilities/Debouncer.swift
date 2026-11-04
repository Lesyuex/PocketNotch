import Foundation

/// 事件驱动刷新的防抖器：合并高频触发（悬停/拖拽检测），降低空闲耗电。
public final class Debouncer {
    private let interval: TimeInterval
    private let queue: DispatchQueue
    private var workItem: DispatchWorkItem?

    public init(interval: TimeInterval, queue: DispatchQueue = .main) {
        self.interval = interval
        self.queue = queue
    }

    public func call(_ action: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: action)
        workItem = item
        queue.asyncAfter(deadline: .now() + interval, execute: item)
    }

    public func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}
