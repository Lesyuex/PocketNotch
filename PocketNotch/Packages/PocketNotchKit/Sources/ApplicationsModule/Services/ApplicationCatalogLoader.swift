import Foundation

enum ApplicationCatalogLoader {
    static func load() -> [ApplicationItem] {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
        ]
        var applicationsByURL: [URL: ApplicationItem] = [:]

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
                applicationsByURL[resolvedURL] = ApplicationItem(
                    url: resolvedURL,
                    name: applicationName(at: resolvedURL)
                )
            }
        }

        return applicationsByURL.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func applicationName(at url: URL) -> String {
        if let bundle = Bundle(url: url),
           let displayName = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle.localizedInfoDictionary?["CFBundleName"] as? String,
           !displayName.isEmpty {
            return displayName
        }
        return url.deletingPathExtension().lastPathComponent
    }
}
