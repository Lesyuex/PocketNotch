import XCTest
@testable import MediaModule

@MainActor
final class CoalescingAsyncTaskTests: XCTestCase {
    func testQueuedRequestsAreCoalescedIntoOneRun() async throws {
        let scheduler = CoalescingAsyncTask()
        var runCount = 0
        var latestValue = -1

        for value in 0..<10 {
            scheduler.schedule {
                runCount += 1
                latestValue = value
            }
        }

        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(runCount, 1)
        XCTAssertEqual(latestValue, 9)
    }

    func testRequestsDuringRunProduceOnlyOneTrailingRun() async throws {
        let scheduler = CoalescingAsyncTask()
        var runCount = 0

        scheduler.schedule {
            runCount += 1
            if runCount == 1 {
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
        try await Task.sleep(for: .milliseconds(10))

        for _ in 0..<10 {
            scheduler.schedule {
                runCount += 1
            }
        }

        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(runCount, 2)
    }

    func testCancelDropsTrailingRun() async throws {
        let scheduler = CoalescingAsyncTask()
        var runCount = 0

        scheduler.schedule {
            runCount += 1
            try? await Task.sleep(for: .milliseconds(40))
        }
        try await Task.sleep(for: .milliseconds(10))
        scheduler.schedule {
            runCount += 1
        }
        scheduler.cancel()

        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(runCount, 1)
    }
}
