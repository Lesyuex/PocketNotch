import Foundation
import IOKit

/// 系统温度采样契约，便于注入桩做测试。
public protocol SystemTemperatureProviding: AnyObject {
    /// CPU 当前结温（摄氏度）；读取失败返回 nil。
    func cpuTemperatureCelsius() -> Double?
    /// GPU 当前结温（摄氏度）；SMC 无 GPU 温度键的机型返回 nil。
    func gpuTemperatureCelsius() -> Double?
}

/// 通过 AppleSMC 私有接口读取 CPU 温度（Apple Silicon / Intel 通用）。
///
/// 采用社区验证的 SMCParamStruct（80 字节固定布局）ABI，经 `IOConnectCallStructMethod`
/// 交互：selector 固定为 2，命令经 `data8` 指定（9=查询键信息、5=读取数据、8=按索引枚举键）。
/// 温度键不硬编码，而是像 vorssaint 那样一次性枚举全部 SMC 键，筛选 `Tp*`/`Te*` 前缀，
/// 每次采样取所有满足值（1...125）中的最大值。
///
/// 这是私有/脆弱 API，按项目铁律隔离在本文件内，其余代码仅通过 `SystemTemperatureProviding` 访问。
public final class AppleSMCTemperatureReader: SystemTemperatureProviding {
    private let connection: io_connect_t?
    private var tempKeysPrepared = false
    private var cpuKeys: [Key] = []
    private var gpuKeys: [Key] = []

    public init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        defer { IOObjectRelease(service) }
        guard service != 0 else {
            connection = nil
            return
        }
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else {
            connection = nil
            return
        }
        connection = conn
    }

    deinit {
        if let connection, connection != 0 {
            IOServiceClose(connection)
        }
    }

    public func cpuTemperatureCelsius() -> Double? {
        guard let connection else { return nil }
        prepareKeysIfNeeded(connection: connection)
        return maxTemperature(of: cpuKeys, connection: connection)
    }

    public func gpuTemperatureCelsius() -> Double? {
        guard let connection else { return nil }
        prepareKeysIfNeeded(connection: connection)
        return maxTemperature(of: gpuKeys, connection: connection)
    }

    // MARK: - 键发现

    /// 首次采样时枚举全部 SMC 键，缓存 CPU（Tp/Te）与 GPU（Tg）温度键。
    private func prepareKeysIfNeeded(connection: io_connect_t) {
        guard !tempKeysPrepared else { return }
        tempKeysPrepared = true
        let keys = allKeys(connection: connection)
        cpuKeys = keys.filter { $0.name.hasPrefix("Tp") || $0.name.hasPrefix("Te") }
        // 实测 Apple Silicon 的 GPU 温度键为 Tg* 前缀（如 Tg0U、Tg16）；
        // 部分机型另有 TG*（ioft/功耗类）会被温度值域过滤掉。
        gpuKeys = keys.filter { $0.name.hasPrefix("Tg") }
    }

    private func allKeys(connection: io_connect_t) -> [Key] {
        let count = keyCount(connection: connection)
        guard count > 0 else { return [] }

        var result: [Key] = []
        for index in 0..<count {
            var probe = SMCParamStruct()
            probe.data8 = Command.keyFromIndex.rawValue
            probe.data32 = UInt32(index)
            guard let out = call(connection, &probe), out.result == 0 else { continue }

            let name = Self.fourCCString(out.key)
            guard !name.isEmpty else { continue }

            var info = SMCParamStruct()
            info.key = out.key
            info.data8 = Command.keyInfo.rawValue
            guard let infoOut = call(connection, &info), infoOut.result == 0 else { continue }

            result.append(Key(
                code: out.key,
                name: name,
                dataSize: infoOut.keyInfo.dataSize,
                dataType: Self.fourCCString(infoOut.keyInfo.dataType)
            ))
        }
        return result
    }

    /// SMC 键总数（读取 "#KEY" 键头 4 字节，大端）。
    private func keyCount(connection: io_connect_t) -> Int {
        var input = SMCParamStruct()
        input.key = Self.fourCC("#KEY")
        input.keyInfo.dataSize = 4
        input.data8 = Command.readKey.rawValue
        guard let out = call(connection, &input), out.result == 0 else { return 0 }
        let bytes = withUnsafeBytes(of: out.bytes) { Array($0.prefix(4)) }
        guard bytes.count == 4 else { return 0 }
        return Int(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
    }

    /// 求一组温度键的最大有效温度；值域校验 1...125 过滤脏数据。
    private func maxTemperature(of keys: [Key], connection: io_connect_t) -> Double? {
        let values = keys.compactMap { key -> Double? in
            guard let value = readValue(key, connection: connection), (1...125).contains(value) else {
                return nil
            }
            return value
        }
        return values.max()
    }

    // MARK: - 读取

    private func readValue(_ key: Key, connection: io_connect_t) -> Double? {
        var input = SMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = key.dataSize
        input.data8 = Command.readKey.rawValue
        guard let out = call(connection, &input), out.result == 0 else { return nil }

        let bytes = withUnsafeBytes(of: out.bytes) { Array($0.prefix(Int(key.dataSize))) }
        switch key.dataType {
        case "flt " where bytes.count == 4:
            return Double(bytes.withUnsafeBytes { $0.load(as: Float32.self) })
        case "sp78" where bytes.count == 2:
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256.0
        case "ioft" where bytes.count == 8:
            return Double(bytes.withUnsafeBytes { $0.load(as: UInt64.self) }) / 65_536.0
        default:
            return nil
        }
    }

    private func call(_ connection: io_connect_t, _ input: inout SMCParamStruct) -> SMCParamStruct? {
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let kr = IOConnectCallStructMethod(
            connection,
            UInt32(Command.handleYCPEvent.rawValue),
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )
        return (kr == kIOReturnSuccess) ? output : nil
    }

    // MARK: - 工具

    private static func fourCC(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func fourCCString(_ value: UInt32) -> String {
        let chars = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
        return String(bytes: chars, encoding: .ascii) ?? ""
    }

    // MARK: - ABI 定义

    private struct Key {
        let code: UInt32
        let name: String
        let dataSize: UInt32
        let dataType: String
    }

    /// 命令字节（经 SMCParamStruct.data8 传入）。
    private enum Command: UInt8 {
        case handleYCPEvent = 2
        case readKey = 5
        case keyFromIndex = 8
        case keyInfo = 9
    }

    /// AppleSMC 用户端交换结构：固定 80 字节布局。
    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }
}