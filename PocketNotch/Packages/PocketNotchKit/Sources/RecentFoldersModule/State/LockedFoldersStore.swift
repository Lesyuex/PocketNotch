import Foundation
import Observation

/// 用户「锁定」的文件夹：以安全作用域书签持久化到 UserDefaults。
/// 锁定后文件夹不再受 Finder 最近切换次序影响，始终排在常用文件夹列表最前。
@MainActor
@Observable
public final class LockedFoldersStore {
    public private(set) var locked: [RecentFolder] = []

    private static let storageKey = "recentFolders.lockedBookmarks"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    public func isLocked(_ folder: RecentFolder) -> Bool {
        locked.contains { $0.url.standardizedFileURL == folder.url.standardizedFileURL }
    }

    public func toggle(_ folder: RecentFolder) {
        let path = folder.url.standardizedFileURL
        if isLocked(folder) {
            locked.removeAll { $0.url.standardizedFileURL == path }
        } else {
            locked.append(
                RecentFolder(url: folder.url, name: folder.name)
            )
        }
        save()
    }

    private func load() {
        let datas = defaults.array(forKey: Self.storageKey) as? [Data] ?? []
        locked = datas.compactMap(resolveBookmark)
    }

    private func save() {
        let bookmarks: [Data] = locked.compactMap { folder in
            try? folder.url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        defaults.set(bookmarks, forKey: Self.storageKey)
    }

    private func resolveBookmark(_ data: Data) -> RecentFolder? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ),
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else { return nil }

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        return RecentFolder(url: url, name: url.lastPathComponent)
    }
}