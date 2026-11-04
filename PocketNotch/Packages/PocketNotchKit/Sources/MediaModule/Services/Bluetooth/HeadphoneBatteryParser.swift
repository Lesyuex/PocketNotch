import Foundation

/// 负责解析、归一化并匹配来自 IORegistry 与 system_profiler 的耳机电量数据。
enum HeadphoneBatteryParser {
    static func batteryPercentage(
        inSystemProfilerJSON data: Data,
        deviceName: String,
        deviceUID: String? = nil
    ) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var candidates: [BatteryCandidate] = []
        collectSystemProfilerCandidates(
            in: root,
            keyHint: nil,
            deviceName: deviceName,
            deviceUID: deviceUID,
            candidates: &candidates
        )
        return candidates
            .max(by: { lhs, rhs in lhs.matchScore < rhs.matchScore })?
            .percentage
    }

    private static func collectSystemProfilerCandidates(
        in value: Any,
        keyHint: String?,
        deviceName: String,
        deviceUID: String?,
        candidates: inout [BatteryCandidate]
    ) {
        if let dictionary = dictionary(from: value) {
            if let percentage = batteryPercentage(in: dictionary) {
                // 新版 system_profiler 直接把设备名作为字典键，不再提供 `_name` 字段。
                let productName = productName(in: dictionary) ?? keyHint
                let registryAddress = deviceAddress(in: dictionary) ?? keyHint
                let score = matchScore(
                    deviceName: deviceName,
                    deviceUID: deviceUID,
                    registryProductName: productName,
                    registryAddress: registryAddress
                )
                if score > 0 {
                    candidates.append(BatteryCandidate(percentage: percentage, matchScore: score))
                }
            }

            for (key, nestedValue) in dictionary {
                collectSystemProfilerCandidates(
                    in: nestedValue,
                    keyHint: key,
                    deviceName: deviceName,
                    deviceUID: deviceUID,
                    candidates: &candidates
                )
            }
        } else if let array = value as? [Any] {
            for nestedValue in array {
                collectSystemProfilerCandidates(
                    in: nestedValue,
                    keyHint: keyHint,
                    deviceName: deviceName,
                    deviceUID: deviceUID,
                    candidates: &candidates
                )
            }
        }
    }

    private static func dictionary(from value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] { return dictionary }
        if let dictionary = value as? NSDictionary { return dictionary as? [String: Any] }
        return nil
    }

    static func batteryPercentage(in properties: [String: Any]) -> Int? {
        for key in directBatteryKeys {
            if let value = property(named: key, in: properties),
               let percentage = percentage(from: value, key: key) {
                return percentage
            }
        }

        let earPercentages = earBatteryKeys.compactMap { key in
            property(named: key, in: properties).flatMap {
                percentage(from: $0, key: key)
            }
        }
        // 单圆环展示耳机组可用电量，取两耳较低值，避免高估剩余使用时间。
        return earPercentages.min()
    }

    static func productName(in properties: [String: Any]) -> String? {
        for key in productNameKeys {
            if let name = property(named: key, in: properties) as? String,
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return name
            }
        }
        return nil
    }


    static func deviceAddress(in properties: [String: Any]) -> String? {
        for key in deviceAddressKeys {
            if let address = property(named: key, in: properties) as? String,
               !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return address
            }
        }
        return nil
    }

    static func property(named targetKey: String, in properties: [String: Any]) -> Any? {
        property(named: normalizedPropertyKey(targetKey), in: properties, remainingDepth: 5)
    }

    private static func property(
        named normalizedTargetKey: String,
        in value: Any,
        remainingDepth: Int
    ) -> Any? {
        guard remainingDepth >= 0 else { return nil }

        let dictionary: [String: Any]?
        if let typedDictionary = value as? [String: Any] {
            dictionary = typedDictionary
        } else if let nsDictionary = value as? NSDictionary {
            dictionary = nsDictionary as? [String: Any]
        } else {
            dictionary = nil
        }

        if let dictionary {
            if let directMatch = dictionary.first(where: {
                normalizedPropertyKey($0.key) == normalizedTargetKey
            }) {
                return directMatch.value
            }
            for nestedValue in dictionary.values {
                if let match = property(
                    named: normalizedTargetKey,
                    in: nestedValue,
                    remainingDepth: remainingDepth - 1
                ) {
                    return match
                }
            }
        } else if let array = value as? [Any] {
            for nestedValue in array {
                if let match = property(
                    named: normalizedTargetKey,
                    in: nestedValue,
                    remainingDepth: remainingDepth - 1
                ) {
                    return match
                }
            }
        }

        return nil
    }

    private static func percentage(from value: Any, key: String) -> Int? {
        let numericValue: Double?
        switch value {
        // Foundation 桥接下 NSString/NSData 也可能被 `as NSNumber` 接住，具体类型必须先判断。
        case let string as String:
            let normalized = string
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.lowercased().hasPrefix("0x") {
                numericValue = UInt64(normalized.dropFirst(2), radix: 16).map { Double($0) }
            } else {
                numericValue = Double(normalized)
            }
        case let data as Data:
            numericValue = percentageValue(from: data)
        case let number as NSNumber:
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            numericValue = number.doubleValue
        default:
            numericValue = nil
        }

        guard var numericValue, numericValue.isFinite else { return nil }
        if normalizedPropertyKey(key).contains("level"), numericValue >= 0, numericValue <= 1 {
            numericValue *= 100
        }
        guard numericValue >= 0, numericValue <= 100 else { return nil }
        return Int(numericValue.rounded())
    }

    private static func percentageValue(from data: Data) -> Double? {
        guard !data.isEmpty, data.count <= MemoryLayout<UInt64>.size else { return nil }
        if data.count == 1 { return Double(data[data.startIndex]) }

        let bytes = Array(data)
        let littleEndian = bytes.enumerated().reduce(UInt64(0)) { result, item in
            result | (UInt64(item.element) << UInt64(item.offset * 8))
        }
        let bigEndian = bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return [littleEndian, bigEndian]
            .first(where: { $0 <= 100 })
            .map { Double($0) }
    }

    private static func normalizedPropertyKey(_ key: String) -> String {
        key
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    static func matchScore(
        deviceName: String,
        deviceUID: String?,
        registryProductName: String?,
        registryAddress: String?
    ) -> Int {
        if let deviceUID,
           let registryAddress,
           normalizedAddress(deviceUID).contains(normalizedAddress(registryAddress)),
           normalizedAddress(registryAddress).count >= 12 {
            return 120
        }

        guard let registryProductName else { return 0 }
        let device = normalized(deviceName)
        let product = normalized(registryProductName)
        guard !device.isEmpty, !product.isEmpty else { return 0 }

        if device == product { return 100 }
        if device.contains(product) || product.contains(device) { return 80 }

        let deviceTokens = Set(device.split(separator: " ").map(String.init))
        let productTokens = Set(product.split(separator: " ").map(String.init))
        let sharedTokens = deviceTokens.intersection(productTokens)
        guard sharedTokens.contains(where: headphoneIdentityTokens.contains) else { return 0 }
        return 50 + min(sharedTokens.count * 5, 20)
    }

    private static func normalizedAddress(_ value: String) -> String {
        value.lowercased().unicodeScalars
            .filter { CharacterSet(charactersIn: "0123456789abcdef").contains($0) }
            .map(String.init)
            .joined()
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " " }
            .reduce(into: "") { $0.append($1) }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    struct BatteryCandidate {
        let percentage: Int
        let matchScore: Int
    }

    // 只查询耳机相关的 Apple 服务，禁止遍历通用 IOHIDEventService；后者可能触发键鼠驱动同步取属性，
    // 在部分机器上会造成 WindowServer 输入事件短暂阻塞。
    static let serviceClasses = [
        "AppleDeviceManagementHIDEventService",
        "AppleHSBluetoothDevice"
    ]

    private static let directBatteryKeys = [
        "BatteryPercent",
        "BatteryPercentSingle",
        "BatteryPercentCombined",
        "BatteryPercentage",
        "BatteryLevel",
        "Battery",
        "device_batteryLevelMain",
        "device_batteryLevel",
        // 系统（蓝牙菜单 / 系统设置）显示的就是 combined 值；优先采用，保证与系统对齐。
        "device_batteryLevelCombined"
    ]

    private static let earBatteryKeys = [
        "BatteryPercentLeft",
        "BatteryPercentRight",
        "BatteryLevelLeft",
        "BatteryLevelRight",
        "LeftBatteryPercent",
        "RightBatteryPercent",
        "LeftBatteryLevel",
        "RightBatteryLevel",
        "device_batteryLevelLeft",
        "device_batteryLevelRight",
        "BatteryLeft",
        "BatteryRight",
        "LeftBattery",
        "RightBattery"
    ]

    private static let productNameKeys = [
        "Product",
        "ProductName",
        "DeviceName",
        "Name",
        "_name",
        "device_name",
        "device_title"
    ]


    private static let deviceAddressKeys = [
        "DeviceAddress",
        "BluetoothAddress",
        "Address",
        "device_address"
    ]

    static let registrySearchKeys = directBatteryKeys
        + earBatteryKeys
        + productNameKeys
        + deviceAddressKeys

    private static let headphoneIdentityTokens: Set<String> = [
        "airpods", "airpod", "beats", "buds", "earbuds", "headphones", "headphone", "headset",
        "earphones", "earphone", "sony", "wf", "bose", "qc", "jbl", "skullcandy", "sennheiser",
        "jabra", "galaxy", "freebuds", "soundcore", "anker", "razer", "shure", "beyerdynamic",
        "edifier", "plantronics", "enco", "tws", "oneplus", "xiaomi", "oppo", "vivo"
    ]
}
