import Foundation
import AppKit
import PocketNotchShared

/// 在 MediaRemote 私有 API 无法返回数据时，负责 Helper 与 AppleScript 降级读取。
/// 将进程生命周期、来源缓存和降级命令隔离，避免主服务随新增媒体源持续膨胀。
final class MediaRemoteFallbackService: @unchecked Sendable {
    private let fallbackSource = LockedBox<String?>(nil)
    private let latestHelperSnapshot = LockedBox<MediaRemoteSnapshot?>(nil)
    private let helperMonitorProcess = LockedBox<Process?>(nil)
    private let helperMonitorOutputBuffer = LockedBox<String>("")
    /// 已获得 Apple Events 授权、可执行 AppleScript 的媒体 App 名称集合。
    /// 未授权的 App 一律不走 AppleScript，避免在监听过程中自发弹出系统「允许控制」弹窗。
    private let authorizedAppleScriptTargets = LockedBox<Set<String>>([])

    private func fileLog(_ message: String) {
        let path = "/tmp/pn_shuffle_debug.log"
        let line = "[\(Date())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: path) {
            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    /// 更新可执行 AppleScript 控制的媒体 App 集合（如 "Music"、"Spotify"）。
    func setAppleScriptControlEnabled(forTargets targets: Set<String>) {
        authorizedAppleScriptTargets.value = targets
    }

    private func isAppleScriptEnabled(for appName: String) -> Bool {
        authorizedAppleScriptTargets.value.contains(appName)
    }

    /// 常驻 helper monitor 输出的最新快照。只以数据本身为准，不设来源闸门：
    /// 主进程直读成功会重置 fallbackSource，若以此为缓存闸门，则会永久废掉
    /// helper 数据，使 MediaRemote 会话不稳定的应用（PID/字典时有时无）再也上不了岛。
    /// 陈旧剪裁由 `discardCachedSnapshot` 与 monitor 常驻输出负责。
    var cachedHelperSnapshot: MediaRemoteSnapshot? {
        latestHelperSnapshot.value
    }

    /// Boring Notch-style one-shot `get`: read the current MediaRemote session
    /// through the helper process when the stream has not produced its first item yet.
    func fetchCurrentMediaRemoteSnapshot() async -> MediaRemoteSnapshot? {
        if let snapshot = cachedHelperSnapshot {
            return snapshot
        }
        return await Task.detached(priority: .userInitiated) { [weak self] in
            self?.mediaRemoteHelperSnapshot()
        }.value
    }

    func clearCurrentSource() {
        fallbackSource.value = nil
    }

    private func mediaRemoteHelperSnapshot() -> MediaRemoteSnapshot? {
        let source = MediaRemoteHelperSource.snapshot

        guard let output = runSwiftSnippet(source) else { return nil }
        guard let snapshot = MediaRemoteHelperOutputParser.parse(output, status: "已通过系统 helper 读取媒体信息") else {
            PocketNotchLog.media.warning("helper 返回格式异常：\(output.prefix(200), privacy: .public)")
            return nil
        }

        fallbackSource.value = "MediaRemoteHelper"
        latestHelperSnapshot.value = snapshot
        return snapshot
    }

    func startObserving(_ onChange: @Sendable @escaping () -> Void) {
        guard helperMonitorProcess.value == nil else { return }

        let process = Process()
        let output = Pipe()
        let error = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["-e", MediaRemoteHelperSource.monitor]
        process.standardOutput = output
        process.standardError = error

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty,
                  let chunk = String(data: data, encoding: .utf8) else {
                return
            }
            self.consumeHelperMonitorOutput(chunk, onChange: onChange)
        }

        error.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !message.isEmpty else {
                return
            }
            PocketNotchLog.media.warning("MediaRemote helper monitor stderr: \(message, privacy: .public)")
        }

        process.terminationHandler = { [weak self] _ in
            output.fileHandleForReading.readabilityHandler = nil
            error.fileHandleForReading.readabilityHandler = nil
            self?.helperMonitorProcess.value = nil
            // monitor 退出后其数据即失效；缓存不再依赖 fallbackSource 门卫，
            // 必须在此显式清空，避免陈旧快照永久占位、阻塞主进程直读恢复。
            self?.latestHelperSnapshot.value = nil
            if self?.fallbackSource.value == "MediaRemoteHelper" {
                self?.fallbackSource.value = nil
            }
        }

        do {
            try process.run()
            helperMonitorProcess.value = process
        } catch {
            PocketNotchLog.media.error("MediaRemote helper monitor 启动失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    func stopObserving() {
        let process = helperMonitorProcess.value
        helperMonitorProcess.value = nil
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (process?.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        // Monitoring is a lifecycle boundary. Do not retain the last artwork-bearing
        // snapshot or a partial helper line after the media module is deactivated.
        latestHelperSnapshot.value = nil
        fallbackSource.value = nil
        helperMonitorOutputBuffer.value = ""
    }

    private func consumeHelperMonitorOutput(_ chunk: String, onChange: @Sendable @escaping () -> Void) {
        // helper 输出的单行可能很长（Spotify 封面 base64 可达数百 KB），因此绝不能对行首
        // 做 `.suffix()` 截断，否则会破坏 title/artwork 字段。这里仅保留最后一个可能不完整
        // 的行做累积，并设一个足够大的行长度上限防止畸形 helper 无限膨胀内存。
        let combined = helperMonitorOutputBuffer.value + chunk
        var lines = combined.components(separatedBy: "\n")
        helperMonitorOutputBuffer.value = String((lines.popLast() ?? "").suffix(2 * 1024 * 1024))

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let snapshot = MediaRemoteHelperOutputParser.parse(trimmed, status: "已通过系统 helper 监听媒体信息") else {
                PocketNotchLog.media.warning("helper monitor 返回格式异常：\(trimmed.prefix(200), privacy: .public)")
                continue
            }
            // 同一次媒体事件会触发多条系统通知，helper 会重复输出内容相同的快照。
            // 注意去重发生在 parse 之后：base64 封面每行都已解码，这条 guard 省不下解析开销，
            // 它只决定是否回填缓存、是否触发一次刷新。
            // NowPlayingInfo 的 Equatable 是合成的，含 elapsedTime / updatedAt，
            // 二者在播放中推进，所以「内容相同」的快照通常并不相等，这条 guard 大多数时候拦不住。
            guard snapshot.info != latestHelperSnapshot.value?.info else {
                continue
            }
            latestHelperSnapshot.value = snapshot
            fallbackSource.value = "MediaRemoteHelper"
            onChange()
        }
    }

    private func runSwiftSnippet(_ source: String) -> String? {
        let result = MediaRemoteProcessRunner.runSwiftSnippet(source)
        if let error = result.error {
            PocketNotchLog.media.warning("helper swift snippet failed: \(error, privacy: .public)")
            return nil
        }
        return result.output
    }

    @discardableResult
    func discardCachedSnapshot(forTerminatedPID pid: Int32) -> Bool {
        guard latestHelperSnapshot.value?.info?.appPID == pid else { return false }
        latestHelperSnapshot.value = nil
        if fallbackSource.value == "MediaRemoteHelper" {
            fallbackSource.value = nil
        }
        return true
    }

    func sendAppleScriptCommand(_ command: String) -> Bool {
        guard let sourceName = fallbackSource.value,
              sourceName == "Music" || sourceName == "Spotify",
              isAppleScriptEnabled(for: sourceName) else {
            return false
        }

        let script = """
        tell application "\(sourceName)"
            \(command)
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            PocketNotchLog.media.warning("\(sourceName, privacy: .public) AppleScript command failed: \(String(describing: error), privacy: .public)")
            return false
        }
        return true
    }

    func toggleShuffle(sourceBundleIdentifier: String?) -> Bool? {
        let sourceName: String
        switch sourceBundleIdentifier {
        case "com.apple.Music":
            sourceName = "Music"
        case "com.spotify.client":
            sourceName = "Spotify"
        default:
            return nil
        }

        // 暂时放宽限制，便于排查
        // guard isAppleScriptEnabled(for: sourceName) else { return nil }

        let script: String
        if sourceName == "Music" {
            script = """
            tell application "System Events"
                tell process "Music"
                    click menu bar item "控制" of menu bar 1
                    delay 0.2
                    click menu item "随机播放" of menu 1 of menu bar item "控制" of menu bar 1
                end tell
            end tell
            return true
            """
        } else {
            script = """
            tell application "Spotify"
                set currentState to shuffling
                set shuffling to not currentState
                delay 0.05
                return shuffling
            end tell
            """
        }

        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let resultDescriptor = appleScript?.executeAndReturnError(&error)
        if let error {
            PocketNotchLog.media.warning("\(sourceName, privacy: .public) shuffle command failed: \(String(describing: error), privacy: .public)")
            NSLog("[DEBUG_SHUF] shuffle command failed for \(sourceName): \(error)")
            return nil
        }
        if sourceName == "Music" {
            let boolResult = resultDescriptor?.booleanValue ?? false
            NSLog("[DEBUG_SHUF] shuffle command result for \(sourceName): \(boolResult)")
            return boolResult
        }
        let result = resultDescriptor?.booleanValue ?? false
        NSLog("[DEBUG_SHUF] shuffle command result for \(sourceName): \(result)")
        return result
    }

    func shuffleState(sourceBundleIdentifier: String?) -> Bool? {
        let sourceName: String
        switch sourceBundleIdentifier {
        case "com.apple.Music":
            sourceName = "Music"
        case "com.spotify.client":
            sourceName = "Spotify"
        default:
            return nil
        }

        // 暂时放宽限制，便于排查
        // guard isAppleScriptEnabled(for: sourceName) else { return nil }

        let script: String
        if sourceName == "Music" {
            script = """
            tell application "Music"
                return shuffle enabled
            end tell
            """
        } else {
            script = """
            tell application "Spotify"
                return shuffling
            end tell
            """
        }

        var error: NSDictionary?
        let resultDescriptor = NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            PocketNotchLog.media.warning("\(sourceName, privacy: .public) shuffle state query failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        if sourceName == "Music" {
            let mode = resultDescriptor?.stringValue ?? ""
            return (mode == "songs" || mode == "albums")
        }
        return resultDescriptor?.booleanValue
    }

    func toggleFavorite(sourceBundleIdentifier: String?) -> Bool? {
        guard sourceBundleIdentifier == "com.apple.Music" else { return nil }
        // 暂时放宽限制，便于排查
        // guard isAppleScriptEnabled(for: "Music") else { return nil }
        let script = """
        tell application "Music"
            set favorited of current track to not (favorited of current track)
            return favorited of current track
        end tell
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error).booleanValue
        if let error {
            PocketNotchLog.media.warning("Music favorite command failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        return result
    }

    func seek(to position: TimeInterval) -> Bool {
        guard position.isFinite else { return false }
        let clampedPosition = max(position, 0)
        switch fallbackSource.value {
        case "MediaRemoteHelper":
            return sendHelperSeek(to: clampedPosition)
        case "Music", "Spotify":
            return sendAppleScriptCommand("set player position to \(clampedPosition)")
        default:
            return false
        }
    }

    func sendHelperCommand(_ command: Int32) -> Bool {
        guard fallbackSource.value == "MediaRemoteHelper" else { return false }

        let source = """
        import Foundation

        typealias SendCommandFunction = @convention(c) (Int32, NSDictionary?) -> Void
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
              let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else {
            exit(2)
        }

        let sendCommand = unsafeBitCast(symbol, to: SendCommandFunction.self)
        sendCommand(\(command), nil)
        """

        return runSwiftSnippet(source) != nil
    }

    private func sendHelperSeek(to position: TimeInterval) -> Bool {
        let source = """
        import Foundation

        typealias SendCommandFunction = @convention(c) (Int32, NSDictionary?) -> Void
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
              let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else {
            exit(2)
        }

        let sendCommand = unsafeBitCast(symbol, to: SendCommandFunction.self)
        let options: NSDictionary = ["kMRMediaRemoteOptionPlaybackPosition": \(position)]
        sendCommand(24, options)
        """

        return runSwiftSnippet(source) != nil
    }

}
