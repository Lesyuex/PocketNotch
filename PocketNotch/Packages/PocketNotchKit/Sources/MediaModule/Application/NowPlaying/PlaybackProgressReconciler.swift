import Foundation

struct PlaybackProgressReconciliation {
    let info: NowPlayingInfo?
    let didFinishPendingSeek: Bool
}

/// Owns temporary playback progress state used to mask stale snapshots after
/// seek, shuffle, and favorite commands.
struct PlaybackProgressReconciler {
    private struct PendingSeek {
        let title: String
        let artist: String
        let appPID: Int32?
        let targetPosition: TimeInterval
        let duration: TimeInterval
        let wasPlaying: Bool
        let requestedAt: Date

        func matches(_ info: NowPlayingInfo) -> Bool {
            if let appPID, let refreshedPID = info.appPID, appPID != refreshedPID {
                return false
            }
            return title == info.title
                && artist == info.artist
                && abs(duration - (info.duration ?? duration)) < 1
        }

        func projectedPosition(at date: Date) -> TimeInterval {
            let elapsed = wasPlaying ? max(date.timeIntervalSince(requestedAt), 0) : 0
            return min(max(targetPosition + elapsed, 0), duration)
        }
    }

    private struct ProtectedProgress {
        let title: String
        let artist: String
        let appPID: Int32?
        let elapsedTime: TimeInterval
        let duration: TimeInterval
        let isPlaying: Bool
        let anchoredAt: Date
        let expiresAt: Date

        func matches(_ info: NowPlayingInfo) -> Bool {
            if let appPID, let refreshedPID = info.appPID, appPID != refreshedPID {
                return false
            }
            return title == info.title
                && artist == info.artist
                && abs(duration - (info.duration ?? duration)) < 1
        }

        func projectedPosition(at date: Date) -> TimeInterval {
            let advanced = isPlaying ? max(date.timeIntervalSince(anchoredAt), 0) : 0
            return min(max(elapsedTime + advanced, 0), duration)
        }
    }

    private var pendingSeek: PendingSeek?
    private var protectedProgress: ProtectedProgress?

    mutating func beginSeek(
        from info: NowPlayingInfo,
        to targetPosition: TimeInterval,
        at requestedAt: Date
    ) -> NowPlayingInfo {
        let duration = info.duration ?? 0
        protectedProgress = nil
        pendingSeek = PendingSeek(
            title: info.title,
            artist: info.artist,
            appPID: info.appPID,
            targetPosition: targetPosition,
            duration: duration,
            wasPlaying: info.isPlaying,
            requestedAt: requestedAt
        )

        return replacingProgress(
            in: info,
            elapsedTime: targetPosition,
            duration: duration,
            isPlaying: info.isPlaying,
            updatedAt: requestedAt
        )
    }

    mutating func reconcile(
        _ refreshedInfo: NowPlayingInfo?,
        currentInfo: NowPlayingInfo?,
        at date: Date
    ) -> PlaybackProgressReconciliation {
        guard let pendingSeek else {
            return PlaybackProgressReconciliation(
                info: preservingProtectedProgress(in: refreshedInfo, at: date),
                didFinishPendingSeek: false
            )
        }
        guard date.timeIntervalSince(pendingSeek.requestedAt) < 1.5 else {
            self.pendingSeek = nil
            return PlaybackProgressReconciliation(
                info: refreshedInfo,
                didFinishPendingSeek: true
            )
        }
        guard let refreshedInfo else {
            return PlaybackProgressReconciliation(
                info: currentInfo,
                didFinishPendingSeek: false
            )
        }
        guard pendingSeek.matches(refreshedInfo) else {
            self.pendingSeek = nil
            return PlaybackProgressReconciliation(
                info: refreshedInfo,
                didFinishPendingSeek: true
            )
        }

        let refreshedPosition = projectedPosition(of: refreshedInfo, at: date)
        let expectedPosition = pendingSeek.projectedPosition(at: date)
        guard abs(refreshedPosition - expectedPosition) > 2 else {
            self.pendingSeek = nil
            return PlaybackProgressReconciliation(
                info: refreshedInfo,
                didFinishPendingSeek: true
            )
        }

        return PlaybackProgressReconciliation(
            info: replacingProgress(
                in: refreshedInfo,
                elapsedTime: expectedPosition,
                duration: refreshedInfo.duration ?? pendingSeek.duration,
                isPlaying: refreshedInfo.isPlaying,
                updatedAt: date
            ),
            didFinishPendingSeek: false
        )
    }

    mutating func protect(_ info: NowPlayingInfo?, at date: Date = Date()) {
        guard let info,
              let elapsedTime = info.elapsedTime,
              let duration = info.duration,
              duration > 0 else {
            protectedProgress = nil
            return
        }
        let advanced = info.isPlaying ? max(date.timeIntervalSince(info.updatedAt), 0) : 0
        protectedProgress = ProtectedProgress(
            title: info.title,
            artist: info.artist,
            appPID: info.appPID,
            elapsedTime: min(max(elapsedTime + advanced, 0), duration),
            duration: duration,
            isPlaying: info.isPlaying,
            anchoredAt: date,
            expiresAt: date.addingTimeInterval(1.5)
        )
    }

    mutating func discardProtectedProgress() {
        protectedProgress = nil
    }

    mutating func clearPendingSeek() {
        pendingSeek = nil
    }

    mutating func reset() {
        pendingSeek = nil
        protectedProgress = nil
    }

    private mutating func preservingProtectedProgress(
        in refreshedInfo: NowPlayingInfo?,
        at date: Date
    ) -> NowPlayingInfo? {
        guard let protectedProgress else { return refreshedInfo }
        guard date <= protectedProgress.expiresAt,
              let refreshedInfo,
              protectedProgress.matches(refreshedInfo) else {
            self.protectedProgress = nil
            return refreshedInfo
        }

        return replacingProgress(
            in: refreshedInfo,
            elapsedTime: protectedProgress.projectedPosition(at: date),
            duration: refreshedInfo.duration ?? protectedProgress.duration,
            isPlaying: protectedProgress.isPlaying,
            updatedAt: date
        )
    }

    private func projectedPosition(of info: NowPlayingInfo, at date: Date) -> TimeInterval {
        guard let elapsedTime = info.elapsedTime else { return 0 }
        let advanced = info.isPlaying ? max(date.timeIntervalSince(info.updatedAt), 0) : 0
        return min(max(elapsedTime + advanced, 0), info.duration ?? .greatestFiniteMagnitude)
    }

    private func replacingProgress(
        in info: NowPlayingInfo,
        elapsedTime: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool,
        updatedAt: Date
    ) -> NowPlayingInfo {
        NowPlayingInfo(
            title: info.title,
            artist: info.artist,
            album: info.album,
            artworkData: info.artworkData,
            appPID: info.appPID,
            sourceBundleIdentifier: info.sourceBundleIdentifier,
            isFavorited: info.isFavorited,
            elapsedTime: elapsedTime,
            duration: duration,
            isPlaying: isPlaying,
            updatedAt: updatedAt
        )
    }
}
