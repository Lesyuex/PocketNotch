import Darwin
import Foundation
import IOKit

/// 系统运行状态采样契约，便于注入桩做测试。
public protocol SystemLoadProviding: AnyObject {
    /// 立即采样一次。CPU 为差值型指标，需要两次采样之间有时间跨度才产生有效值。
    func sample() -> SystemLoadSnapshot
}

/// 基于 Mach host API 与 IOKit 的系统负载采样。
///
/// CPU 使用率经 `HOST_CPU_LOAD_INFO` 读取全局负载 ticks，两次采样之间求差值。
/// GPU 使用率经 IOKit 公开 API 读取 `IOAccelerator` 的 `PerformanceStatistics.Device Utilization %`。
/// 任一环节不可用都优雅降级为 nil。
public final class SystemLoadService: SystemLoadProviding {
    private var previousCPUTicks: (busy: UInt64, total: UInt64)?
    /// CPU 温度读取器（AppleSMC 私有 API 隔离在其自身文件内）。
    private let temperatureReader: any SystemTemperatureProviding

    public init(temperatureReader: (any SystemTemperatureProviding)? = nil) {
        self.temperatureReader = temperatureReader ?? AppleSMCTemperatureReader()
    }

    public func sample() -> SystemLoadSnapshot {
        let disk = diskInfo()
        return SystemLoadSnapshot(
            cpuUsage: cpuUsage(),
            gpuUsage: gpuUsage(),
            memoryUsage: memoryUsage(),
            diskUsage: disk?.ratio,
            diskUsedBytes: disk?.usedBytes,
            diskTotalBytes: disk?.totalBytes,
            diskName: disk?.name,
            cpuTemperature: temperatureReader.cpuTemperatureCelsius(),
            gpuTemperature: temperatureReader.gpuTemperatureCelsius(),
            memoryPressure: memoryPressure()
        )
    }

    // MARK: - CPU

    /// 全局 CPU 使用率：两次调用之间计算 tick 差值；首次调用仅建立基线，返回 nil。
    /// 使用 `HOST_CPU_LOAD_INFO`（全局负载），不遍历每个核心——更简单更可靠。
    private func cpuUsage() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        )

        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle

        defer { previousCPUTicks = (busy, total) }
        guard let previous = previousCPUTicks, total > previous.total else { return nil }
        return min(max(Double(busy - previous.busy) / Double(total - previous.total), 0), 1)
    }

    // MARK: - GPU

    /// GPU 使用率：读取显卡驱动的 `PerformanceStatistics.Device Utilization %`。
    /// Apple Silicon 上该统计位于 `AppleARMIODevice`，Intel 上位于 `IOAccelerator`，
    /// 两个类逐一尝试。直接返回百分比，不需要差值计算。
    private func gpuUsage() -> Double? {
        for className in ["AppleARMIODevice", "IOAccelerator"] {
            if let usage = gpuDeviceUtilization(forClass: className) { return usage }
        }
        return nil
    }

    private func gpuDeviceUtilization(forClass className: String) -> Double? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(className),
            &iterator
        ) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let ref = IORegistryEntryCreateCFProperty(
                entry, "PerformanceStatistics" as CFString,
                kCFAllocatorDefault, 0
            ),
                let stats = ref.takeRetainedValue() as? [String: Any],
                let utilization = stats["Device Utilization %"] as? NSNumber
            else { continue }
            return min(max(utilization.doubleValue / 100.0, 0), 1)
        }
        return nil
    }

    // MARK: - 内存

    /// 内存压力（0...1）：内核 Jetsam 同源压力值——`kern.memorystatus_level`
    /// 为 0–100 的「充裕度」（100=充裕、0=严峻），压力 = 100 − 充裕度。
    /// sysctl 属未文档化私有接口，不可用或读值异常时优雅回退为已用占比。
    private func memoryPressure() -> Double? {
        var level = Int32(0)
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_level", &level, &size, nil, 0) == 0,
           size == MemoryLayout<Int32>.size {
            let pressure = (100 - Double(level)) / 100
            if pressure.isFinite {
                return min(max(pressure, 0), 1)
            }
        }
        return memoryUsage()
    }

    /// 已用内存占比：应用内存（internal - purgeable）+ 内核常驻 + 压缩内存，口径贴近活动监视器。
    private func memoryUsage() -> Double? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let hostPort = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, hostPort) }

        let result = withUnsafeMutablePointer(to: &stats) { statsPointer -> kern_return_t in
            let integerCapacity = MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
            return statsPointer.withMemoryRebound(to: integer_t.self, capacity: integerCapacity) { intPointer in
                host_statistics64(hostPort, HOST_VM_INFO64, host_info64_t(intPointer), &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        let appMemoryPages = UInt64(max(stats.internal_page_count - stats.purgeable_count, 0))
        let usedBytes = (appMemoryPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard totalBytes > 0 else { return nil }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }

    // MARK: - 磁盘

    private struct DiskInfo {
        let ratio: Double      // 0...1
        let usedBytes: UInt64
        let totalBytes: UInt64
        let name: String?
    }

    /// 根卷已用容量占比，可用空间采用「重要用途可用容量」口径（贴近 Finder 显示）。
    private func diskInfo() -> DiskInfo? {
        let rootURL = URL(fileURLWithPath: "/")
        guard let values = try? rootURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeNameKey,
        ]),
            let totalCapacity = values.volumeTotalCapacity,
            let availableCapacity = values.volumeAvailableCapacityForImportantUsage,
            totalCapacity > 0
        else { return nil }
        let total = UInt64(totalCapacity)
        let available = UInt64(max(0, availableCapacity))
        let used = total - available
        let ratio = min(max(Double(used) / Double(total), 0), 1)
        return DiskInfo(ratio: ratio, usedBytes: used, totalBytes: total, name: values.volumeName)
    }
}
