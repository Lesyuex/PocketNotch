import XCTest
import PocketNotchCore
@testable import SystemStatsModule

@MainActor
final class SystemLoadServiceTests: XCTestCase {
    /// 真实采样：RAM / 磁盘是即时读数，首次采样即应有有效值且落在 0...1；
    /// CPU / GPU 为差值型指标，第二次采样后也应产生合法值或保持 nil。
    func testSampleProducesBoundedRatios() throws {
        let service = SystemLoadService()

        _ = service.sample()
        // 给差值型指标一个采样跨度。
        Thread.sleep(forTimeInterval: 0.2)
        let snapshot = service.sample()

        let memoryUsage = try XCTUnwrap(snapshot.memoryUsage)
        XCTAssertTrue((0...1).contains(memoryUsage), "RAM 使用率越界：\(memoryUsage)")

        let diskUsage = try XCTUnwrap(snapshot.diskUsage)
        XCTAssertTrue((0...1).contains(diskUsage), "磁盘使用率越界：\(diskUsage)")

        if let cpuUsage = snapshot.cpuUsage {
            XCTAssertTrue((0...1).contains(cpuUsage), "CPU 使用率越界：\(cpuUsage)")
        }
        if let gpuUsage = snapshot.gpuUsage {
            XCTAssertTrue((0...1).contains(gpuUsage), "GPU 使用率越界：\(gpuUsage)")
        }
    }

    /// 采样完全失败时应得到空快照，UI 可据此整体占位。
    func testSnapshotIsEmptyWhenAllMetricsUnavailable() {
        let snapshot = SystemLoadSnapshot(cpuUsage: nil, gpuUsage: nil, memoryUsage: nil, diskUsage: nil)
        XCTAssertTrue(snapshot.isEmpty)

        let nonEmpty = SystemLoadSnapshot(cpuUsage: 0.5, gpuUsage: nil, memoryUsage: nil, diskUsage: nil)
        XCTAssertFalse(nonEmpty.isEmpty)
    }

    /// 轮询启动后应持续产生快照，stop 之后引用任务被清理。
    func testViewModelPollingStartAndStop() async throws {
        let service = StubSystemLoadProvider()
        let viewModel = NowPageSystemStatusViewModel(
            loadService: service,
            refreshInterval: .milliseconds(20)
        )

        viewModel.startPolling()
        try await waitForCondition { viewModel.snapshot != nil }

        viewModel.stopPolling()
        // @MainActor 测试类内可直接访问 internal 轮询任务（stop 后应为 nil）。
        XCTAssertNil(viewModel.pollingTask)
    }

    private func waitForCondition(
        timeout: TimeInterval = 2,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("等待条件超时")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class StubSystemLoadProvider: SystemLoadProviding {
    var callCount = 0

    func sample() -> SystemLoadSnapshot {
        callCount += 1
        return SystemLoadSnapshot(
            cpuUsage: 0.25,
            gpuUsage: nil,
            memoryUsage: 0.5,
            diskUsage: 0.75
        )
    }
}
