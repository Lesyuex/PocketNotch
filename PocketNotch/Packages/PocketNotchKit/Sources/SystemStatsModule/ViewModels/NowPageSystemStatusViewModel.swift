import Combine
import Foundation
import PocketNotchCore
import Observation

/// 「此刻」页系统状态区（CPU / GPU / RAM / SSD）的采样驱动。
///
/// 轮询由岛展开态触发：展开时 `startPolling`，收起时 `stopPolling`，
/// 遵守「空闲态不轮询」的耗电铁律。早期实现把轮询挂在模块 activate 上，
/// 而模块在启动时激活、退出时才停用，导致即使岛收起也保持每 2 秒一次
/// IOKit/磁盘/温度全量采样（可观的常驻开销）。
@Observable
@MainActor
public final class NowPageSystemStatusViewModel {
    /// 最近一次采样快照；页面出现后的首次采样前为 nil。
    public private(set) var snapshot: SystemLoadSnapshot?

    /// CPU 使用率历史（0...1，最多保留 30 点），供 sparkline 使用。
    /// 随采样 ViewModel/轮询任务一起销毁：展开态隐藏即销毁，下次展开重新从零累积。
    public private(set) var cpuUsageHistory: [Double] = []

    /// GPU 使用率历史（0...1，最多保留 30 点），供状态卡迷你曲线使用。
    public private(set) var gpuUsageHistory: [Double] = []

    /// 内存使用率历史（0...1，最多保留 30 点），供使用趋势曲线使用。
    public private(set) var memoryUsageHistory: [Double] = []

    /// 磁盘使用率历史（0...1，最多保留 30 点），供使用趋势曲线使用。
    public private(set) var diskUsageHistory: [Double] = []

    /// 内存条厂商名（system_profiler 异步读取，一次性缓存）；未拿到时保持 nil。
    public private(set) var memoryBrand: String?

    /// 健康分：由四项使用率 + 最高结温按权重扣分，钳制 0...100。卡 1 与卡 2 共享。
    public var healthScore: Int {
        guard let snapshot else { return 0 }
        let maxTemperature = max(snapshot.cpuTemperature ?? 0, snapshot.gpuTemperature ?? 0)
        let usagePenalty =
            (snapshot.cpuUsage ?? 0) * Self.cpuUsageWeight
            + (snapshot.gpuUsage ?? 0) * Self.gpuUsageWeight
            + (snapshot.memoryUsage ?? 0) * Self.memoryUsageWeight
            + (snapshot.diskUsage ?? 0) * Self.diskUsageWeight
        let temperaturePenalty = max(maxTemperature - Self.temperatureBaseline, 0) * Self.temperatureWeight
        let rawScore = 100 - usagePenalty - temperaturePenalty
        return max(0, min(100, Int(rawScore.rounded())))
    }

    /// 内建磁盘型号（与内存厂商同一次 system_profiler 调用读取）；未拿到时保持 nil。
    public private(set) var diskModel: String?

    /// GPU 型号（同一次 system_profiler 调用读取）；未拿到时保持 nil。
    public private(set) var gpuModel: String?

    /// GPU 厂商（同一次 system_profiler 调用读取）；未拿到时保持 nil。
    public private(set) var gpuVendor: String?

    /// 机型 / 屏幕尺寸 / 芯片型号的静态身份信息：尺寸同步就绪，机型/芯片异步补齐。
    public private(set) var macIdentity = MacDeviceIdentity()

    private let loadService: any SystemLoadProviding
    private let infoService = SystemInfoService()
    private let notchViewModel: NotchViewModel?
    private var hardwareLoadStarted = false
    private let refreshInterval: Duration
    private var expansionStateCancellable: AnyCancellable?
    var pollingTask: Task<Void, Never>?

    public init(
        loadService: any SystemLoadProviding = SystemLoadService(),
        refreshInterval: Duration = .seconds(2),
        notchViewModel: NotchViewModel? = nil
    ) {
        self.loadService = loadService
        self.refreshInterval = refreshInterval
        self.notchViewModel = notchViewModel
        // 不自动启动轮询：采样只跟随岛展开态（见 observeExpansionState），
        // 避免「模块在启动时激活、退出时才停用」导致收起态也保持常驻采样。
        observeExpansionState()
    }

    public func startPolling() {
        guard pollingTask == nil else { return }
        loadHardwareIdentityIfNeeded()
        // weak self：轮询期间不持有强引用，ViewModel 释放后任务在下一轮自行退出；
        // deinit 是非隔离上下文，无法在此取消任务，故以自终止代替 deinit 清理。
        pollingTask = Task { [weak self, refreshInterval] in
            while !Task.isCancelled {
                self?.refreshOnce()
                guard self != nil else { return }
                do {
                    try await Task.sleep(for: refreshInterval)
                } catch {
                    return
                }
            }
        }
    }

    /// 首次展开时异步读取硬件身份并缓存，后续展开不再重复调用 system_profiler。
    private func loadHardwareIdentityIfNeeded() {
        guard !hardwareLoadStarted else { return }
        hardwareLoadStarted = true
        Task { [weak self] in
            let profile = await self?.infoService.fetch()
            self?.memoryBrand = profile?.memoryBrand
            self?.diskModel = profile?.diskModel
            self?.gpuModel = profile?.gpuModel
            self?.gpuVendor = profile?.gpuVendor
            self?.macIdentity.apply(modelName: profile?.modelName, chipModel: profile?.chipModel, physicalMemoryLabel: profile?.physicalMemoryLabel)
        }
    }

    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        // 展开态隐藏即销毁采样上下文：曲线历史与瞬时快照一并重置，
        // 下次展开从零开始累积，与「隐藏销毁组件+定时任务」的资源策略一致。
        cpuUsageHistory.removeAll()
        gpuUsageHistory.removeAll()
        memoryUsageHistory.removeAll()
        diskUsageHistory.removeAll()
        snapshot = nil
    }

    /// 采样只跟随岛展开态：展开即采，收起即停（守耗电铁律）。
    /// `notchViewModel` 缺省时（测试/独立构造）不自动轮询，
    /// 由调用方显式驱动 `startPolling`/`stopPolling`。
    private func observeExpansionState() {
        expansionStateCancellable = notchViewModel?.isExpandedPublisher
            .removeDuplicates()
            .sink { [weak self] isExpanded in
                guard let self else { return }
                if isExpanded {
                    self.startPolling()
                } else {
                    self.stopPolling()
                }
            }
    }

    /// 立即采样一次；公开以便测试与诊断。
    public func refreshOnce() {
        let newSnapshot = loadService.sample()
        snapshot = newSnapshot
        record(newSnapshot.cpuUsage, into: &cpuUsageHistory)
        record(newSnapshot.gpuUsage, into: &gpuUsageHistory)
        record(newSnapshot.memoryUsage, into: &memoryUsageHistory)
        record(newSnapshot.diskUsage, into: &diskUsageHistory)
    }

    /// 把一次采样值追加进历史（钳制到 0...1），超出窗口丢弃最旧的采样。
    private func record(_ value: Double?, into history: inout [Double]) {
        guard let value else { return }
        history.append(min(max(value, 0), 1))
        if history.count > Self.historyCapacity {
            history.removeFirst(history.count - Self.historyCapacity)
        }
    }

    /// 曲线历史最大采样点数。
    static let historyCapacity = 30

    // 健康分权重
    private static let cpuUsageWeight: Double = 30
    private static let gpuUsageWeight: Double = 15
    private static let memoryUsageWeight: Double = 25
    private static let diskUsageWeight: Double = 10
    private static let temperatureBaseline: Double = 50
    private static let temperatureWeight: Double = 0.8
}