import Foundation
import PocketNotchShared

enum MediaSessionObservationOrigin: Sendable {
    case mediaRemote
    case helper
    case clientEnumeration
}

/// 媒体会话的唯一状态收敛点。
/// CoreAudio 只能说明某个音频引擎仍注册在系统中，不能证明该会话正在播放；
/// 播放源和播放态都必须由 MediaRemote 会话数据决定。
final class MediaSessionCoordinator: @unchecked Sendable {
    private struct Entry {
        var lastElapsedTime: TimeInterval?
        var stalledSamples = 0
    }

    private let lock = NSLock()
    private var entries: [Int32: Entry] = [:]

    func resolve(
        _ snapshot: MediaRemoteSnapshot,
        origin: MediaSessionObservationOrigin
    ) -> MediaRemoteSnapshot {
        guard let info = snapshot.info,
              let pid = info.appPID,
              pid > 0 else {
            return snapshot
        }

        lock.lock()
        defer { lock.unlock() }

        guard info.isPlaying,
              origin != .clientEnumeration,
              let elapsed = info.elapsedTime,
              elapsed.isFinite else {
            entries[pid] = Entry(lastElapsedTime: info.elapsedTime, stalledSamples: 0)
            return snapshot
        }

        var entry = entries[pid] ?? Entry(lastElapsedTime: nil, stalledSamples: 0)
        let advanced = entry.lastElapsedTime.map { elapsed - $0 >= 0.25 } ?? true
        if advanced {
            entry.stalledSamples = 0
        } else {
            entry.stalledSamples += 1
        }
        entry.lastElapsedTime = elapsed
        entries[pid] = entry

        // 首次采样保留响应速度；连续两次播放进度不动，认定是滞后的播放标记。
        guard entry.stalledSamples >= 2 else { return snapshot }
        PocketNotchLog.media.debug(
            "Media session coordinator forced paused pid=\(pid) elapsed=\(elapsed) stalledSamples=\(entry.stalledSamples)"
        )
        return replacingPlaybackState(in: snapshot, isPlaying: false)
    }

    func reset() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    private func replacingPlaybackState(
        in snapshot: MediaRemoteSnapshot,
        isPlaying: Bool
    ) -> MediaRemoteSnapshot {
        guard let info = snapshot.info else { return snapshot }
        return MediaRemoteSnapshot(
            info: NowPlayingInfo(
                title: info.title,
                artist: info.artist,
                album: info.album,
                artworkData: info.artworkData,
                appPID: info.appPID,
                sourceBundleIdentifier: info.sourceBundleIdentifier,
                isFavorited: info.isFavorited,
                elapsedTime: info.elapsedTime,
                duration: info.duration,
                isPlaying: isPlaying,
                updatedAt: Date()
            ),
            status: snapshot.status + "；播放进度未变化，已收敛为暂停"
        )
    }
}
