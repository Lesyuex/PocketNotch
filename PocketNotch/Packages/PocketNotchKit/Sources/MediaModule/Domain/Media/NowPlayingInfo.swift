import Foundation

public struct NowPlayingInfo: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let album: String?
    /// 归一化后的展示图（超大原图已压缩限界）。灵动态、折叠、此刻页卡片与展开态统一使用该压缩文件，
    /// 不再保留未经压缩限界的原图，避免整份高分辨率封面长期占用内存。
    public let artworkData: Data?
    /// 播放来源 app 的进程 PID。用于识别应用退出后的过期媒体快照；曲目无封面时也用于回退 app 图标。
    public let appPID: Int32?
    public let sourceBundleIdentifier: String?
    public let isFavorited: Bool?
    public let elapsedTime: TimeInterval?
    public let duration: TimeInterval?
    public let isPlaying: Bool
    public let updatedAt: Date

    public init(
        title: String,
        artist: String,
        album: String? = nil,
        artworkData: Data? = nil,
        appPID: Int32? = nil,
        sourceBundleIdentifier: String? = nil,
        isFavorited: Bool? = nil,
        elapsedTime: TimeInterval? = nil,
        duration: TimeInterval? = nil,
        isPlaying: Bool,
        updatedAt: Date = Date()
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
        self.appPID = appPID
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.isFavorited = isFavorited
        self.elapsedTime = elapsedTime
        self.duration = duration
        self.isPlaying = isPlaying
        self.updatedAt = updatedAt
    }
}
