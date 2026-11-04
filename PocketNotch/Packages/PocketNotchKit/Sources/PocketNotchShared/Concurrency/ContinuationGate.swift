import Foundation

package final class ContinuationGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    package init() {}

    package func resume(_ continuation: CheckedContinuation<Value, Never>, returning value: Value) {
        lock.lock()
        guard !hasResumed else {
            lock.unlock()
            return
        }
        hasResumed = true
        lock.unlock()
        continuation.resume(returning: value)
    }
}
