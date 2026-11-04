import Foundation

/// 一次性读取硬件品牌/型号信息（`system_profiler SPMemoryDataType SPStorageDataType -xml`）。
/// 首次调用耗时约 1 秒，由调用方异步触发并缓存，绝不进入采样节拍。
struct SystemInfoProfile {
    /// 内存条厂商名，如 "Micron"；拿不到时 nil。
    let memoryBrand: String?
    /// 内建磁盘型号，如 "APPLE SSD AP0512Z"；拿不到时 nil。
    let diskModel: String?
    /// GPU 型号，如 "Apple M5"；拿不到时 nil。
    let gpuModel: String?
    /// GPU 厂商，如 "Apple"；拿不到时 nil。
    let gpuVendor: String?
    /// 机型展示名，如 "MacBook Pro"；拿不到时 nil。
    let modelName: String?
    /// 芯片型号，如 "Apple M5 Pro"；拿不到时 nil。
    let chipModel: String?
    /// 内存总量标签，如 "32 GB"；拿不到时 nil。
    let physicalMemoryLabel: String?
}

final class SystemInfoService {
    func fetch() async -> SystemInfoProfile {
        guard let data = await run() else {
            return SystemInfoProfile(
                memoryBrand: nil,
                diskModel: nil,
                gpuModel: nil,
                gpuVendor: nil,
                modelName: nil,
                chipModel: nil,
                physicalMemoryLabel: nil
            )
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let top = plist as? [[String: Any]] else {
            return SystemInfoProfile(
                memoryBrand: nil,
                diskModel: nil,
                gpuModel: nil,
                gpuVendor: nil,
                modelName: nil,
                chipModel: nil,
                physicalMemoryLabel: nil
            )
        }

        let memoryBrand = top.first {
            ($0["_dataType"] as? String) == "SPMemoryDataType"
        }.flatMap { memoryManufacturer(in: $0) }

        let diskModel = top.first {
            ($0["_dataType"] as? String) == "SPStorageDataType"
        }.flatMap { diskModel(in: $0) }

        let gpuEntry = top.first {
            ($0["_dataType"] as? String) == "SPDisplaysDataType"
        }

        let hardwareEntry = top.first {
            ($0["_dataType"] as? String) == "SPHardwareDataType"
        }
        let hardwareItem = (hardwareEntry?["_items"] as? [[String: Any]])?.first

        return SystemInfoProfile(
            memoryBrand: memoryBrand,
            diskModel: diskModel,
            gpuModel: gpuEntry.flatMap { gpuModel(in: $0) },
            gpuVendor: gpuEntry.flatMap { gpuVendor(in: $0) },
            modelName: hardwareItem.flatMap {
                ($0["machine_name"] as? String) ?? ($0["model_name"] as? String)
            },
            chipModel: hardwareItem?["chip_type"] as? String,
            physicalMemoryLabel: hardwareItem?["physical_memory"] as? String
        )
    }

    /// 第一个内存条的厂商名。
    private func memoryManufacturer(in entry: [String: Any]) -> String? {
        guard let dimms = entry["_items"] as? [[String: Any]] else { return nil }
        for dimm in dimms {
            guard let manufacturer = dimm["dimm_manufacturer"] as? String,
                  !manufacturer.isEmpty else { continue }
            return manufacturer
        }
        return nil
    }

    /// 内建物理盘的型号名（优先 is_internal_disk=yes，其次跳过 Disk Image）。
    private func diskModel(in entry: [String: Any]) -> String? {
        guard let volumes = entry["_items"] as? [[String: Any]] else { return nil }

        if let internalDrive = volumes.first(where: {
            ($0["physical_drive"] as? [String: Any])?["is_internal_disk"] as? String == "yes"
        }) {
            return physicalDeviceName(in: internalDrive)
        }

        for volume in volumes {
            guard let drive = volume["physical_drive"] as? [String: Any],
                  drive["media_name"] as? String != "Disk Image" else { continue }
            return drive["device_name"] as? String
        }
        return nil
    }

    private func physicalDeviceName(in volume: [String: Any]) -> String? {
        guard let drive = volume["physical_drive"] as? [String: Any] else { return nil }
        return drive["device_name"] as? String
    }

    /// 首个 GPU 的型号名（优先 sppci_model，回退显示名 _name）。
    private func gpuModel(in entry: [String: Any]) -> String? {
        guard let items = entry["_items"] as? [[String: Any]],
              let gpu = items.first else { return nil }
        if let model = gpu["sppci_model"] as? String, !model.isEmpty {
            return model
        }
        return gpu["_name"] as? String
    }

    /// 首个 GPU 的厂商名（如 "sppci_vendor_Apple" → "Apple"）。
    private func gpuVendor(in entry: [String: Any]) -> String? {
        guard let items = entry["_items"] as? [[String: Any]],
              let gpu = items.first,
              let vendor = gpu["spdisplays_vendor"] as? String,
              !vendor.isEmpty else { return nil }
        return vendor.hasPrefix("sppci_vendor_") ? String(vendor.dropFirst("sppci_vendor_".count)) : vendor
    }

    private func run() async -> Data? {
        await withCheckedContinuation { continuation in
            let process = Process()
            // system_profiler 位于 /usr/sbin，需要显式全路径绑定。
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPMemoryDataType", "SPStorageDataType", "SPDisplaysDataType", "SPHardwareDataType", "-xml", "-detailLevel", "basic"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: data)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}