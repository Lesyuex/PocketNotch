import Foundation
import Observation

@MainActor
@Observable
public final class RecentFoldersViewModel {
    public let lockedStore = LockedFoldersStore()
    public private(set) var folders: [RecentFolder] = []

    public init() {}

    /// 已锁定的文件夹固定排在最前，其余按 Finder 最近使用次序跟随。
    public func reload() {
        let recents = FinderRecentFoldersService.loadRecentFolders()
        let unlocked = recents.filter { !lockedStore.isLocked($0) }
        folders = lockedStore.locked + unlocked
    }

    public func isLocked(_ folder: RecentFolder) -> Bool {
        lockedStore.isLocked(folder)
    }

    public func toggleLocked(_ folder: RecentFolder) {
        lockedStore.toggle(folder)
        reload()
    }
}