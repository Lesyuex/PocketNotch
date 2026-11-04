public struct MediaRemoteSnapshot: Equatable, Sendable {
    public let info: NowPlayingInfo?
    public let status: String

    public init(info: NowPlayingInfo?, status: String) {
        self.info = info
        self.status = status
    }
}
