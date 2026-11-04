import Foundation
import IOBluetooth
import PocketNotchShared

/// 蓝牙外设建立连接时用于 compact 两侧区域临时展示的设备状态。
protocol BluetoothDeviceConnectionProviding: AnyObject {
    func startObserving(
        onDeviceConnected: @Sendable @escaping (ConnectedHeadphonesSnapshot) -> Void
    )
    func stopObserving()
    func batteryPercentage(for deviceName: String) async -> Int?
}

extension BluetoothDeviceConnectionProviding {
    func batteryPercentage(for deviceName: String) async -> Int? { nil }
}

/// 监听蓝牙基带连接，而不是音频输出路由。启动时已连接的设备只建立基线，之后的真实重连才通知 UI。
final class SystemBluetoothDeviceConnectionService: NSObject, BluetoothDeviceConnectionProviding,
    @unchecked Sendable
{
    /// 仅用于桥接「蓝牙连接」与紧随其后的「音频输出切换」两次事件，避免重复读取。
    /// 超过该时长后重新读取，保证每次展示都是当前电量而非上一次的旧值。
    private static let batteryCacheLifetime: TimeInterval = 5

    private struct CachedBattery {
        let percentage: Int
        let timestamp: Date
    }

    private let stateQueue = DispatchQueue(label: "com.pocketnotch.bluetooth-device-connection")
    private let stateQueueKey = DispatchSpecificKey<Void>()
    private let batteryQueue = DispatchQueue(label: "com.pocketnotch.bluetooth-device-battery", qos: .utility)
    private let batteryReader = HeadphoneBatteryReader()
    private let gattBatteryReader = HeadphoneGATTBatteryReader()

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var connectedAddresses: Set<String> = []
    private var connectedAddressesByName: [String: String] = [:]
    private var batteryReadGenerations: [String: UInt] = [:]
    private var batteryPercentagesByName: [String: CachedBattery] = [:]
    private var onDeviceConnected: (@Sendable (ConnectedHeadphonesSnapshot) -> Void)?
    private var isObserving = false

    override init() {
        super.init()
        stateQueue.setSpecific(key: stateQueueKey, value: ())
    }

    func startObserving(
        onDeviceConnected: @Sendable @escaping (ConnectedHeadphonesSnapshot) -> Void
    ) {
        stateQueue.async { [weak self] in
            guard let self, !self.isObserving else { return }
            self.isObserving = true
            self.onDeviceConnected = onDeviceConnected

            // IOBluetooth 会把每个 profile 的建立都视作连接回调；先记录当前连接，避免应用启动即弹出。
            for device in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
            where device.isConnected() {
                self.rememberConnected(device)
                if UInt32(device.deviceClassMajor) == UInt32(kBluetoothDeviceClassMajorAudio) {
                    self.cacheBattery(for: device)
                }
            }

            self.connectNotification = IOBluetoothDevice.register(
                forConnectNotifications: self,
                selector: #selector(self.bluetoothDeviceConnected(_:device:))
            )
        }
    }

    func stopObserving() {
        let cleanup = { [self] in
            guard isObserving else { return }
            connectNotification?.unregister()
            connectNotification = nil
            for notification in disconnectNotifications.values {
                notification.unregister()
            }
            disconnectNotifications.removeAll()
            connectedAddresses.removeAll()
            connectedAddressesByName.removeAll()
            batteryReadGenerations.removeAll()
            batteryPercentagesByName.removeAll()
            onDeviceConnected = nil
            isObserving = false
        }
        if DispatchQueue.getSpecific(key: stateQueueKey) != nil {
            cleanup()
        } else {
            stateQueue.sync(execute: cleanup)
        }
    }

    deinit {
        stopObserving()
    }

    func batteryPercentage(for deviceName: String) async -> Int? {
        await batteryPercentage(for: deviceName, maxCacheAge: Self.batteryCacheLifetime)
    }

    /// 忽略缓存强制重新读取，用于连接事件与启动预热，确保拿到当前电量而非旧值。
    private func freshBatteryPercentage(for deviceName: String) async -> Int? {
        await batteryPercentage(for: deviceName, maxCacheAge: 0)
    }

    private func batteryPercentage(for deviceName: String, maxCacheAge: TimeInterval) async -> Int? {
        let cacheKey = normalizedDeviceName(deviceName)
        let now = Date()
        let cachedState = stateQueue.sync {
            (batteryPercentagesByName[cacheKey], connectedAddressesByName[cacheKey])
        }
        if let cached = cachedState.0, now.timeIntervalSince(cached.timestamp) < maxCacheAge {
            return cached.percentage
        }

        let percentage: Int? = await withCheckedContinuation { continuation in
            batteryQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                let percentage = self.batteryReader.percentage(
                    for: deviceName,
                    deviceUID: cachedState.1
                )
                if let percentage {
                    self.storeBattery(percentage, forCacheKey: cacheKey)
                }
                continuation.resume(returning: percentage)
            }
        }
        if let percentage {
            return percentage
        }

        // IORegistry / system_profiler 只上报 Apple 设备电量；第三方耳机回退到与系统
        // 同一数据源（GATT Battery Service），保证与 Control Center 显示一致。
        let gattPercentage = await gattBatteryReader.percentage(for: deviceName)
        if let gattPercentage {
            storeBattery(gattPercentage, forCacheKey: cacheKey)
        }
        return gattPercentage
    }

    private func storeBattery(_ percentage: Int, forCacheKey cacheKey: String) {
        stateQueue.async { [weak self] in
            self?.batteryPercentagesByName[cacheKey] = CachedBattery(
                percentage: percentage,
                timestamp: Date()
            )
        }
    }

    @objc private func bluetoothDeviceConnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        stateQueue.async { [weak self] in
            guard let self, self.isObserving else { return }
            let address = self.normalizedAddress(of: device)
            guard !address.isEmpty, self.connectedAddresses.insert(address).inserted else { return }
            self.installDisconnectNotification(for: device, address: address)
            self.publishConnection(for: device, address: address)
        }
    }

    @objc private func bluetoothDeviceDisconnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            let address = self.normalizedAddress(of: device)
            self.connectedAddresses.remove(address)
            // 断开即丢弃该设备缓存的电量，避免重连后仍显示上一次会话的旧值。
            for name in self.connectedAddressesByName
                .filter({ $0.value == address })
                .map(\.key) {
                self.batteryPercentagesByName.removeValue(forKey: name)
            }
            self.connectedAddressesByName = self.connectedAddressesByName.filter {
                $0.value != address
            }
            self.batteryReadGenerations[address, default: 0] &+= 1
            self.disconnectNotifications.removeValue(forKey: address)?.unregister()
        }
    }

    private func rememberConnected(_ device: IOBluetoothDevice) {
        let address = normalizedAddress(of: device)
        guard !address.isEmpty else { return }
        connectedAddresses.insert(address)
        if let name = device.nameOrAddress, !name.isEmpty {
            connectedAddressesByName[normalizedDeviceName(name)] = address
        }
        installDisconnectNotification(for: device, address: address)
    }

    private func cacheBattery(for device: IOBluetoothDevice) {
        let deviceName = device.nameOrAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let deviceName, !deviceName.isEmpty else { return }
        Task.detached { [weak self] in
            _ = await self?.freshBatteryPercentage(for: deviceName)
        }
    }

    private func installDisconnectNotification(for device: IOBluetoothDevice, address: String) {
        guard disconnectNotifications[address] == nil else { return }
        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self,
            selector: #selector(bluetoothDeviceDisconnected(_:device:))
        )
    }

    private func publishConnection(for device: IOBluetoothDevice, address: String) {
        let deviceName = device.nameOrAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (deviceName?.isEmpty == false ? deviceName : nil) ?? "蓝牙设备"
        let snapshot = ConnectedHeadphonesSnapshot(
            deviceName: resolvedName,
            deviceSymbolName: BluetoothDeviceSymbol.name(
                deviceName: resolvedName,
                majorClass: UInt32(device.deviceClassMajor),
                minorClass: UInt32(device.deviceClassMinor)
            ),
            batteryPercentage: nil
        )
        PocketNotchLog.media.debug("Bluetooth device connected: \(resolvedName, privacy: .public)")
        onDeviceConnected?(snapshot)

        batteryReadGenerations[address, default: 0] &+= 1
        let generation = batteryReadGenerations[address, default: 0]
        Task.detached { [weak self] in
            guard let self else { return }
            // 连接事件即强制重新读取并预热电量缓存（含第三方 OPO/GATT 路径），让随后触发
            // 的音频输出切换通知能直接命中缓存并立即显示电量，同时避免沿用旧值。
            let percentage = await self.freshBatteryPercentage(for: resolvedName)
            guard let percentage else { return }
            self.stateQueue.async { [weak self] in
                guard let self,
                      self.isObserving,
                      self.connectedAddresses.contains(address),
                      self.batteryReadGenerations[address] == generation else { return }
                self.batteryPercentagesByName[self.normalizedDeviceName(resolvedName)] = CachedBattery(
                    percentage: percentage,
                    timestamp: Date()
                )
                self.onDeviceConnected?(
                    ConnectedHeadphonesSnapshot(
                        deviceName: resolvedName,
                        deviceSymbolName: snapshot.deviceSymbolName,
                        batteryPercentage: percentage
                    )
                )
            }
        }
    }

    private func normalizedAddress(of device: IOBluetoothDevice) -> String {
        (device.addressString ?? "")
            .lowercased()
            .filter(\.isHexDigit)
    }

    private func normalizedDeviceName(_ name: String) -> String {
        name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 按产品名称优先、蓝牙设备类别兜底，选择适合 compact 前导区域展示的 SF Symbol。
enum BluetoothDeviceSymbol {
    static func name(deviceName: String, majorClass: UInt32, minorClass: UInt32) -> String {
        let name = deviceName.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).lowercased()

        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") || name.contains("airpod") { return "airpods" }
        if name.contains("magic keyboard") || name.contains("keyboard") || name.contains("键盘") {
            return "keyboard.fill"
        }
        if name.contains("magic mouse") || name.contains("mouse") || name.contains("鼠标") {
            return "computermouse.fill"
        }
        if name.contains("magic trackpad") || name.contains("trackpad") || name.contains("触控板") {
            return "rectangle.and.hand.point.up.left.fill"
        }
        if name.contains("gamepad") || name.contains("controller") || name.contains("手柄") {
            return "gamecontroller.fill"
        }
        if name.contains("iphone") { return "iphone" }
        if name.contains("ipad") { return "ipad" }
        if name.contains("apple watch") || name.contains("watch") { return "applewatch" }
        if name.contains("beats") || name.contains("headphone") || name.contains("headset")
            || name.contains("buds") || name.contains("耳机") {
            return "headphones"
        }
        if name.contains("speaker") || name.contains("音箱") || name.contains("扬声器") {
            return "hifispeaker.fill"
        }

        switch majorClass {
        case UInt32(kBluetoothDeviceClassMajorAudio):
            // 音频大类同时涵盖耳机与音箱；用 minor 类别区分，避免蓝牙音箱被兜底成耳机。
            switch minorClass {
            case UInt32(kBluetoothDeviceClassMinorAudioLoudspeaker),
                 UInt32(kBluetoothDeviceClassMinorAudioVideoDisplayAndLoudspeaker),
                 UInt32(kBluetoothDeviceClassMinorAudioHiFi):
                return "hifispeaker.fill"
            default:
                return "headphones"
            }
        case UInt32(kBluetoothDeviceClassMajorPhone):
            return "iphone"
        case UInt32(kBluetoothDeviceClassMajorComputer):
            return "laptopcomputer"
        case UInt32(kBluetoothDeviceClassMajorPeripheral):
            let primary = minorClass & 0x30
            let secondary = minorClass & 0x0F
            if primary == 0x10 { return "keyboard.fill" }
            if primary == 0x20 { return "computermouse.fill" }
            if primary == 0x30 { return "keyboard.badge.ellipsis" }
            if secondary == 0x01 || secondary == 0x02 { return "gamecontroller.fill" }
            if secondary == 0x03 { return "av.remote.fill" }
            if secondary == 0x05 || secondary == 0x07 { return "pencil.tip" }
            return "sensor.tag.radiowaves.forward.fill"
        case UInt32(kBluetoothDeviceClassMajorImaging):
            return "camera.fill"
        case UInt32(kBluetoothDeviceClassMajorWearable):
            return "applewatch"
        case UInt32(kBluetoothDeviceClassMajorHealth):
            return "heart.fill"
        default:
            return "dot.radiowaves.left.and.right"
        }
    }
}
