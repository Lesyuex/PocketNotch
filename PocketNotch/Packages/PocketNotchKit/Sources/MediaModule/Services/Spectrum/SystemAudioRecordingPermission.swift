import ApplicationServices
import CryptoKit
import Darwin
import Foundation
import PocketNotchCore

/// 系统音频录制授权的只读查询（不弹窗、不建 tap）。
///
/// Process Tap 由 TCC 的服务 `kTCCServiceAudioCapture` 把关；macOS 没有公开的预检 API，
/// 只有几条可交叉验证的信号：
/// - 本 build 真实建链（tap+聚合设备+IOProc）成功过 → 强信号，绝对已授权；
/// - 「屏幕与系统音频录制」组合授权会使 `CGPreflightScreenCaptureAccess()` 为 true；
/// - TCC 私有 SPI `TCCAccessPreflight` 查询（只读，不触发弹窗）——私有且各版本语义不一，
///   实测对 adhoc 进程返回值可能与真实授权状态矛盾，因此只作为补充信号，不作为唯一依据。
///
/// TCC SPI 是私有/脆弱 API，按架构铁律「私有 API 收敛隔离」全部封在本文件，
/// 失效时只需改这一处，对外只暴露状态枚举。
@available(macOS 14.4, *)
public enum SystemAudioRecordingAuthorization: Equatable {
    case granted
    case notDetermined
    case denied
}

@available(macOS 14.4, *)
public func systemAudioRecordingAuthorization() -> SystemAudioRecordingAuthorization {
    // 结果为进程级常驻状态，短 TTL 内复用，避免 1s 轮询每轮都打 tccd / WindowServer。
    if let cached = systemAudioRecordingAuthorizationCache.get() {
        return cached
    }
    let result = computeAudioRecordingAuthorization()
    systemAudioRecordingAuthorizationCache.set(result)
    return result
}

@available(macOS 14.4, *)
private func computeAudioRecordingAuthorization() -> SystemAudioRecordingAuthorization {
    // 任一成立即视为已授权。信号按可信度排序：
    // 1) 真实建链标记（仅本 build 有效，指纹隔离）
    // 2) 「屏幕与系统音频录制」组合授权
    // 3) TCC SPI 明确报告已授权
    let chainKey = makeSystemAudioRecordingChainKey()
    if UserDefaults.standard.bool(forKey: chainKey) { return .granted }
    if CGPreflightScreenCaptureAccess() { return .granted }
    if let result = tccAudioCapturePreflightResult() {
        let interpreted = interpretPreflightResult(result)
        if interpreted == .granted { return .granted }
    }
    // 无可信授权信号：是否明确拒绝，仅交给 SPI 判定。
    // SPI 对 adhoc 进程的「拒绝」值也可能失真，因此兜底按未决定处理，
    // 由用户在面板中重新触发授权探测（真实建链）裁决。
    if let result = tccAudioCapturePreflightResult() {
        let interpreted = interpretPreflightResult(result)
        if interpreted == .denied { return .notDetermined }
        return interpreted
    }
    return .notDetermined
}

/// 音频授权结果短 TTL 缓存：权限是系统级常驻状态，不会秒级变化。
/// 用锁保护，可跨线程访问（1s 轮询在主线程、设置面板在 MainActor、建链探测在后台）。
@available(macOS 14.4, *)
private let systemAudioRecordingAuthorizationCache = SystemAudioRecordingAuthorizationCache()

@available(macOS 14.4, *)
private final class SystemAudioRecordingAuthorizationCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: SystemAudioRecordingAuthorization?
    private var cachedAt: Date = .distantPast
    private static let ttl: TimeInterval = 2.0

    func get() -> SystemAudioRecordingAuthorization? {
        lock.lock()
        defer { lock.unlock() }
        guard let cached else { return nil }
        guard Date().timeIntervalSince(cachedAt) < Self.ttl else { return nil }
        return cached
    }

    func set(_ result: SystemAudioRecordingAuthorization) {
        lock.lock()
        defer { lock.unlock() }
        cached = result
        cachedAt = Date()
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
    }
}

/// 授权交互完成后立即清空缓存，让状态在用户返回时立即反映，而不必等 TTL。
/// 供 App 壳在发起/完成授权操作后调用。
@available(macOS 14.4, *)
public func invalidateSystemAudioRecordingAuthorizationCache() {
    systemAudioRecordingAuthorizationCache.invalidate()
}

/// TCCAccessPreflight 的取值在不同 macOS 版本语义不同（私有 SPI 无稳定文档）：
/// 实测 macOS 27：2=已授权、0=拒绝、1=未决定（kTCCServiceAudioCapture 授权后实测为 2）。
/// 老系统（macOS 14/15 系，in-gui/AudioCap 在产验证）：0=已授权、1=拒绝。
@available(macOS 14.4, *)
private func interpretPreflightResult(_ result: Int) -> SystemAudioRecordingAuthorization {
    if SystemVersionService.shared.isMacOS26OrLater {
        switch result {
        case 2: return .granted
        case 0, 3: return .denied
        default: return .notDetermined
        }
    } else {
        switch result {
        case 0: return .granted
        case 1: return .denied
        default: return .notDetermined
        }
    }
}

/// 记录「系统音频录制」真实建链成功（视同已授权），供后续只读判定复用。
/// 该标记仅在 TCC SPI 失效/未知时作为兜底信号。
/// 因 ad-hoc 签名下每次重编都是新的 TCC 身份，本地标记必须按二进制指纹隔离，
/// 否则旧 build 的标记会让新 build 误判为已授权，实际建 tap 仍会弹窗。
@available(macOS 14.4, *)
func markSystemAudioRecordingChainGranted() {
    let key = makeSystemAudioRecordingChainKey()
    UserDefaults.standard.set(true, forKey: key)
    // 清理旧作用域：只保留旧版无作用域 key 与新下标不相同时的历史脏值
    for prefix in [systemAudioRecordingChainKey, systemAudioRecordingChainKey + ".v2"] {
        if prefix == key { continue }
        if UserDefaults.standard.object(forKey: prefix) != nil {
            UserDefaults.standard.removeObject(forKey: prefix)
        }
    }
}

@available(macOS 14.4, *)
private func makeSystemAudioRecordingChainKey() -> String {
    if let digest = mainExecutableDigest() {
        return "\(systemAudioRecordingChainKey).v2.\(digest)"
    }
    return systemAudioRecordingChainKey
}

/// 当前主可执行文件内容的 SHA-256 摘要，作为二进制身份指纹。
/// 重编（内容变化）→ 指纹变化 → 旧授权标记失效。
/// 公开给 App 壳复用（文件访问等同样按二进制身份隔离的本地标记）。
public func mainExecutableDigest() -> String? {
    generatorDigest
}

private let generatorDigest: String? = {
    guard let executableURL = Bundle.main.executableURL,
          let data = try? Data(contentsOf: executableURL) else { return nil }
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}()

@available(macOS 14.4, *)
private let systemAudioRecordingChainKey = "media.systemAudioRecordingAuthorized"

// MARK: - TCC SPI（私有框架，仅限本文件）

@available(macOS 14.4, *)
private typealias TCCAccessPreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int

@available(macOS 14.4, *)
private let tccPreflightFunction: TCCAccessPreflightFunction? = {
    guard let handle = TCCAccessPreflight.dynamicLibraryHandle else { return nil }
    guard let symbol = dlsym(handle, "TCCAccessPreflight") else { return nil }
    return unsafeBitCast(symbol, to: TCCAccessPreflightFunction.self)
}()

@available(macOS 14.4, *)
private func tccAudioCapturePreflightResult() -> Int? {
    tccPreflightResult(for: "kTCCServiceAudioCapture")
}

@available(macOS 14.4, *)
private func tccPreflightResult(for service: String) -> Int? {
    guard let preflight = tccPreflightFunction else { return nil }
    return preflight(service as CFString, nil)
}

private enum TCCAccessPreflight {
    static let dynamicLibraryHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
    }()
}