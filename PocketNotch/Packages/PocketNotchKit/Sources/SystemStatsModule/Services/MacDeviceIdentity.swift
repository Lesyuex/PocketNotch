import AppKit
import Foundation
import PocketNotchCore
import IOKit

/// 机型、屏幕尺寸、芯片型号、macOS 版本、物理磁盘容量的静态身份信息：全部同步读取，
/// 机型/芯片/内存标签由 `system_profiler SPHardwareDataType` 异步补齐，不进入采样节拍。
public struct MacDeviceIdentity {
    /// 机型展示名，如 "MacBook Pro"；未拿到时 nil。
    public private(set) var modelName: String?
    /// 屏幕尺寸，如 "14″"；未拿到时 nil。
    public let screenSize: String?
    /// 芯片型号，如 "M5 Pro"（展示用简写）；未拿到时 nil。
    public private(set) var chipModel: String?
    /// 芯片型号全称，如 "Apple M5 Pro"（不简写）；未拿到时 nil。
    public private(set) var chipBrand: String?
    /// macOS 版本，如 "macOS 15.5"；无法解析时 nil。
    public let osVersion: String?
    /// 内存总量标签，如 "32 GB"；未拿到时 nil。
    public private(set) var physicalMemoryLabel: String?
    /// 物理磁盘容量（字节），如 "APPLE SSD AP0512Z" → 500277790720；未拿到时 nil。
    public let diskCapacityBytes: UInt64?

    public init() {
        screenSize = Self.currentScreenSizeLabel()
        chipModel = Self.chipDisplayName(Self.chipBrandString())
        chipBrand = Self.chipBrandString()
        osVersion = Self.currentOSVersionLabel()
        diskCapacityBytes = Self.currentDiskCapacityBytes()
    }

    /// 内存总量 GB 数值（从内存标签解析，如 "32 GB" → 32）；未拿到时 nil。
    public var totalGB: Double? {
        guard let label = physicalMemoryLabel else { return nil }
        let digits = label.prefix { $0.isNumber || $0 == "." }
        return Double(digits)
    }

    /// 磁盘容量展示名：按 Apple 营销档位就近取整，如 500.3 GB → "512 GB"、1 TB → "1 TB"、2 TB → "2 TB"。
    public var diskCapacityLabel: String? {
        guard let bytes = diskCapacityBytes, bytes > 0 else { return nil }
        let gb = Double(bytes) / 1_000_000_000
        let tiers: [Double] = [256, 512, 1024, 2048]
        guard let nearest = tiers.min(by: { abs($0 - gb) < abs($1 - gb) }) else { return nil }
        if nearest >= 1024 {
            return String(format: "%.0f TB", nearest / 1024)
        }
        return String(format: "%.0f GB", nearest)
    }

    /// 用 `system_profiler` 读到的硬件身份字段补齐机型/芯片/内存（异步，一次性）。nil 不覆盖已同步获取的值。
    mutating func apply(modelName: String?, chipModel: String?, physicalMemoryLabel: String?) {
        if let modelName, !modelName.isEmpty {
            self.modelName = modelName
        }
        if let chipModel {
            self.chipModel = Self.chipDisplayName(chipModel)
            self.chipBrand = chipModel
        }
        if let physicalMemoryLabel {
            self.physicalMemoryLabel = physicalMemoryLabel
        }
    }

    /// 主屏物理对角线（mm → inch，四舍五入为整数英寸），如 "14″"。
    private static func currentScreenSizeLabel() -> String? {
        let size = CGDisplayScreenSize(CGMainDisplayID())
        guard size.width > 0, size.height > 0 else { return nil }
        let diagonal = sqrt(size.width * size.width + size.height * size.height) / 25.4
        return "\(Int(diagonal.rounded()))″"
    }

    /// 当前 macOS 版本，如 "macOS 15.5"；patch 为 0 时省略。
    private static func currentOSVersionLabel() -> String? {
        let version = SystemVersionService.shared.currentVersion()
        let patch = version.patch > 0 ? ".\(version.patch)" : ""
        return "macOS \(version.major).\(version.minor)\(patch)"
    }

    /// 整块物理磁盘容量（字节）：遍历 IOKit IOMedia，取 Whole=true 且 Leaf=false 的整盘中最大者
/// （APFS 容器等也会被列为整盘，物理盘容量恒为最大，如 "APPLE SSD" 500GB 档）。
    private static func currentDiskCapacityBytes() -> UInt64? {
        let iteratorRef: UnsafeMutablePointer<io_iterator_t> = .allocate(capacity: 1)
        defer { iteratorRef.deallocate() }
        guard let match = IOServiceMatching("IOMedia") else { return nil }
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, iteratorRef) == KERN_SUCCESS else { return nil }
        let iterator = iteratorRef.pointee
        defer { IOObjectRelease(iterator) }

        var largest: UInt64 = 0
        var media = IOIteratorNext(iterator)
        while media != 0 {
            defer { IOObjectRelease(media); media = IOIteratorNext(iterator) }
            let whole = IORegistryEntryCreateCFProperty(media, "Whole" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber
            let leaf = IORegistryEntryCreateCFProperty(media, "Leaf" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber
            let size = IORegistryEntryCreateCFProperty(media, "Size" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber
            guard whole?.boolValue == true, leaf?.boolValue == false, let size else { continue }
            largest = max(largest, size.uint64Value)
        }
        return largest > 0 ? largest : nil
    }

    /// "Apple M5 Pro" → "M5 Pro"；非 Apple 前缀原样返回。
    private static func chipDisplayName(_ brand: String?) -> String? {
        guard let brand, !brand.isEmpty else { return nil }
        if brand.hasPrefix("Apple ") {
            return String(brand.dropFirst("Apple ".count))
        }
        return brand
    }

    /// 当前芯片型号全称，如 "Apple M5 Pro"。
    private static func chipBrandString() -> String? {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0)
        let value = String(cString: bytes).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}