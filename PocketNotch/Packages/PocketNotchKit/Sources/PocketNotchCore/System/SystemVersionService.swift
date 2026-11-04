import Foundation

/// 解析后的系统版本号。
public struct SystemVersionInfo: Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }
}

/// 系统版本的唯一取数入口：任何需要 macOS 版本判断的地方都走这个 Service，
/// 不允许再直接读 `ProcessInfo.operatingSystemVersion`，便于统一缓存与测试替换。
public protocol SystemVersionProviding: Sendable {
    func currentVersion() -> SystemVersionInfo
}

public extension SystemVersionProviding {
    /// 是否为 macOS 26 及以上（Liquid Glass 等新能力分水岭）。
    var isMacOS26OrLater: Bool {
        currentVersion().major >= 26
    }
}

/// 默认实现：进程启动时读一次 `ProcessInfo` 并缓存（系统版本运行期不变）。
/// 支持在设置中心「模拟 macOS 版本」写入覆盖值：设置后所有版本判断走覆盖值，
/// 清除后自动回落真实系统版本。任何改动都会广播 `overrideDidChange` 供 UI 刷新。
public final class SystemVersionService: SystemVersionProviding, @unchecked Sendable {
    public static let shared = SystemVersionService()

    /// 版本模拟在 UserDefaults 中的键；存格式 "major.minor.patch"，不存在即跟随真实系统。
    private static let overrideKey = "pocketnotch.macOSVersionOverride"

    /// 覆盖值变化时广播，触发依赖版本判断的界面重求值。
    public static let overrideDidChange = Notification.Name("PocketNotchSystemVersionOverrideDidChange")

    private let cachedVersion: SystemVersionInfo
    private let defaults: UserDefaults

    public init(processInfo: ProcessInfo = .processInfo, defaults: UserDefaults = .standard) {
        let version = processInfo.operatingSystemVersion
        cachedVersion = SystemVersionInfo(
            major: version.majorVersion,
            minor: version.minorVersion,
            patch: version.patchVersion
        )
        self.defaults = defaults
    }

    public init(version: SystemVersionInfo, defaults: UserDefaults = .standard) {
        cachedVersion = version
        self.defaults = defaults
    }

    /// 真实系统版本，不受模拟覆盖影响。
    public var realVersion: SystemVersionInfo {
        cachedVersion
    }

    /// 当前模拟覆盖值；nil 表示跟随真实系统版本。
    public var overriddenVersion: SystemVersionInfo? {
        get {
            guard let raw = defaults.string(forKey: Self.overrideKey) else { return nil }
            return Self.parse(raw)
        }
        set {
            if let version = newValue {
                defaults.set("\(version.major).\(version.minor).\(version.patch)", forKey: Self.overrideKey)
            } else {
                defaults.removeObject(forKey: Self.overrideKey)
            }
            NotificationCenter.default.post(name: Self.overrideDidChange, object: nil)
        }
    }

    public func currentVersion() -> SystemVersionInfo {
        overriddenVersion ?? cachedVersion
    }

    private static func parse(_ raw: String) -> SystemVersionInfo? {
        let parts = raw.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return SystemVersionInfo(
            major: parts[0],
            minor: parts[1],
            patch: parts.count >= 3 ? parts[2] : 0
        )
    }
}
