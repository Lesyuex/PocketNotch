import Foundation
import AppKit
import PocketNotchShared

enum MediaRemotePlaybackStateResolver {
    static func resolve(playbackRate: Double?) -> Bool {
        playbackRate.map { $0 > 0 } ?? false
    }

    static func resolve(playbackRate: Double?, fallback: Bool?) -> Bool {
        playbackRate.map { $0 > 0 } ?? fallback ?? false
    }
}

/// 私有框架（MediaRemote）隔离点：所有脆弱/私有 API 只允许出现在此文件。
/// API 失效或需上架时只改这一处。
public final class MediaRemoteService: MediaRemoteProviding, @unchecked Sendable {
    private typealias GetNowPlayingInfoFunction = @convention(c) (
        DispatchQueue,
        @escaping @convention(block) (NSDictionary?) -> Void
    ) -> Void

    private typealias GetIsPlayingFunction = @convention(c) (
        DispatchQueue,
        @escaping @convention(block) (Bool) -> Void
    ) -> Void

    private typealias GetPIDFunction = @convention(c) (
        DispatchQueue,
        @escaping @convention(block) (Int32) -> Void
    ) -> Void

    private typealias SendCommandFunction = @convention(c) (Int32, NSDictionary?) -> Void

    private typealias RegisterForNowPlayingNotificationsFunction = @convention(c) (DispatchQueue) -> Void
    private typealias UnregisterForNowPlayingNotificationsFunction = @convention(c) () -> Void
    private typealias SetWantsNowPlayingNotificationsFunction = @convention(c) (Bool) -> Void

    private enum Command {
        static let togglePlayPause: Int32 = 2
        static let nextTrack: Int32 = 4
        static let previousTrack: Int32 = 5
        static let advanceShuffleMode: Int32 = 6
        static let seekToPlaybackPosition: Int32 = 24
    }

    private enum NotificationNames {
        static let nowPlayingInfoDidChange = Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification")
        static let playbackStateDidChange = Notification.Name("kMRMediaRemotePlaybackStateDidChangeNotification")
        static let applicationDidChange = Notification.Name("kMRMediaRemoteNowPlayingApplicationDidChangeNotification")
        static let applicationIsPlayingDidChange = Notification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")
    }

    private let frameworkHandle: UnsafeMutableRawPointer?
    private let callbackQueue = DispatchQueue.main
    private let mediaCallbackQueue = DispatchQueue(label: "com.pocketnotch.media.callback", qos: .userInitiated)
    private let getNowPlayingInfo: GetNowPlayingInfoFunction?
    private let getIsPlaying: GetIsPlayingFunction?
    private let getPID: GetPIDFunction?
    private let sendCommand: SendCommandFunction?
    private let registerForNowPlayingNotifications: RegisterForNowPlayingNotificationsFunction?
    private let unregisterForNowPlayingNotifications: UnregisterForNowPlayingNotificationsFunction?
    private let setWantsNowPlayingNotifications: SetWantsNowPlayingNotificationsFunction?
    private let notificationObservers = LockedBox<[NSObjectProtocol]>([])
    private let workspaceNotificationObservers = LockedBox<[NSObjectProtocol]>([])
    private let currentSourceBundleIdentifier = LockedBox<String?>(nil)
    private let observedChangeEventTask = LockedBox<Task<Void, Never>?>(nil)
    private let fallbackService = MediaRemoteFallbackService()
    /// MediaRemote 一次切歌会广播多条分布式通知，helper 监听也会连续输出多行；
    /// 尾随去抖把一次事件风暴合并为一次刷新，避免中间的陈旧/部分快照打到 UI。
    private static let observedChangeDebounceInterval: Duration = .milliseconds(180)

    /// 事件去抖的单调起点，仅用于诊断「事件风暴被防抖切成几段」。

    public init() {
        frameworkHandle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW
        )
        getNowPlayingInfo = MediaRemoteService.loadSymbol(
            "MRMediaRemoteGetNowPlayingInfo",
            from: frameworkHandle,
            as: GetNowPlayingInfoFunction.self
        )
        getIsPlaying = MediaRemoteService.loadSymbol(
            "MRMediaRemoteGetNowPlayingApplicationIsPlaying",
            from: frameworkHandle,
            as: GetIsPlayingFunction.self
        )
        getPID = MediaRemoteService.loadSymbol(
            "MRMediaRemoteGetNowPlayingApplicationPID",
            from: frameworkHandle,
            as: GetPIDFunction.self
        )
        sendCommand = MediaRemoteService.loadSymbol(
            "MRMediaRemoteSendCommand",
            from: frameworkHandle,
            as: SendCommandFunction.self
        )
        registerForNowPlayingNotifications = MediaRemoteService.loadSymbol(
            "MRMediaRemoteRegisterForNowPlayingNotifications",
            from: frameworkHandle,
            as: RegisterForNowPlayingNotificationsFunction.self
        )
        unregisterForNowPlayingNotifications = MediaRemoteService.loadSymbol(
            "MRMediaRemoteUnregisterForNowPlayingNotifications",
            from: frameworkHandle,
            as: UnregisterForNowPlayingNotificationsFunction.self
        )
        setWantsNowPlayingNotifications = MediaRemoteService.loadSymbol(
            "MRMediaRemoteSetWantsNowPlayingNotifications",
            from: frameworkHandle,
            as: SetWantsNowPlayingNotificationsFunction.self
        )

        if frameworkHandle == nil {
            PocketNotchLog.media.error("MediaRemote framework failed to load")
        }
        if getNowPlayingInfo == nil {
            PocketNotchLog.media.error("MRMediaRemoteGetNowPlayingInfo symbol is unavailable")
        }
    }

    deinit {
        stopObserving()
        if let frameworkHandle {
            dlclose(frameworkHandle)
        }
    }

    public func currentSnapshot() async -> MediaRemoteSnapshot {
        // Prefer the stream/one-shot helper. Newer macOS versions may return an
        // empty dictionary to a third-party process calling MediaRemote directly.
        if let helperSnapshot = await fallbackService.fetchCurrentMediaRemoteSnapshot() {
            currentSourceBundleIdentifier.value = helperSnapshot.info?.sourceBundleIdentifier
            PocketNotchLog.media.debug(
                "MediaRemote snapshot: source=helper hasInfo=\(helperSnapshot.info != nil) pid=\(helperSnapshot.info?.appPID ?? 0) playing=\(helperSnapshot.info?.isPlaying == true) title=\(helperSnapshot.info?.title ?? "<nil>", privacy: .public)"
            )
            return helperSnapshot
        }

        let snapshot = await fetchCurrentSnapshot()
        currentSourceBundleIdentifier.value = snapshot.info?.sourceBundleIdentifier
        PocketNotchLog.media.debug(
            "MediaRemote snapshot: source=primary hasInfo=\(snapshot.info != nil) pid=\(snapshot.info?.appPID ?? 0) playing=\(snapshot.info?.isPlaying == true) title=\(snapshot.info?.title ?? "<nil>", privacy: .public) status=\(snapshot.status, privacy: .public)"
        )
        return snapshot
    }

    public func startObserving(_ onChange: @Sendable @escaping () -> Void) {
        guard notificationObservers.value.isEmpty else { return }

        setWantsNowPlayingNotifications?(true)
        registerForNowPlayingNotifications?(callbackQueue)

        let emit: @Sendable () -> Void = { [weak self] in
            self?.scheduleDebouncedObservedChange(onChange)
        }

        let names = [
            NotificationNames.nowPlayingInfoDidChange,
            NotificationNames.playbackStateDidChange,
            NotificationNames.applicationDidChange,
            NotificationNames.applicationIsPlayingDidChange
        ]

        notificationObservers.value = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: nil
            ) { _ in
                PocketNotchLog.media.debug("MediaRemote notification received: \(name.rawValue, privacy: .public)")
                emit()
            }
        }

        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        workspaceNotificationObservers.value = [
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
                let terminatedPID = application.processIdentifier
                guard self?.discardCachedSnapshot(forTerminatedPID: terminatedPID) == true else {
                    PocketNotchLog.media.debug(
                        "Unrelated application terminated; keeping current media layout: \(application.localizedName ?? "unknown", privacy: .public) pid=\(terminatedPID)"
                    )
                    return
                }
                PocketNotchLog.media.debug(
                    "Current media application terminated; refreshing media state: \(application.localizedName ?? "unknown", privacy: .public) pid=\(terminatedPID)"
                )
                emit()
            }
        ]

        fallbackService.startObserving(emit)
    }

    public func stopObserving() {
        let observers = notificationObservers.value
        notificationObservers.value = []
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        let workspaceObservers = workspaceNotificationObservers.value
        workspaceNotificationObservers.value = []
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspaceNotificationCenter.removeObserver($0) }
        unregisterForNowPlayingNotifications?()
        setWantsNowPlayingNotifications?(false)
        observedChangeEventTask.value?.cancel()
        observedChangeEventTask.value = nil
        fallbackService.stopObserving()
    }

    private func scheduleDebouncedObservedChange(_ onChange: @Sendable @escaping () -> Void) {
        observedChangeEventTask.value?.cancel()
        observedChangeEventTask.value = Task {
            try? await Task.sleep(for: Self.observedChangeDebounceInterval)
            guard !Task.isCancelled else { return }
            // 距本次事件流入恰好 180ms。若上一次也刚放行过，这里会密集出现 fire 行，
            // 说明一次切歌被防抖切成了多段刷新 —— 闪屏的必要条件之一。
            onChange()
        }
    }

    public func setMusicControlAuthorizedTargets(_ targets: Set<String>) {
        fallbackService.setAppleScriptControlEnabled(forTargets: targets)
    }

    public func togglePlay() {
        if fallbackService.sendHelperCommand(Command.togglePlayPause) { return }
        if fallbackService.sendAppleScriptCommand("playpause") { return }
        sendCommand?(Command.togglePlayPause, nil)
    }

    public func toggleShuffle() async -> Bool? {
        NSLog("[DEBUG_SHUF] MediaRemoteService.toggleShuffle called")
        let result = await Task.detached(priority: .userInitiated) { [weak self] in
            self?.performToggleShuffle()
        }.value
        NSLog("[DEBUG_SHUF] MediaRemoteService.toggleShuffle result: \(String(describing: result))")
        return result
    }

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

    public func shuffleState() async -> Bool? {
        await Task.detached(priority: .utility) { [weak self] in
            guard let self else { return nil }
            return self.fallbackService.shuffleState(
                sourceBundleIdentifier: self.currentSourceBundleIdentifier.value
            )
        }.value
    }

    private func performToggleShuffle() -> Bool? {
        if let isEnabled = fallbackService.toggleShuffle(
            sourceBundleIdentifier: currentSourceBundleIdentifier.value
        ) {
            return isEnabled
        }
        if fallbackService.sendHelperCommand(Command.advanceShuffleMode) { return nil }
        sendCommand?(Command.advanceShuffleMode, nil)
        return nil
    }

    public func toggleFavorite() async -> Bool? {
        await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return nil }
            return self.fallbackService.toggleFavorite(
                sourceBundleIdentifier: self.currentSourceBundleIdentifier.value
            )
        }.value
    }

    public func seek(to position: TimeInterval) {
        guard position.isFinite else { return }
        let clampedPosition = max(position, 0)
        if fallbackService.seek(to: clampedPosition) { return }
        sendCommand?(
            Command.seekToPlaybackPosition,
            ["kMRMediaRemoteOptionPlaybackPosition": clampedPosition]
        )
    }

    public func next() {
        if fallbackService.sendHelperCommand(Command.nextTrack) { return }
        if fallbackService.sendAppleScriptCommand("next track") { return }
        sendCommand?(Command.nextTrack, nil)
    }

    public func previous() {
        if fallbackService.sendHelperCommand(Command.previousTrack) { return }
        if fallbackService.sendAppleScriptCommand("previous track") { return }
        sendCommand?(Command.previousTrack, nil)
    }

    private func fetchCurrentSnapshot() async -> MediaRemoteSnapshot {
        // 灵动显示只反映 MediaRemote 的当前会话，不枚举客户端、不读取历史缓存，
        // 也不根据 CoreAudio 输出重新选择媒体来源。
        guard frameworkHandle != nil else {
            return MediaRemoteSnapshot(info: nil, status: "MediaRemote 加载失败")
        }
        guard let getNowPlayingInfo else {
            return MediaRemoteSnapshot(info: nil, status: "读取函数不可用")
        }

        // MediaRemote 的歌曲字典、播放状态和 PID 是三组独立异步 API。媒体应用切换时并发读取
        // 会把不同应用的数据拼成一个快照，因此用前后两次 PID 把字典读取夹住并验证来源稳定。
        // 注意：回调使用独立的后台队列 `mediaCallbackQueue`，在后台线程直接执行，无需依赖
        // 主 runloop。`MRMediaRemoteGetNowPlayingInfo` 若以 `.main` 为回调队列，需要主线程
        // 空闲地驱动 runloop 才能收到回调；在 App 的 @MainActor 上下文中常因 runloop 嵌套
        // 而永不派发，导致拿不到含封面的字典。故这里改用后台回调队列并保持顺序 await。
        let leadingPID = validPID(await fetchNowPlayingPID())
        let nowPlayingDictionary = await fetchNowPlayingDictionary(using: getNowPlayingInfo)
        let isApplicationPlaying = await fetchIsPlaying()
        guard let dictionary = nowPlayingDictionary else {
            PocketNotchLog.media.warning("MediaRemote returned no now playing dictionary")
            return MediaRemoteSnapshot(info: nil, status: "MediaRemote 未提供媒体信息")
        }
        let trailingPID = validPID(await fetchNowPlayingPID())
        if let leadingPID, let trailingPID, leadingPID != trailingPID {
            PocketNotchLog.media.debug(
                "MediaRemote source changed while reading snapshot: \(leadingPID) -> \(trailingPID)"
            )
            return MediaRemoteSnapshot(info: nil, status: "媒体来源切换中")
        }
        let nowPlayingApplicationPID = trailingPID ?? leadingPID

        let title = MediaRemoteDictionaryParser.string(
            from: dictionary,
            keys: "kMRMediaRemoteNowPlayingInfoTitle",
            "title"
        )
        let artist = MediaRemoteDictionaryParser.string(
            from: dictionary,
            keys: "kMRMediaRemoteNowPlayingInfoArtist",
            "artist"
        )
        let album = MediaRemoteDictionaryParser.string(
            from: dictionary,
            keys: "kMRMediaRemoteNowPlayingInfoAlbum",
            "album"
        )
        let elapsedTime = MediaRemoteDictionaryParser.number(
            from: dictionary,
            keys: "kMRMediaRemoteNowPlayingInfoElapsedTime",
            "elapsedTime"
        )
        let duration = MediaRemoteDictionaryParser.number(
            from: dictionary,
            keys: "kMRMediaRemoteNowPlayingInfoDuration",
            "duration"
        )
        let rawArtworkData = MediaRemoteDictionaryParser.data(
            from: dictionary,
            keys: "kMRMediaRemoteNowPlayingInfoArtworkData",
            "artworkData"
        )
        let artworkData = ArtworkDataNormalizer.normalized(rawArtworkData)
        let updatedAt = MediaRemoteDictionaryParser.date(
            from: dictionary,
            keys: "kMRMediaRemoteNowPlayingInfoTimestamp",
            "timestamp"
        ) ?? Date()
        let playbackRate = MediaRemoteDictionaryParser.number(
            from: dictionary,
            keys: "kMRMediaRemoteNowPlayingInfoPlaybackRate",
            "rate"
        )
        // playbackRate 优先使用当前字典的会话状态；缺失时使用 MediaRemote
        // 同一当前会话提供的全局播放状态，不向其他客户端探测或切换来源。
        let isPlaying = MediaRemotePlaybackStateResolver.resolve(
            playbackRate: playbackRate,
            fallback: isApplicationPlaying
        )
        let isFavorited = MediaRemoteDictionaryParser.bool(
            from: dictionary,
            keys: "kMRMediaRemoteNowPlayingInfoIsLiked",
            "isLiked"
        )

        guard !title.isEmpty || !artist.isEmpty else {
            PocketNotchLog.media.warning("MediaRemote now playing dictionary has no title or artist. Key count: \(dictionary.count)")
            return MediaRemoteSnapshot(info: nil, status: "媒体字典无歌曲字段")
        }

        PocketNotchLog.media.debug("MediaRemote now playing: \(title, privacy: .public) - \(artist, privacy: .public)")

        let info = NowPlayingInfo(
            title: title.isEmpty ? L10n.tr("media.unknownTitle") : title,
            artist: artist,
            album: album.isEmpty ? nil : album,
            artworkData: artworkData,
            appPID: nowPlayingApplicationPID,
            sourceBundleIdentifier: bundleIdentifier(forPID: nowPlayingApplicationPID),
            isFavorited: isFavorited,
            elapsedTime: elapsedTime,
            duration: duration,
            isPlaying: isPlaying,
            updatedAt: updatedAt
        )
        // 主 MediaRemote 快照成功后同步清除 helper 来源，避免控制命令继续指向旧来源。
        fallbackService.clearCurrentSource()
        return MediaRemoteSnapshot(info: info, status: "已读取系统媒体信息")
    }

    private func bundleIdentifier(forPID pid: Int32?) -> String? {
        guard let pid, pid > 0 else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }
    @discardableResult
    private func discardCachedSnapshot(forTerminatedPID pid: Int32) -> Bool {
        return fallbackService.discardCachedSnapshot(
            forTerminatedPID: pid
        )
    }

    private func fetchNowPlayingDictionary(using getNowPlayingInfo: GetNowPlayingInfoFunction) async -> NSDictionary? {
        await withCheckedContinuation { continuation in
            getNowPlayingInfo(mediaCallbackQueue) { dictionary in
                continuation.resume(returning: dictionary)
            }
        }
    }

    private func validPID(_ pid: Int32?) -> Int32? {
        guard let pid, pid > 0 else { return nil }
        return pid
    }

    private func fetchIsPlaying() async -> Bool? {
        guard let getIsPlaying else { return nil }

        return await withCheckedContinuation { continuation in
            getIsPlaying(mediaCallbackQueue) { isPlaying in
                continuation.resume(returning: isPlaying)
            }
        }
    }

    private func fetchNowPlayingPID() async -> Int32? {
        guard let getPID else { return nil }

        return await withCheckedContinuation { continuation in
            getPID(mediaCallbackQueue) { pid in
                continuation.resume(returning: pid)
            }
        }
    }

    private static func loadSymbol<T>(_ name: String, from handle: UnsafeMutableRawPointer?, as type: T.Type) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }
}
