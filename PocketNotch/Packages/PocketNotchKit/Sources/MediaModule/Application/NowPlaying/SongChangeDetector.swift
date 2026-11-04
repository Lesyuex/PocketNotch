import Foundation

/// 只负责歌曲身份判定与封面就绪门控，不持有任何 UI 状态或计时任务。
struct SongChangeDetector {
    private struct SongIdentity: Equatable {
        let title: String
        let artist: String

        init(info: NowPlayingInfo) {
            title = info.title.trimmingCharacters(in: .whitespacesAndNewlines)
            artist = info.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func representsSameSong(as other: SongIdentity) -> Bool {
            guard title == other.title else { return false }
            return artist == other.artist || artist.isEmpty || other.artist.isEmpty
        }
    }

    enum Update {
        case none
        case dismiss
        case publish(info: NowPlayingInfo, artwork: Data)
    }

    private var lastSongIdentity: SongIdentity?
    private var pendingArtworkSongIdentity: SongIdentity?

    mutating func update(with info: NowPlayingInfo?) -> Update {
        guard let info else { return .dismiss }

        let identity = SongIdentity(info: info)
        guard !identity.title.isEmpty || !identity.artist.isEmpty else { return .none }
        guard let previous = lastSongIdentity else {
            lastSongIdentity = identity
            return .none
        }

        if !identity.representsSameSong(as: previous) {
            lastSongIdentity = identity
            pendingArtworkSongIdentity = info.artworkData == nil ? identity : nil
            guard let artwork = info.artworkData else { return .dismiss }
            return .publish(info: info, artwork: artwork)
        }

        // 歌手等字段可能晚于歌名和封面到达；吸收本次补全，避免下次再被识别为新歌。
        lastSongIdentity = identity
        guard let pendingArtworkSongIdentity,
              pendingArtworkSongIdentity.representsSameSong(as: identity),
              let artwork = info.artworkData else {
            return .none
        }
        self.pendingArtworkSongIdentity = nil
        return .publish(info: info, artwork: artwork)
    }

    mutating func clearPendingNotification() {
        pendingArtworkSongIdentity = nil
    }

    mutating func reset() {
        lastSongIdentity = nil
        pendingArtworkSongIdentity = nil
    }
}
