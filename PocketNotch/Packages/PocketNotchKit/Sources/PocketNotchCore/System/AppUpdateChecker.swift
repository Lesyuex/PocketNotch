import AppKit
import Combine
import CryptoKit
import Foundation
import PocketNotchShared

public struct AppUpdateAsset: Equatable, Sendable {
    public let name: String
    public let downloadURL: URL
    public let digest: String?

    public init(name: String, downloadURL: URL, digest: String?) {
        self.name = name
        self.downloadURL = downloadURL
        self.digest = digest
    }
}

public struct AppUpdateRelease: Equatable, Sendable {
    public let tagName: String
    public let version: String
    public let name: String?
    public let releaseURL: URL
    public let dmgAsset: AppUpdateAsset?
    public let checksumAsset: AppUpdateAsset?

    public init(
        tagName: String,
        name: String?,
        releaseURL: URL,
        dmgAsset: AppUpdateAsset? = nil,
        checksumAsset: AppUpdateAsset? = nil
    ) {
        self.tagName = tagName
        self.version = AppVersionComparator.normalizedVersion(tagName)
        self.name = name
        self.releaseURL = releaseURL
        self.dmgAsset = dmgAsset
        self.checksumAsset = checksumAsset
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

struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case digest
    }
}

struct GitHubLatestRelease: Decodable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        assets = try container.decodeIfPresent([GitHubReleaseAsset].self, forKey: .assets) ?? []
    }
}

@MainActor
public final class AppUpdateChecker: ObservableObject {
    public static let releasesPageURL = URL(
        string: "https://github.com/Lesyuex/PocketNotch/releases/latest"
    )!

    @Published public private(set) var availableUpdate: AppUpdateRelease?
    @Published public private(set) var isChecking = false
    @Published public private(set) var lastCheckError: String?

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

    public func checkForUpdates() async {
        if let checkTask {
            await checkTask.value
        } else {
            await performCheck()
        }
    }

    private func performCheck() async {
        isChecking = true
        lastCheckError = nil
        defer { isChecking = false }

        var request = URLRequest(url: latestReleaseAPIURL)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PocketNotch", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200..<300).contains(statusCode) else {
                let message = "unexpected HTTP response: \(statusCode)"
                lastCheckError = message
                PocketNotchLog.core.error("Update check failed: \(message, privacy: .public)")
                return
            }

            let release = try JSONDecoder().decode(GitHubLatestRelease.self, from: data)
            lastCheckDate = Date()

            let dmgAsset = release.assets.first {
                $0.name.hasSuffix(".dmg") && !$0.name.contains("-universal")
            } ?? release.assets.first { $0.name.hasSuffix(".dmg") }
            let checksumAsset = dmgAsset.flatMap { dmg in
                release.assets.first { $0.name == dmg.name + ".sha256" }
            }
            let update = AppUpdateRelease(
                tagName: release.tagName,
                name: release.name,
                releaseURL: release.htmlURL,
                dmgAsset: dmgAsset.map {
                    AppUpdateAsset(name: $0.name, downloadURL: $0.browserDownloadURL, digest: $0.digest)
                },
                checksumAsset: checksumAsset.map {
                    AppUpdateAsset(name: $0.name, downloadURL: $0.browserDownloadURL, digest: $0.digest)
                }
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
            lastCheckError = error.localizedDescription
            PocketNotchLog.core.error(
                "Update check failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

public enum AppUpdaterPhase: Equatable {
    case idle
    case downloading(progress: Double?)
    case verifying
    case installing
    case installed
    case failed(String)
}

private final class AppUpdaterDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let fileManager: FileManager
    private let progressHandler: @Sendable (Double?) -> Void
    private let completion: @Sendable (Result<Void, Error>) -> Void
    private var session: URLSession?
    private var isFinished = false

    init(
        destination: URL,
        fileManager: FileManager,
        progressHandler: @escaping @Sendable (Double?) -> Void,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        self.destination = destination
        self.fileManager = fileManager
        self.progressHandler = progressHandler
        self.completion = completion
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let progress: Double? = totalBytesExpectedToWrite > 0
            ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
            : nil
        progressHandler(progress)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: location, to: destination)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        finish(.failure(error))
    }

    func attach(_ session: URLSession) {
        self.session = session
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !isFinished else { return }
        isFinished = true
        session?.finishTasksAndInvalidate()
        completion(result)
    }
}

@MainActor
public final class AppUpdater: ObservableObject {
    @Published public private(set) var phase: AppUpdaterPhase = .idle

    private let session: URLSession
    private let fileManager: FileManager
    private let applicationURL: URL
    private var updateTask: Task<Void, Never>?

    public init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        applicationURL: URL? = nil
    ) {
        self.session = session
        self.fileManager = fileManager
        self.applicationURL = applicationURL ?? Bundle.main.bundleURL
    }

    deinit {
        updateTask?.cancel()
    }

    public var isBusy: Bool {
        switch phase {
        case .downloading, .verifying, .installing, .installed:
            true
        case .idle, .failed:
            false
        }
    }

    public func update(to release: AppUpdateRelease) {
        guard !isBusy, let asset = release.dmgAsset else { return }
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            guard let self else { return }
            await self.performUpdate(release: release, asset: asset)
            self.updateTask = nil
        }
    }

    public func reset() {
        updateTask?.cancel()
        updateTask = nil
        phase = .idle
    }

    private func performUpdate(release: AppUpdateRelease, asset: AppUpdateAsset) async {
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("PocketNotchUpdate-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: workspace) }

            phase = .downloading(progress: 0)
            let dmgURL = workspace.appendingPathComponent(asset.name)
            try await download(asset.downloadURL, to: dmgURL)

            var expectedDigest = asset.digest?
                .replacingOccurrences(of: "sha256:", with: "")
                .lowercased()
            if let checksum = release.checksumAsset {
                let (downloadedChecksum, _) = try await session.download(from: checksum.downloadURL)
                let text = try String(contentsOf: downloadedChecksum, encoding: .utf8)
                expectedDigest = text.split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased()
            }
            guard let expectedDigest else { throw UpdateError.missingChecksum }

            phase = .verifying
            let digest = SHA256.hash(data: try Data(contentsOf: dmgURL))
                .map { String(format: "%02x", $0) }
                .joined()
            guard digest == expectedDigest else { throw UpdateError.checksumMismatch }

            phase = .installing
            let mountPoint = workspace.appendingPathComponent("Volume", isDirectory: true)
            try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
            try run("/usr/bin/hdiutil", [
                "attach", "-nobrowse", "-noautoopen", "-mountpoint", mountPoint.path, dmgURL.path
            ])
            defer { _ = try? run("/usr/bin/hdiutil", ["detach", mountPoint.path]) }

            let packagedApp = mountPoint.appendingPathComponent("PocketNotch.app")
            guard fileManager.fileExists(atPath: packagedApp.path) else {
                throw UpdateError.appNotFound
            }

            let backupURL = applicationURL.deletingLastPathComponent()
                .appendingPathComponent("PocketNotch.previous-\(UUID().uuidString).app")
            if fileManager.fileExists(atPath: applicationURL.path) {
                try fileManager.moveItem(at: applicationURL, to: backupURL)
            }
            do {
                try run("/usr/bin/ditto", [packagedApp.path, applicationURL.path])
                _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", applicationURL.path])
            } catch {
                if fileManager.fileExists(atPath: backupURL.path) {
                    try? fileManager.removeItem(at: applicationURL)
                    try? fileManager.moveItem(at: backupURL, to: applicationURL)
                }
                throw error
            }
            try? fileManager.removeItem(at: backupURL)

            phase = .installed
            PocketNotchLog.core.info("Update installed: \(release.version, privacy: .public)")
        } catch {
            let message = error.localizedDescription
            phase = .failed(message)
            PocketNotchLog.core.error("Update failed: \(message, privacy: .public)")
        }
    }

    private func download(_ url: URL, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = AppUpdaterDownloadDelegate(
                destination: destination,
                fileManager: fileManager,
                progressHandler: { [weak self] progress in
                    Task { @MainActor in
                        guard let self, case .downloading = self.phase else { return }
                        self.phase = .downloading(progress: progress)
                    }
                },
                completion: { result in
                    continuation.resume(with: result)
                }
            )
            let downloadSession = URLSession(
                configuration: session.configuration,
                delegate: delegate,
                delegateQueue: nil
            )
            delegate.attach(downloadSession)
            downloadSession.downloadTask(with: url).resume()
        }
    }

    private enum UpdateError: LocalizedError {
        case missingChecksum
        case checksumMismatch
        case appNotFound
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingChecksum:
                "校验信息缺失"
            case .checksumMismatch:
                "校验失败，下载文件可能已损坏"
            case .appNotFound:
                "更新包中未找到应用"
            case .commandFailed(let message):
                "系统命令执行失败：\(message)"
            }
        }
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.commandFailed(String(data: data, encoding: .utf8) ?? executable)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
