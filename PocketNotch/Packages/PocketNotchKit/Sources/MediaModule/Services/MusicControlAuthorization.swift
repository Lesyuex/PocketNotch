import AppKit
import Foundation

/// 音乐 / Spotify 控制（Apple Events）授权。
///
/// 系统只允许在「App 主动向目标 App 发送 Apple Event」时弹出授权提示，且授权结果按目标 App
/// 分别记录。这里统一从 PocketNotch 的授权窗口发起：只探测「正在运行」的音乐 App，避免误启动
/// 目标应用，也避免在监听过程中自发弹出系统「允许控制」弹窗。
@MainActor
public enum MusicControlAuthorization {
    public static let musicAppName = "Music"
    public static let spotifyAppName = "Spotify"

    public static func displayName(for appName: String) -> String {
        switch appName {
        case musicAppName: "音乐"
        case spotifyAppName: "Spotify"
        default: appName
        }
    }

    /// 当前已授权的媒体 App 名称。
    public static func authorizedTargets(for settings: MediaMonitoringSettings) -> Set<String> {
        Set(settings.musicControlAuthorizedApps)
    }

    /// 是否有任意音乐 App 正在运行（授权探测依赖它，否则无法发起系统授权）。
    /// `NSWorkspace.runningApplications` 是同步系统调用，在 1s 权限轮询里每轮调用会徒增主线程开销，
    /// 因此加短 TTL 缓存（检测到运行中的应用不受 TTL 影响，因为授权只关心「此时有应用可授权」）。
    public static func isAnyMusicAppRunning() -> Bool {
        let now = Date()
        if let (at, value) = cachedRunningState, now.timeIntervalSince(at) < runningStateTTL {
            return value
        }
        let value = !MusicControlAuthorizationProbe.runningApps().isEmpty
        cachedRunningState = (now, value)
        return value
    }

    /// 非隔离的运行状态探测（不依赖 MainActor），供后台轮询直接调用。
    nonisolated public static func probeRunningMusicApps() -> Bool {
        RunningMusicAppCache.isAnyRunning()
    }

    public static func runningMusicApps() -> Set<String> {
        MusicControlAuthorizationProbe.runningApps()
    }

    private static var cachedRunningState: (date: Date, value: Bool)?
    private static let runningStateTTL: TimeInterval = 5.0

    /// 发起授权：对每个「正在运行」的音乐 App 发送一次探测 Apple Event，系统会在此时弹出
    /// 「允许控制」提示。返回本次新增授权的 App 名称（用户拒绝或中途取消则为空）。
    @discardableResult
    public static func requestAuthorization(
        for settings: MediaMonitoringSettings
    ) async -> Set<String> {
        let runningApps = MusicControlAuthorizationProbe.runningApps()
        guard !runningApps.isEmpty else { return [] }

        let results = await Task.detached(priority: .userInitiated) {
            MusicControlAuthorizationProbe.probeAll(runningApps)
        }.value

        var authorized = Set(settings.musicControlAuthorizedApps)
        authorized.formUnion(results.0)
        authorized.subtract(results.1)
        settings.musicControlAuthorizedApps = authorized.sorted()

        var denied = Set(settings.musicControlDeniedApps)
        denied.formUnion(results.1)
        denied.subtract(results.0)
        settings.musicControlDeniedApps = denied.sorted()

        return results.0
    }
}

/// 非隔离的「音乐 App 是否在运行」短 TTL 缓存：探测只读系统状态，后台线程可安全访问。
private enum RunningMusicAppCache {
    private static let lock = NSLock()
    private static var cached: (date: Date, value: Bool)?
    private static let ttl: TimeInterval = 5.0

    static func isAnyRunning() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if let (at, value) = cached, now.timeIntervalSince(at) < ttl {
            return value
        }
        let value = !MusicControlAuthorizationProbe.runningApps().isEmpty
        cached = (now, value)
        return value
    }
}

/// 无隔离的探测逻辑：只依赖 osascript 子进程与运行中的应用列表，可安全在后台执行。
private enum MusicControlAuthorizationProbe {
    enum Result {
        case authorized
        case denied
        case indeterminate
    }

    static func runningApps() -> Set<String> {
        let running = NSWorkspace.shared.runningApplications.map(\.bundleIdentifier)
        var apps: Set<String> = []
        if running.contains("com.apple.Music") {
            apps.insert("Music")
        }
        if running.contains("com.spotify.client") {
            apps.insert("Spotify")
        }
        return apps
    }

    static func probeAll(_ apps: Set<String>) -> (authorized: Set<String>, denied: Set<String>) {
        var authorized: Set<String> = []
        var denied: Set<String> = []
        for app in apps {
            switch probe(app) {
            case .authorized:
                authorized.insert(app)
            case .denied:
                denied.insert(app)
            case .indeterminate:
                break
            }
        }
        return (authorized, denied)
    }

    private static func probe(_ appName: String) -> Result {
        let script = "tell application \"\(appName)\" to get player state"
        let result = MediaRemoteProcessRunner.runOsaScript(script)
        if result.error == nil { return .authorized }
        if result.error?.contains("-1743") == true { return .denied }
        return .indeterminate
    }
}
