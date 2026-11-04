import Foundation

public struct RecentFolder: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    public var id: URL { url }
}

public enum FinderRecentFoldersService {
    public static let plistURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences/com.apple.finder.plist")

    public static func loadRecentFolders() -> [RecentFolder] {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil
              ),
              let topLevel = plist as? [String: Any],
              let entries = topLevel["FXRecentFolders"] as? [[String: Any]]
        else { return [] }

        return entries.compactMap(resolveEntry)
    }

    static func resolveEntry(_ entry: [String: Any]) -> RecentFolder? {
        guard let bookmark = entry["file-bookmark"] as? Data else { return nil }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else { return nil }

        let name = (entry["name"] as? String) ?? url.lastPathComponent
        return RecentFolder(url: url, name: name)
    }
}