import Foundation
import IOKit

/// 从 IORegistry 读取蓝牙耳机上报的电量。仅在连接或播放开始时按事件读取，避免定时扫描系统注册表。
struct HeadphoneBatteryReader: Sendable {
    func percentage(for deviceName: String, deviceUID: String? = nil) -> Int? {
        var candidates: [HeadphoneBatteryParser.BatteryCandidate] = []

        for serviceClass in HeadphoneBatteryParser.serviceClasses {
            guard let matching = IOServiceMatching(serviceClass) else { continue }
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(iterator) }

            while true {
                let service = IOIteratorNext(iterator)
                guard service != 0 else { break }
                defer { IOObjectRelease(service) }

                guard let properties = expandedProperties(for: service),
                      let percentage = HeadphoneBatteryParser.batteryPercentage(in: properties) else { continue }

                let productName = HeadphoneBatteryParser.productName(in: properties) ?? registryName(for: service)
                let registryAddress = HeadphoneBatteryParser.deviceAddress(in: properties)
                let score = HeadphoneBatteryParser.matchScore(
                    deviceName: deviceName,
                    deviceUID: deviceUID,
                    registryProductName: productName,
                    registryAddress: registryAddress
                )
                guard score > 0 else { continue }

                candidates.append(HeadphoneBatteryParser.BatteryCandidate(percentage: percentage, matchScore: score))
            }
        }

        if let percentage = candidates
            .max(by: { lhs, rhs in lhs.matchScore < rhs.matchScore })?
            .percentage {
            return percentage
        }

        // 较新的 macOS/部分 AirPods 固件不会再把电量挂到上述 HID 服务上，
        // 但“系统信息”的蓝牙报告仍能拿到 Apple 自己维护的连接设备电量。
        return systemProfilerPercentage(for: deviceName, deviceUID: deviceUID)
    }

    private func systemProfilerPercentage(for deviceName: String, deviceUID: String?) -> Int? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "mini"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return HeadphoneBatteryParser.batteryPercentage(
            inSystemProfilerJSON: data,
            deviceName: deviceName,
            deviceUID: deviceUID
        )
    }

    static func batteryPercentage(
        inSystemProfilerJSON data: Data,
        deviceName: String,
        deviceUID: String? = nil
    ) -> Int? {
        HeadphoneBatteryParser.batteryPercentage(
            inSystemProfilerJSON: data,
            deviceName: deviceName,
            deviceUID: deviceUID
        )
    }

    private func properties(for service: io_registry_entry_t) -> [String: Any]? {
        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        ) == KERN_SUCCESS,
        let properties = unmanagedProperties?.takeRetainedValue() else {
            return nil
        }
        return properties as NSDictionary as? [String: Any]
    }


    /// AirPods 的电量和产品名在不同 macOS/固件版本中可能分别挂在 HID 节点及其父节点。
    /// 先取当前节点完整属性，再只沿父链补齐已知键，避免遍历通用 HID 子树。
    private func expandedProperties(for service: io_registry_entry_t) -> [String: Any]? {
        guard var properties = properties(for: service) else { return nil }

        for key in HeadphoneBatteryParser.registrySearchKeys where HeadphoneBatteryParser.property(named: key, in: properties) == nil {
            if let value = parentProperty(named: key, for: service) {
                properties[key] = value
            }
        }
        return properties
    }

    private func parentProperty(named key: String, for service: io_registry_entry_t) -> Any? {
        guard let value = IORegistryEntrySearchCFProperty(
            service,
            kIOServicePlane,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        ) else {
            return nil
        }
        return value
    }

    private func registryName(for service: io_registry_entry_t) -> String? {
        var name = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(service, &name) == KERN_SUCCESS else { return nil }
        return String(cString: name)
    }

    static func batteryPercentage(in properties: [String: Any]) -> Int? {
        HeadphoneBatteryParser.batteryPercentage(in: properties)
    }
}
