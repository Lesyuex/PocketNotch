import CoreAudio

/// 将系统音频设备名称与传输类型映射为稳定的 SF Symbol，避免 UI 了解 CoreAudio 细节。
/// 设备名可被用户重命名，因此优先用不可改动的型号名匹配，设备名与传输类型逐级兜底。
enum AudioOutputDeviceSymbol {
    static func name(
        deviceName: String,
        transportType: UInt32,
        modelName: String? = nil
    ) -> String {
        let primary = modelName?.isEmpty == false ? modelName! : deviceName
        let device = deviceName.lowercased()

        if let symbol = airPodsSymbol(primary: primary, device: device) {
            return symbol
        }
        if isHeadphone(namedBy: primary) || isHeadphone(namedBy: device) {
            return "headphones"
        }
        if transportType == kAudioDeviceTransportTypeBuiltIn {
            return "macbook"
        }
        if let symbol = installedDeviceSymbol(namedBy: primary) ?? installedDeviceSymbol(namedBy: device) {
            return symbol
        }

        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return "macbook"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "display"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        default:
            return "hifispeaker.fill"
        }
    }

    private static func airPodsSymbol(primary: String, device: String) -> String? {
        let primaryName = primary.lowercased()
        let combined = "\(primaryName) \(device)"
        guard combined.contains("airpods") else { return nil }

        if combined.contains("airpods max") {
            return "airpods.max"
        }
        if combined.contains("airpods pro") {
            return isFirstGenerationAirPodsPro(combined)
                ? "airpods.pro.gen1"
                : "airpods.pro"
        }
        return isThirdGenerationAirPods(combined)
            ? "airpods.gen3"
            : "airpods"
    }

    private static func isHeadphone(namedBy text: String) -> Bool {
        let name = text.lowercased()
        return name.contains("beats")
            || name.contains("headphone")
            || name.contains("headset")
            || name.contains("buds")
            || name.contains("耳机")
    }

    private static func installedDeviceSymbol(namedBy text: String) -> String? {
        let name = text.lowercased()

        if name.contains("homepod mini") {
            return "homepodmini.fill"
        }
        if name.contains("homepod") {
            return "homepod.fill"
        }
        if name.contains("apple tv") {
            return "appletv.fill"
        }
        if name.contains("display")
            || name.contains("monitor")
            || name.contains("显示器")
            || name.contains("电视") {
            return "display"
        }
        if name.contains("speaker")
            || name.contains("扬声器")
            || name.contains("音箱") {
            return "hifispeaker.fill"
        }
        return nil
    }

    /// AirPods Pro 第 1 代：系统名称会带“（第 1 代）/（一代）/ 1st generation”后缀。
    private static func isFirstGenerationAirPodsPro(_ name: String) -> Bool {
        name.contains("第 1 代")
            || name.contains("一代")
            || name.contains("gen 1")
            || name.contains("gen1")
            || name.contains("1st generation")
    }

    private static func isThirdGenerationAirPods(_ name: String) -> Bool {
        name.contains("第 3 代")
            || name.contains("三代")
            || name.contains("gen 3")
            || name.contains("gen3")
            || name.contains("3rd generation")
    }

    static func isAirPods(deviceName: String, symbolName: String) -> Bool {
        let normalizedName = deviceName.lowercased()
        return normalizedName.contains("airpods")
            || normalizedName.contains("airpod")
            || symbolName.hasPrefix("airpods")
    }

    /// 有线耳机识别：内置耳机孔（MacBook 3.5mm）在内置总线，需按型号识别；
    /// USB/雷电等有线传输与 3.5mm 插孔传输（私有 FourCC 'hdpn'）靠名称或传输类型兜底。
    static func isWiredHeadphones(
        deviceName: String,
        transportType: UInt32,
        modelName: String? = nil
    ) -> Bool {
        if isBluetooth(transportType: transportType) {
            return false
        }
        let headphoneJackTransportType: UInt32 = 0x6864706E
        if transportType == headphoneJackTransportType {
            return true
        }
        if transportType == kAudioDeviceTransportTypeBuiltIn {
            return headphoneNamedText((modelName ?? "") + " " + deviceName)
        }
        let name = deviceName.lowercased()
        return name.contains("headset")
            || name.contains("headphone")
            || name.contains("earphone")
            || name.contains("earbud")
            || name.contains("buds")
            || name.contains("耳机")
            || name.contains("耳塞")
    }

    private static func headphoneNamedText(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("headset")
            || lowercased.contains("headphone")
            || lowercased.contains("earphone")
            || lowercased.contains("earbud")
            || lowercased.contains("buds")
            || lowercased.contains("耳机")
            || lowercased.contains("耳塞")
    }

    private static func isBluetooth(transportType: UInt32) -> Bool {
        transportType == kAudioDeviceTransportTypeBluetooth
            || transportType == kAudioDeviceTransportTypeBluetoothLE
    }
}
