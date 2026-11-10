import Combine
import Foundation
import PocketNotchShared

public struct AppUpdateRelease: Equatable, Sendable {
    public let tagName: String
    public let version: String
    public let name: String?
    public let releaseURL: URL

    public init(tagName: String, name: String?, releaseURL: URL) {
        self.tagName = tagName
        self.version = AppVersionComparator.normalizedVersion(tagName)
        self.name = name
        self.releaseURL = releaseURL
    }
}

public enum AppVersionComparator {
    /// 去掉版本号前缀 `v`，得到用于展示与比较的纯版本字符串。
    public static func normalizedVersion(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }
        return value
    }

    /// 语义化比较两个版本号，忽略 `v` 前缀、预发布后缀与不足的位段。
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateComponents = numericComponents(candidate)
        let currentComponents = numericComponents(current)
        guard !candidateComponents.isEmpty, !currentComponents.isEmpty else { return false }

        let count = max(candidateComponents.count, currentComponents.count)
        for index in 0..<count {
            let candidateValue = index < candidateComponents.count ? candidateComponents[index] : 0
            let currentValue = index < currentComponents.count ? currentComponents[index] : 0
            if candidateValue != currentValue {
                return candidateValue > currentValue
            }
        }
        return false
    }

    private static func numericComponents(_ raw: String) -> [Int] {
        var value = normalizedVersion(raw)
        if let suffixIndex = value.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            value = String(value[..<suffixIndex])
        }
        return value.split(separator: ".").map { component in
            Int(component.prefix(while: { $0.isNumber })) ?? 0
        }
    }
}

struct GitHubLatestRelease: Decodable {
    let tagName: String
    let name: String?
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
    }
}

@MainActor
public final class AppUpdateChecker: ObservableObject {
    public static let releasesPageURL = URL(
        string: "https://github.com/Lesyuex/PocketNotch/releases/latest"
    )!

    @Published public private(set) var availableUpdate: AppUpdateRelease?
    @Published public private(set) var isChecking = false

    private let latestReleaseAPIURL: URL
    private let currentVersionProvider: () -> String?
    private let session: URLSession
    private let minimumCheckInterval: TimeInterval
    private var lastCheckDate: Date?
    private var checkTask: Task<Void, Never>?

    public init(
        repositoryOwner: String = "Lesyuex",
        repositoryName: String = "PocketNotch",
        currentVersionProvider: @escaping () -> String? = {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        },
        minimumCheckInterval: TimeInterval = 600,
        session: URLSession = .shared
    ) {
        latestReleaseAPIURL = URL(
            string: "https://api.github.com/repos/\(repositoryOwner)/\(repositoryName)/releases/latest"
        )!
        self.currentVersionProvider = currentVersionProvider
        self.minimumCheckInterval = minimumCheckInterval
        self.session = session
    }

    deinit {
        checkTask?.cancel()
    }

    public func checkForUpdatesIfNeeded(force: Bool = false) {
        guard checkTask == nil else { return }
        if !force,
           let lastCheckDate,
           Date().timeIntervalSince(lastCheckDate) < minimumCheckInterval {
            return
        }

        checkTask = Task { [weak self] in
            guard let self else { return }
            await self.performCheck()
            self.checkTask = nil
        }
    }

    private func performCheck() async {
        isChecking = true
        defer { isChecking = false }

        var request = URLRequest(url: latestReleaseAPIURL)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PocketNotch", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                PocketNotchLog.core.error("Update check failed: unexpected HTTP response")
                return
            }

            let release = try JSONDecoder().decode(GitHubLatestRelease.self, from: data)
            lastCheckDate = Date()

            let update = AppUpdateRelease(
                tagName: release.tagName,
                name: release.name,
                releaseURL: release.htmlURL
            )
            let currentVersion = currentVersionProvider() ?? ""
            if AppVersionComparator.isNewer(update.version, than: currentVersion) {
                availableUpdate = update
                PocketNotchLog.core.info(
                    "New version available: \(update.version, privacy: .public) (current: \(currentVersion, privacy: .public))"
                )
            } else {
                availableUpdate = nil
            }
        } catch {
            PocketNotchLog.core.error(
                "Update check failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
