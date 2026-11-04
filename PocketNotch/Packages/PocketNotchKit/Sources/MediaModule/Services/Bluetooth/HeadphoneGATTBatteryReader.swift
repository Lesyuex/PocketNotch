import CoreBluetooth
import Foundation

/// 通过 CoreBluetooth 读取已连接蓝牙耳机的电量。
///
/// IORegistry 与 system_profiler 只对 Apple 设备（AirPods/Beats）上报电量；第三方 TWS 耳机的
/// 真实电量常不走标准 Battery Service（0x2A19 可能恒为 0），而是放在 OPPO/OnePlus/Realme
/// 共用的私有「OPO 协议」服务（0000079A）里。读取优先级：
/// 1. OPO 协议电量查询（HELLO / REGISTER / Battery Query，电量帧 CAT=0x06 SUB=0x81）；
/// 2. 标准 GATT Battery Service 0x2A19（macOS bluetoothd 对通用耳机用的同一特征）兜底。
struct HeadphoneGATTBatteryReader: Sendable {
    func percentage(for deviceName: String) async -> Int? {
        let targetName = Self.normalized(deviceName)
        guard !targetName.isEmpty else { return nil }

        return await withCheckedContinuation { continuation in
            let session = Session(deviceName: targetName) { value in
                continuation.resume(returning: value)
            }
            session.start()
        }
    }

    /// 解析 OPO 协议电量响应帧。
    ///
    /// 布局（OPPO Enco Free3，实测 15 字节）：
    /// `AA LEN PAD PAD 06 81 SEQ ... <L-id> <L%> <R-id> <R%>`，左% = bytes[12]，右% = bytes[14]。
    /// 实测：`aa 0d 00 00 06 81 43 06 00 00 02 01 14 02 14` → 左 20%，右 20%。
    /// Nord Buds 系的 16 字节帧同一偏移也适用（bytes[15] 为盒%）。取两耳机中较小值展示。
    static func opoBatteryPercentage(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 15, bytes[0] == 0xAA, bytes[4] == 0x06, bytes[5] == 0x81 else {
            return nil
        }
        let candidates = [Int(bytes[12]), Int(bytes[14])].filter { 0...100 ~= $0 }
        return candidates.min()
    }

    /// 判断 GATT 外设名称是否对应目标音频设备名。分类匹配与 HeadphoneBatteryParser 保持一致。
    static func matches(deviceName: String, peripheralName: String?) -> Bool {
        guard let peripheralName else { return false }
        let target = normalized(deviceName)
        let peripheral = normalized(peripheralName)
        guard !target.isEmpty, !peripheral.isEmpty else { return false }

        if target == peripheral { return true }
        if target.contains(peripheral) || peripheral.contains(target) { return true }

        let targetTokens = target.split(separator: " ").map(String.init)
        let peripheralTokens = peripheral.split(separator: " ").map(String.init)
        let sharedTokens = Set(targetTokens).intersection(peripheralTokens)
        return sharedTokens.contains(where: headphoneIdentityTokens.contains)
    }

    static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " " }
            .reduce(into: "") { $0.append($1) }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static let headphoneIdentityTokens: Set<String> = [
        "airpods", "airpod", "beats", "buds", "earbuds", "headphones", "headphone", "headset",
        "earphones", "earphone", "sony", "wf", "bose", "qc", "jbl", "skullcandy", "sennheiser",
        "jabra", "galaxy", "freebuds", "soundcore", "anker", "razer", "shure", "beyerdynamic",
        "edifier", "plantronics", "enco", "tws", "oneplus", "xiaomi", "oppo", "vivo"
    ]

    fileprivate static let centralQueue = DispatchQueue(label: "com.pocketnotch.headphone-gatt-battery")
    fileprivate static let batteryServiceUUID = CBUUID(string: "0x180F")
    fileprivate static let batteryLevelUUID = CBUUID(string: "0x2A19")
    fileprivate static let opoServiceUUID = CBUUID(string: "0000079A-D102-11E1-9B23-00025B00A5A5")
    fileprivate static let opoWriteUUID = CBUUID(string: "0100079A-D102-11E1-9B23-00025B00A5A5")
    fileprivate static let opoNotifyUUID = CBUUID(string: "0200079A-D102-11E1-9B23-00025B00A5A5")
    fileprivate static let totalTimeout: TimeInterval = 20
    fileprivate static let opoFrameTimeout: TimeInterval = 8
}

/// 单次 GATT 读取会话。持有专属 central manager 并通过自引用保持存活，直到成功或超时。
private final class Session: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let targetName: String
    private let completion: (Int?) -> Void

    private var keepAlive: Session?
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var didInitiateConnection = false
    private var isFinished = false
    private var timeoutWorkItem: DispatchWorkItem?

    private var connectAttempts = 0
    private var pendingConnect: CBPeripheral?

    private var batteryService: CBService?
    private var batteryLevelCharacteristic: CBCharacteristic?
    private var opoWriteCharacteristic: CBCharacteristic?
    private var opoNotifyCharacteristic: CBCharacteristic?
    private var opoFrameWorkItem: DispatchWorkItem?

    init(deviceName: String, completion: @escaping (Int?) -> Void) {
        self.targetName = deviceName
        self.completion = completion
        super.init()
    }

    func start() {
        keepAlive = self
        scheduleTimeout()
        let central = CBCentralManager(delegate: self, queue: HeadphoneGATTBatteryReader.centralQueue)
        self.central = central
    }

    private func scheduleTimeout() {
        let workItem = DispatchWorkItem { [weak self] in
            self?.finish(nil)
        }
        timeoutWorkItem = workItem
        let queue = DispatchQueue.global(qos: .utility)
        queue.asyncAfter(deadline: .now() + HeadphoneGATTBatteryReader.totalTimeout, execute: workItem)
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !isFinished else { return }
        guard central.state == .poweredOn else {
            if central.state != .poweredOn {
                finish(nil)
            }
            return
        }

        let candidates = central.retrieveConnectedPeripherals(
            withServices: [HeadphoneGATTBatteryReader.batteryServiceUUID]
        )
        guard let target = candidates.first(where: {
            HeadphoneGATTBatteryReader.matches(
                deviceName: self.targetName,
                peripheralName: $0.name
            )
        }) else {
            finish(nil)
            return
        }

        peripheral = target
        target.delegate = self
        if target.state == .connected {
            discoverEverything(target)
        } else {
            connectTo(target)
        }
    }

    private func connectTo(_ target: CBPeripheral) {
        guard let central else { return }
        didInitiateConnection = true
        pendingConnect = target
        connectAttempts += 1
        central.connect(target, options: nil)
        scheduleConnectStallCheck(target)
    }

    /// macOS 上 connect() 偶发不触发 didConnect；超时后主动 cancel 并重试有限次数。
    private func scheduleConnectStallCheck(_ target: CBPeripheral) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let central = self.central, !self.isFinished,
                  self.pendingConnect === target, target.state != .connected else {
                return
            }
            if self.connectAttempts >= 3 {
                self.finish(nil)
                return
            }
            central.cancelPeripheralConnection(target)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, self.pendingConnect === target, !self.isFinished else { return }
                self.connectTo(target)
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3.5, execute: workItem)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard !isFinished else { return }
        pendingConnect = nil
        discoverEverything(peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        guard !isFinished else { return }
        if connectAttempts >= 3 {
            finish(nil)
        } else {
            connectTo(peripheral)
        }
    }

    // MARK: CBPeripheralDelegate

    private func discoverEverything(_ peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard !isFinished else { return }

        let services = peripheral.services ?? []
        batteryService = services.first {
            $0.uuid == HeadphoneGATTBatteryReader.batteryServiceUUID
        }
        if let opoService = services.first(where: {
            $0.uuid == HeadphoneGATTBatteryReader.opoServiceUUID
        }) {
            peripheral.discoverCharacteristics(nil, for: opoService)
        } else if let batteryService {
            peripheral.discoverCharacteristics(
                [HeadphoneGATTBatteryReader.batteryLevelUUID],
                for: batteryService
            )
        } else {
            finish(nil)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        guard !isFinished else { return }

        if service.uuid == HeadphoneGATTBatteryReader.opoServiceUUID {
            opoWriteCharacteristic = service.characteristics?.first {
                $0.uuid == HeadphoneGATTBatteryReader.opoWriteUUID
            }
            opoNotifyCharacteristic = service.characteristics?.first {
                $0.uuid == HeadphoneGATTBatteryReader.opoNotifyUUID
            }
            if let opoNotifyCharacteristic {
                peripheral.setNotifyValue(true, for: opoNotifyCharacteristic)
            }
            guard opoWriteCharacteristic != nil, opoNotifyCharacteristic != nil, !opoStarted else {
                if opoWriteCharacteristic == nil || opoNotifyCharacteristic == nil {
                    readStandardBattery()
                }
                return
            }
            runOPOHandshake()
        } else if service.uuid == HeadphoneGATTBatteryReader.batteryServiceUUID {
            batteryLevelCharacteristic = service.characteristics?.first {
                $0.uuid == HeadphoneGATTBatteryReader.batteryLevelUUID
            }
            if batteryLevelCharacteristic == nil {
                finish(nil)
                return
            }
            // 兜底路径：OPO 无效的普通耳机，发现到 0x2A19 后立即读。
            readStandardBattery()
        }
    }

    // MARK: OPO 协议

    private var opoStarted = false

    private func runOPOHandshake() {
        guard !opoStarted else { return }
        opoStarted = true

        scheduleOPOFrameTimeout()
        sendOPO([0xAA, 0x07, 0x00, 0x00, 0x00, 0x01, 0x23, 0x00, 0x00, 0x12], name: "hello")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.sendOPO(
                [0xAA, 0x0C, 0x00, 0x00, 0x00, 0x85, 0x41, 0x05, 0x00, 0x00, 0xB5, 0x50, 0xA0, 0x69],
                name: "register"
            )
        }
        // 询电量的 SUB 命令在不同型号上可能是 0x82 或 0x01，两条都发，取先返回的电量帧。
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.sendOPO([0xAA, 0x07, 0x00, 0x00, 0x06, 0x82, 0x43, 0x00, 0x00, 0x00], name: "query-82")
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.sendOPO([0xAA, 0x07, 0x00, 0x00, 0x06, 0x01, 0x43, 0x00, 0x00, 0x00], name: "query-01")
        }
    }

    private func scheduleOPOFrameTimeout() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isFinished else { return }
            self.readStandardBattery()
        }
        opoFrameWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + HeadphoneGATTBatteryReader.opoFrameTimeout,
            execute: workItem
        )
    }

    private func sendOPO(_ bytes: [UInt8], name: String) {
        guard !isFinished else { return }
        guard let peripheral, let characteristic = opoWriteCharacteristic else { return }
        peripheral.writeValue(Data(bytes), for: characteristic, type: .withoutResponse)
    }

    // MARK: 标准 Battery Service

    private func readStandardBattery() {
        guard !isFinished else { return }
        guard let peripheral else { return }
        if let batteryLevelCharacteristic {
            peripheral.readValue(for: batteryLevelCharacteristic)
            if batteryLevelCharacteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: batteryLevelCharacteristic)
            }
        } else if let batteryService {
            peripheral.discoverCharacteristics(
                [HeadphoneGATTBatteryReader.batteryLevelUUID],
                for: batteryService
            )
        } else {
            finish(nil)
        }
    }

    // MARK: 响应处理

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard !isFinished else { return }
        guard error == nil else { return }
        let bytes = (characteristic.value ?? Data()).map { $0 }

        if characteristic.uuid == HeadphoneGATTBatteryReader.opoNotifyUUID {
            if let value = HeadphoneGATTBatteryReader.opoBatteryPercentage(in: bytes) {
                cancelOPOFrameTimeout()
                finish(value)
            }
        } else if characteristic.uuid == HeadphoneGATTBatteryReader.batteryLevelUUID {
            if let byte = bytes.first {
                cancelOPOFrameTimeout()
                finish(Int(byte))
            }
        }
    }

    // MARK: Lifecycle

    private func cancelOPOFrameTimeout() {
        opoFrameWorkItem?.cancel()
        opoFrameWorkItem = nil
    }

    private func finish(_ value: Int?) {
        guard !isFinished else { return }
        isFinished = true
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        cancelOPOFrameTimeout()

        if let peripheral, didInitiateConnection {
            central?.cancelPeripheralConnection(peripheral)
        }
        peripheral?.delegate = nil
        central?.delegate = nil
        central = nil
        peripheral = nil
        completion(value)
        keepAlive = nil
    }
}