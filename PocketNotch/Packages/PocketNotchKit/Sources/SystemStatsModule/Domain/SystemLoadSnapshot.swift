import Foundation

/// 一次系统运行状态采样：四项使用率均为 0...1。
/// `nil` 表示该项暂无数据（GPU 通道不可用、CPU 尚无采样基线等），由 UI 以占位呈现。
public struct SystemLoadSnapshot: Equatable, Sendable {
    public let cpuUsage: Double?
    public let gpuUsage: Double?
    public let memoryUsage: Double?
    /// 内存压力（0...1）：内核 Jetsam 同源（kern.memorystatus_level 反转），无内核读数时回退到已用占比。
    public let memoryPressure: Double?
    public let diskUsage: Double?
    /// 磁盘已用字节数（根卷），用于卡片中显示"使用/总量"。
    public let diskUsedBytes: UInt64?
    /// 磁盘总字节数（根卷）。
    public let diskTotalBytes: UInt64?
    /// 根卷名称（如 "Macintosh HD"）。
    public let diskName: String?
    /// CPU 结温（摄氏度）；SMC 不可用时为 nil。
    public let cpuTemperature: Double?
    /// GPU 结温（摄氏度）；SMC 无 GPU 温度键的机型为 nil。
    public let gpuTemperature: Double?

    public init(
        cpuUsage: Double?,
        gpuUsage: Double?,
        memoryUsage: Double?,
        diskUsage: Double?,
        diskUsedBytes: UInt64? = nil,
        diskTotalBytes: UInt64? = nil,
        diskName: String? = nil,
        cpuTemperature: Double? = nil,
        gpuTemperature: Double? = nil,
        memoryPressure: Double? = nil
    ) {
        self.cpuUsage = cpuUsage
        self.gpuUsage = gpuUsage
        self.memoryUsage = memoryUsage
        self.diskUsage = diskUsage
        self.diskUsedBytes = diskUsedBytes
        self.diskTotalBytes = diskTotalBytes
        self.diskName = diskName
        self.cpuTemperature = cpuTemperature
        self.gpuTemperature = gpuTemperature
        self.memoryPressure = memoryPressure
    }

    /// 四项全部无数据（采样完全不可用）。
    public var isEmpty: Bool {
        cpuUsage == nil && gpuUsage == nil && memoryUsage == nil && diskUsage == nil
    }
}