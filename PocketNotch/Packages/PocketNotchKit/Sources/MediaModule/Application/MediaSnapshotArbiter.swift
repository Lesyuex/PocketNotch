import Foundation
import PocketNotchShared

enum MediaSnapshotOrigin: Equatable, Sendable {
    case mediaRemote
    case audioOutputFallback
}

enum AudioOutputEvidence: Equatable, Sendable {
    case producing
    case notObserved
    case unavailable

    init(_ value: Bool?) {
        switch value {
        case true: self = .producing
        case false: self = .notObserved
        case nil: self = .unavailable
        }
    }
}

struct MediaSourceSelectionPolicy: Sendable {
    static let standard = Self(
        sourceSwitchProtectionInterval: 1.2,
        requiredFallbackConfirmations: 2
    )

    let sourceSwitchProtectionInterval: TimeInterval
    let requiredFallbackConfirmations: Int
    /// 切歌后短时间内回退到刚被替换歌曲的候选是 MediaRemote 的瞬时旧读。
    /// 字典缺 timestamp 时 updatedAt 会退化为读取时刻，无法证明候选新旧，
    /// 因此按本地时钟在窗口内一律拒绝，避免 A -> B -> A -> B 抖动。
    let trackRevertProtectionInterval: TimeInterval = 1.5

    func acceptsAudioOutputFallback(
        selectedEvidence: AudioOutputEvidence,
        candidateEvidence: AudioOutputEvidence,
        elapsedSinceSelectionChange: TimeInterval,
        fallbackConfirmationCount: Int
    ) -> Bool {
        guard candidateEvidence == .producing else { return false }

        switch selectedEvidence {
        case .producing, .unavailable:
            return false
        case .notObserved:
            return elapsedSinceSelectionChange >= sourceSwitchProtectionInterval
                && fallbackConfirmationCount >= requiredFallbackConfirmations
        }
    }
}

/// 避免仅激活但未输出音频的媒体应用抢占当前真实播放来源。
final class MediaSnapshotArbiter: @unchecked Sendable {
    private struct ReplacedTrackEvidence {
        let pid: Int32?
        let title: String
        let artist: String
        let replacedAt: TimeInterval
    }

    private let lock = NSLock()
    private let policy: MediaSourceSelectionPolicy
    private let uptime: @Sendable () -> TimeInterval
    private var selectedSnapshot: MediaRemoteSnapshot?
    private var sourceRecency: [Int32] = []
    private var selectionChangedAt: TimeInterval?
    private var fallbackConfirmationCount = 0
    private var replacedTrack: ReplacedTrackEvidence?

    init(
        policy: MediaSourceSelectionPolicy = .standard,
        uptime: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.policy = policy
        self.uptime = uptime
    }

    func select(
        _ candidate: MediaRemoteSnapshot,
        origin: MediaSnapshotOrigin = .mediaRemote,
        isSourceRunning: (Int32) -> Bool,
        isSourceProducingAudio: (Int32) -> Bool?
    ) -> MediaRemoteSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let selectedBefore = selectedSnapshot?.info
        let candidate = preservingExplicitPauseMetadata(
            preservingArtworkIfNeeded(in: candidate)
        )

        guard shouldKeepSelectedSnapshot(
            over: candidate,
            origin: origin,
            isSourceRunning: isSourceRunning,
            isSourceProducingAudio: isSourceProducingAudio
        ), let selectedSnapshot else {
            accept(candidate)
            PocketNotchLog.media.debug(
                "Media arbiter accepted origin=\(String(describing: origin)) pid=\(candidate.info?.appPID ?? 0) playing=\(candidate.info?.isPlaying == true)"
            )
            return candidate
        }

        PocketNotchLog.media.debug(
            "Media arbiter kept pid=\(selectedSnapshot.info?.appPID ?? 0) playing=\(selectedSnapshot.info?.isPlaying == true) candidateOrigin=\(String(describing: origin)) candidatePid=\(candidate.info?.appPID ?? 0) candidatePlaying=\(candidate.info?.isPlaying == true) previousPid=\(selectedBefore?.appPID ?? 0) previousPlaying=\(selectedBefore?.isPlaying == true)"
        )

        return MediaRemoteSnapshot(
            info: selectedSnapshot.info,
            status: "忽略未输出音频的媒体应用，继续显示当前播放来源"
        )
    }

    @discardableResult
    func discardSource(pid: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        sourceRecency.removeAll { $0 == pid }
        guard selectedSnapshot?.info?.appPID == pid else { return false }
        selectedSnapshot = nil
        selectionChangedAt = nil
        fallbackConfirmationCount = 0
        replacedTrack = nil
        return true
    }

    /// 最近成为当前播放源的应用排在前面。调用方仍需用 CoreAudio 过滤是否正在出声。
    func recentlySelectedSourcePIDs() -> [Int32] {
        lock.lock()
        defer { lock.unlock() }
        return sourceRecency.reversed()
    }

    func selectedSourcePID() -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        return validPID(selectedSnapshot?.info?.appPID)
    }

    func reset() {
        lock.lock()
        selectedSnapshot = nil
        sourceRecency = []
        selectionChangedAt = nil
        fallbackConfirmationCount = 0
        replacedTrack = nil
        lock.unlock()
    }

    private func accept(_ snapshot: MediaRemoteSnapshot) {
        let previousInfo = selectedSnapshot?.info
        let nextInfo = snapshot.info
        let sourceChanged = previousInfo?.appPID != nextInfo?.appPID
        let playbackStateChanged = previousInfo?.isPlaying != nextInfo?.isPlaying
        if sourceChanged || playbackStateChanged {
            selectionChangedAt = uptime()
            fallbackConfirmationCount = 0
        }
        if let previousInfo, let nextInfo,
           isDifferentTrack(nextInfo, from: previousInfo) {
            replacedTrack = ReplacedTrackEvidence(
                pid: validPID(previousInfo.appPID),
                title: previousInfo.title,
                artist: previousInfo.artist,
                replacedAt: uptime()
            )
        }
        selectedSnapshot = snapshot
        if snapshot.info == nil {
            sourceRecency.removeAll()
        } else {
            updateSourceRecency(for: snapshot)
        }
    }

    private func updateSourceRecency(for snapshot: MediaRemoteSnapshot) {
        guard let info = snapshot.info,
              let pid = validPID(info.appPID) else {
            return
        }

        sourceRecency.removeAll { $0 == pid }
        // 明确暂停必须从最近播放栈移除。部分播放器暂停后仍保持音频引擎运行，
        // CoreAudio 的 IsRunningOutput 会短暂甚至长期为 true，不能据此把它重新加入。
        guard info.isPlaying else { return }
        sourceRecency.append(pid)
    }

    /// MediaRemote 在同一首歌的多个字段分批更新时，偶尔会先返回已有封面、随后又短暂返回 nil。
    /// 这种瞬时降级不应让 UI 退回 App 图标；但切歌时绝不能沿用上一首歌的封面。
    private func preservingArtworkIfNeeded(in candidate: MediaRemoteSnapshot) -> MediaRemoteSnapshot {
        guard let selectedInfo = selectedSnapshot?.info,
              let candidateInfo = candidate.info,
              selectedInfo.artworkData != nil,
              candidateInfo.artworkData == nil,
              selectedInfo.appPID == candidateInfo.appPID,
              selectedInfo.title == candidateInfo.title,
              selectedInfo.artist == candidateInfo.artist,
              selectedInfo.album == candidateInfo.album else {
            return candidate
        }

        return MediaRemoteSnapshot(
            info: NowPlayingInfo(
                title: candidateInfo.title,
                artist: candidateInfo.artist,
                album: candidateInfo.album,
                artworkData: selectedInfo.artworkData,
                appPID: candidateInfo.appPID,
                sourceBundleIdentifier: candidateInfo.sourceBundleIdentifier,
                isFavorited: candidateInfo.isFavorited,
                elapsedTime: candidateInfo.elapsedTime,
                duration: candidateInfo.duration,
                isPlaying: candidateInfo.isPlaying,
                updatedAt: candidateInfo.updatedAt
            ),
            status: candidate.status
        )
    }

    /// MediaRemote 在多应用切换/暂停时可能把另一首歌的标题和当前 PID 短暂拼在一起。
    /// 只要同一 PID 的暂停快照时间不落后，就保留已选来源的歌曲元数据，但采用新的暂停状态，
    /// 确保封面和频谱立即停止，而不会出现标题串台。
    private func preservingExplicitPauseMetadata(
        _ candidate: MediaRemoteSnapshot
    ) -> MediaRemoteSnapshot {
        guard let selectedInfo = selectedSnapshot?.info,
              let candidateInfo = candidate.info,
              let selectedPID = validPID(selectedInfo.appPID),
              selectedPID == validPID(candidateInfo.appPID),
              selectedInfo.isPlaying,
              !candidateInfo.isPlaying,
              isDifferentTrack(candidateInfo, from: selectedInfo),
              candidateInfo.updatedAt >= selectedInfo.updatedAt else {
            return candidate
        }

        return MediaRemoteSnapshot(
            info: NowPlayingInfo(
                title: selectedInfo.title,
                artist: selectedInfo.artist,
                album: selectedInfo.album,
                artworkData: selectedInfo.artworkData,
                appPID: selectedInfo.appPID,
                sourceBundleIdentifier: candidateInfo.sourceBundleIdentifier
                    ?? selectedInfo.sourceBundleIdentifier,
                isFavorited: candidateInfo.isFavorited ?? selectedInfo.isFavorited,
                elapsedTime: selectedInfo.elapsedTime,
                duration: candidateInfo.duration ?? selectedInfo.duration,
                isPlaying: false,
                updatedAt: candidateInfo.updatedAt
            ),
            status: candidate.status
        )
    }

    private func shouldKeepSelectedSnapshot(
        over candidate: MediaRemoteSnapshot,
        origin: MediaSnapshotOrigin,
        isSourceRunning: (Int32) -> Bool,
        isSourceProducingAudio: (Int32) -> Bool?
    ) -> Bool {
        guard let selectedInfo = selectedSnapshot?.info,
              let selectedPID = validPID(selectedInfo.appPID) else {
            return false
        }

        let candidatePID = validPID(candidate.info?.appPID)
        let selectedIsProducingAudio = isSourceProducingAudio(selectedPID)
        let candidateIsProducingAudio = candidatePID.flatMap(isSourceProducingAudio)

        // CoreAudio 兜底只能纠正「来源归属」，不能用 generic 快照覆盖同一进程
        // 已有的歌曲/暂停元数据；播放器暂停后音频引擎滞留时尤其重要。
        if origin == .audioOutputFallback, candidatePID == selectedPID {
            return true
        }

        if origin == .audioOutputFallback, candidatePID != selectedPID {
            // MediaRemote 的明确暂停优先于 CoreAudio 的滞后活动标记。
            // 暂停来源即使仍被 CoreAudio 认为在出声，也不能阻塞真正播放源的切换。
            let selectedEvidence: AudioOutputEvidence = selectedInfo.isPlaying
                ? AudioOutputEvidence(selectedIsProducingAudio)
                : .notObserved
            let candidateEvidence = AudioOutputEvidence(candidateIsProducingAudio)

            guard selectedEvidence == .notObserved,
                  candidateEvidence == .producing else {
                fallbackConfirmationCount = 0
                return true
            }

            let elapsed = selectionChangedAt.map { max(uptime() - $0, 0) }
                ?? policy.sourceSwitchProtectionInterval
            if elapsed < policy.sourceSwitchProtectionInterval {
                fallbackConfirmationCount = 0
                return true
            }

            fallbackConfirmationCount += 1
            PocketNotchLog.media.debug(
                "Media arbiter fallback evidence selected=\(String(describing: selectedEvidence)) candidate=\(String(describing: candidateEvidence)) elapsed=\(elapsed) confirmations=\(self.fallbackConfirmationCount)"
            )
            return !policy.acceptsAudioOutputFallback(
                selectedEvidence: selectedEvidence,
                candidateEvidence: candidateEvidence,
                elapsedSinceSelectionChange: elapsed,
                fallbackConfirmationCount: fallbackConfirmationCount
            )
        }

        fallbackConfirmationCount = 0

        // 当已选中的来源是 genericPlaybackSnapshot 兜底快照（artist 为"正在播放"）
        // 时，不应保护它。如果候选来自 MediaRemote 真实数据（有实际歌名/艺术家），
        // 必须立即替换，否则 PocketNotch 重启后拿到的兜底快照会因 updatedAt 较新而一直
        // 拒绝真实媒体快照，导致灵动岛始终显示"应用名/正在播放"。
        if candidatePID == selectedPID {
            // selectedInfo 来自 genericPlaybackSnapshot 时，不保护
            if selectedInfo.artist == "正在播放" {
                return false
            }

            // MediaRemote 会把同一次切歌拆成多条通知；后续读取偶尔短暂回退到
            // 上一首歌。接受这种过期快照会形成 A -> B -> A -> B，并让 B 弹两次。
            if let candidateInfo = candidate.info,
               isDifferentTrack(candidateInfo, from: selectedInfo),
               candidateInfo.updatedAt < selectedInfo.updatedAt {
                return true
            }

            // 字典缺 timestamp 时 updatedAt 退化为读取时刻，上面的新旧比对失效；
            // 切歌后短时间内回退到刚被替换的歌曲，一律按瞬时旧读拒绝。
            if let candidateInfo = candidate.info,
               isDifferentTrack(candidateInfo, from: selectedInfo),
               isRecentlyReplacedTrack(candidateInfo) {
                PocketNotchLog.media.debug(
                    "Media arbiter rejected track revert pid=\(candidateInfo.appPID ?? 0) title=\(candidateInfo.title, privacy: .public)"
                )
                return true
            }

            // 同一来源、同一首歌明确上报暂停时，应立即接受 MediaRemote 的播放状态。
            // CoreAudio 的进程活动标记可能在暂停后短时间内仍为 true，若继续以它覆盖暂停状态，
            // 前导封面和尾随频谱都会误判为仍在播放。
            if let candidateInfo = candidate.info,
               candidateInfo.isPlaying == false,
               candidateInfo.title == selectedInfo.title,
               candidateInfo.artist == selectedInfo.artist {
                return false
            }

            // 媒体应用切换过程中，info / playing / PID 的异步结果可能短暂混合。
            // 只有元数据并非当前歌曲时，才用真实音频活动保护已选中的播放来源。
            return selectedIsProducingAudio == true && candidate.info?.isPlaying != true
        }

        // 双源同时发声时的迟滞保护：如果候选来源曾被选中过（在 sourceRecency 中），
        // 说明是两个正在出声的 App 因 updatedAt 交替更新导致的抖动，不应切换。
        // 如果候选来源从未被选中过，说明是用户主动打开了新 App，立即接受。
        if candidatePID != selectedPID,
           let candidateInfo = candidate.info,
           candidateInfo.isPlaying,
           selectedInfo.isPlaying,
           selectedIsProducingAudio == true,
           candidateIsProducingAudio == true {
            let candidateWasRecentlySelected = candidatePID.map { sourceRecency.contains($0) } ?? false
            return candidateWasRecentlySelected
        }

        // MediaRemote 的明确播放事件表示用户刚选择了新来源，立即接受。
        // CoreAudio 只能在保护期后通过连续证据纠正，不能用滞后的单次快照推翻它。
        if let candidateInfo = candidate.info, candidateInfo.isPlaying {
            return false
        }
        if selectedIsProducingAudio == true, candidateIsProducingAudio != true {
            return true
        }
        if candidateIsProducingAudio == true || selectedIsProducingAudio == false {
            return false
        }

        guard selectedInfo.isPlaying, isSourceRunning(selectedPID) else { return false }
        // 空快照可能是 MediaRemote 的短暂读取失败。只有 CoreAudio 明确仍在输出时
        // 才保留旧的播放态；若已确认无输出，应允许清空来源，使封面/频谱停止。
        guard let candidateInfo = candidate.info else {
            return selectedIsProducingAudio != false
        }
        return !candidateInfo.isPlaying
    }

    private func isRecentlyReplacedTrack(_ candidate: NowPlayingInfo) -> Bool {
        guard let replacedTrack,
              replacedTrack.pid == validPID(candidate.appPID),
              replacedTrack.title == candidate.title,
              replacedTrack.artist == candidate.artist else {
            return false
        }
        return uptime() - replacedTrack.replacedAt < policy.trackRevertProtectionInterval
    }

    private func validPID(_ pid: Int32?) -> Int32? {
        guard let pid, pid > 0 else { return nil }
        return pid
    }

    private func isDifferentTrack(_ lhs: NowPlayingInfo, from rhs: NowPlayingInfo) -> Bool {
        lhs.title != rhs.title || lhs.artist != rhs.artist
    }
}
