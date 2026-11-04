import Foundation

/// Now Playing 数据源抽象，便于替换系统实现并在测试中注入桩对象。
public protocol MediaRemoteProviding: Sendable {
    func currentSnapshot() async -> MediaRemoteSnapshot
    func startObserving(_ onChange: @Sendable @escaping () -> Void)
    func stopObserving()
    func togglePlay()
    func shuffleState() async -> Bool?
    func toggleShuffle() async -> Bool?
    func toggleFavorite() async -> Bool?
    func seek(to position: TimeInterval)
    func next()
    func previous()
    /// 更新可执行 AppleScript 控制的媒体 App 名称集合，默认不启用。
    func setMusicControlAuthorizedTargets(_ targets: Set<String>)
}

extension MediaRemoteProviding {
    public func setMusicControlAuthorizedTargets(_ targets: Set<String>) {}
}
