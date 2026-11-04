import Foundation

struct AudioOutputVolumeSnapshot: Equatable, Sendable {
    let volume: Float
    let isMuted: Bool
    let deviceName: String
    let deviceSymbolName: String
    let isBuiltIn: Bool

    init(
        volume: Float,
        isMuted: Bool,
        deviceName: String,
        deviceSymbolName: String,
        isBuiltIn: Bool = false
    ) {
        self.volume = volume
        self.isMuted = isMuted
        self.deviceName = deviceName
        self.deviceSymbolName = deviceSymbolName
        self.isBuiltIn = isBuiltIn
    }

    var displayedPercentage: Int {
        guard !isMuted else { return 0 }
        return Int((min(max(volume, 0), 1) * 100).rounded())
    }

    /// 音量调节提示使用音量语义图标，而不是当前输出设备的外形图标。
    var volumeSymbolName: String {
        switch displayedPercentage {
        case 0:
            return "speaker.slash.fill"
        case 1...33:
            return "speaker.wave.1.fill"
        case 34...66:
            return "speaker.wave.2.fill"
        default:
            return "speaker.wave.3.fill"
        }
    }
}

struct AudioOutputDeviceSnapshot: Equatable, Sendable {
    static let airPodsProRotationDuration: TimeInterval = 6
    static let airPodsHalfRotationDuration: TimeInterval = 2.7
    static let notificationDisplayDuration: TimeInterval = 2

    let deviceName: String
    let deviceSymbolName: String
    let notificationStatusText: String
    let isBluetoothHeadphones: Bool
    let isWiredHeadphones: Bool

    init(
        deviceName: String,
        deviceSymbolName: String,
        notificationStatusText: String = "已切换为播放设备",
        isBluetoothHeadphones: Bool? = nil,
        isWiredHeadphones: Bool = false
    ) {
        self.deviceName = deviceName
        self.deviceSymbolName = deviceSymbolName
        self.notificationStatusText = notificationStatusText
        self.isBluetoothHeadphones = isBluetoothHeadphones ?? Self.inferBluetoothHeadphones(
            deviceName: deviceName,
            deviceSymbolName: deviceSymbolName
        )
        self.isWiredHeadphones = isWiredHeadphones
    }

    var isHeadphones: Bool {
        isBluetoothHeadphones || isWiredHeadphones
    }

    private static func inferBluetoothHeadphones(
        deviceName: String,
        deviceSymbolName: String
    ) -> Bool {
        let normalizedName = deviceName.lowercased()
        let tokens = normalizedName
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        return deviceSymbolName.hasPrefix("airpods")
            || deviceSymbolName == "headphones"
            || normalizedName.contains("airpod")
            || normalizedName.contains("beats")
            || normalizedName.contains("buds")
            || normalizedName.contains("earbud")
            || normalizedName.contains("headphone")
            || normalizedName.contains("headset")
            || normalizedName.contains("earphone")
            || normalizedName.contains("耳机")
            || normalizedName.contains("耳塞")
            || tokens.contains(where: BluetoothHeadphoneBrands.contains)
    }

    var supportsBatteryStatus: Bool {
        isBluetoothHeadphones
    }

    var displayDuration: TimeInterval {
        AudioOutputDeviceSymbol.isAirPods(
            deviceName: deviceName,
            symbolName: deviceSymbolName
        ) ? Self.airPodsHalfRotationDuration : Self.notificationDisplayDuration
    }
}

struct AudioOutputDevice: Equatable, Identifiable, Sendable {
    let id: UInt32
    let deviceName: String
    let deviceSymbolName: String
    let isCurrent: Bool
    let isBluetoothHeadphones: Bool?

    init(
        id: UInt32,
        deviceName: String,
        deviceSymbolName: String,
        isCurrent: Bool,
        isBluetoothHeadphones: Bool? = nil
    ) {
        self.id = id
        self.deviceName = deviceName
        self.deviceSymbolName = deviceSymbolName
        self.isCurrent = isCurrent
        self.isBluetoothHeadphones = isBluetoothHeadphones
    }

    var snapshot: AudioOutputDeviceSnapshot {
        AudioOutputDeviceSnapshot(
            deviceName: deviceName,
            deviceSymbolName: deviceSymbolName,
            isBluetoothHeadphones: isBluetoothHeadphones
        )
    }
}

struct ConnectedHeadphonesSnapshot: Equatable, Sendable {
    let deviceName: String
    let deviceSymbolName: String
    let batteryPercentage: Int?
}

/// 常见第三方蓝牙耳机品牌/型号词。设备名被这些 token 命中时视为耳机，用于在没有
/// CoreAudio 传输类型信息时推断是否为蓝牙耳机（仅作为兜底推断）。
private let BluetoothHeadphoneBrands: Set<String> = [
    "sony", "wf", "bose", "qc", "jbl", "beats", "skullcandy", "sennheiser",
    "jabra", "samsung", "galaxy", "huawei", "freebuds", "xiaomi", "redmi",
    "anker", "soundcore", "marshall", "razer", "oneplus", "nothing", "realme",
    "oppo", "enco", "vivo", "tws", "edifier", "plantronics", "voyager",
    "beyerdynamic", "shure", "klipsch", "jaybird", "philips", "moto", "meta"
]

enum AudioOutputVolumeCommand: Sendable {
    case increase(fineAdjustment: Bool)
    case decrease(fineAdjustment: Bool)
    case toggleMute
}
