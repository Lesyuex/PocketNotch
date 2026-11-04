/// Runs the first requested operation immediately, then coalesces requests that
/// arrive while it is running into at most one trailing operation.
@MainActor
final class CoalescingAsyncTask {
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var isRunning = false
    private var needsTrailingRun = false
    private var operation: (@MainActor () async -> Void)?

    func schedule(_ operation: @escaping @MainActor () async -> Void) {
        self.operation = operation
        if task != nil {
            if isRunning {
                needsTrailingRun = true
            }
            return
        }

        generation &+= 1
        let scheduledGeneration = generation
        task = Task { [weak self] in
            guard let self else { return }
            await self.run(generation: scheduledGeneration)
        }
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        isRunning = false
        needsTrailingRun = false
        operation = nil
    }

    private func run(generation scheduledGeneration: UInt64) async {
        guard generation == scheduledGeneration else { return }
        isRunning = true

        repeat {
            needsTrailingRun = false
            guard let operation else { break }
            self.operation = nil
            await operation()
            guard generation == scheduledGeneration, !Task.isCancelled else { return }
        } while needsTrailingRun

        isRunning = false
        task = nil
    }
}
