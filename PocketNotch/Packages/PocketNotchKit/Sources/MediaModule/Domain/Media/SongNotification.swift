import Foundation

/// 切歌通知载荷。每次歌曲变化都创建独立实例并立即展示。
public struct SongNotification: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let artist: String
    public let album: String?
    public let artworkData: Data

    /// 换封面但保持同一 id：横幅弹出后封面才补到（MediaRemote 先推歌名、
    /// 封面滞后一批）时，就地改正图，不重播出现动画。
    public func withArtwork(_ artworkData: Data) -> SongNotification {
        SongNotification(id: id, title: title, artist: artist, album: album, artworkData: artworkData)
    }
}
