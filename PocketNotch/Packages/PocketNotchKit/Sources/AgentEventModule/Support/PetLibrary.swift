import CoreGraphics
import Foundation
import ImageIO

public enum PetLibraryError: LocalizedError, Equatable {
    case missingManifest
    case invalidManifest
    case invalidIdentifier
    case invalidSpritesheetPath
    case missingSpritesheet
    case invalidSpritesheet
    case spritesheetTooLarge
    case invalidSpritesheetDimensions(width: Int, height: Int)
    case missingStateAnimations
    case invalidStateAnimation(String)
    case stateAnimationNotAnimated(String)
    case packageAlreadyExists(String)
    case cannotDeleteExternalPet
    case unsupportedImport
    case invalidArchive
    case archiveTooLarge
    case unsafeArchive
    case archiveContainsMultiplePackages

    public var errorDescription: String? {
        switch self {
        case .missingManifest: "所选文件夹中没有 pet.json"
        case .invalidManifest: "pet.json 格式无效"
        case .invalidIdentifier: "宠物 ID 无效"
        case .invalidSpritesheetPath: "宠物图集路径无效"
        case .missingSpritesheet: "找不到宠物图集"
        case .invalidSpritesheet: "宠物图集不是有效图片"
        case .spritesheetTooLarge: "宠物图集不能超过 64 MB"
        case .invalidSpritesheetDimensions(let width, let height):
            "宠物图集尺寸为 \(width)×\(height)，需要 1536×1872"
        case .missingStateAnimations: "请为每个宠物状态设置动图"
        case .invalidStateAnimation(let state): "“\(state)”状态的动图无效"
        case .stateAnimationNotAnimated(let state): "“\(state)”状态需要选择包含多个画面的动图"
        case .packageAlreadyExists(let name): "宠物“\(name)”已经存在"
        case .cannotDeleteExternalPet: "只能删除导入到 PocketNotch 的宠物"
        case .unsupportedImport: "请选择 Petdex 文件夹或 ZIP 压缩包"
        case .invalidArchive: "ZIP 压缩包无法解压"
        case .archiveTooLarge: "ZIP 压缩包内容过大"
        case .unsafeArchive: "ZIP 压缩包包含不安全的文件"
        case .archiveContainsMultiplePackages: "ZIP 压缩包中只能包含一个宠物"
        }
    }
}

public final class PetLibrary: @unchecked Sendable {
    public static let atlasSize = CGSize(width: 1536, height: 1872)
    public static let cellSize = CGSize(width: 192, height: 208)
    private static let maximumArchiveSize = 64 * 1_024 * 1_024
    private static let maximumExtractedSize = 128 * 1_024 * 1_024

    private let fileManager: FileManager
    private let bundledRoots: [URL]
    private let libraryRoot: URL
    private let agentRoots: [AgentIdentity: URL]

    public init(
        fileManager: FileManager = .default,
        bundledRoot: URL? = nil,
        libraryRoot: URL? = nil,
        codexRoot: URL? = nil,
        claudeRoot: URL? = nil,
        geminiRoot: URL? = nil
    ) {
        self.fileManager = fileManager
        if let bundledRoot {
            bundledRoots = [bundledRoot]
        } else {
            bundledRoots = [Bundle.main.resourceURL, Bundle.module.resourceURL]
                .compactMap { $0?.appendingPathComponent("DefaultPets", isDirectory: true) }
        }
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.libraryRoot = libraryRoot
            ?? applicationSupport
                .appendingPathComponent("PocketNotch", isDirectory: true)
                .appendingPathComponent("Pets", isDirectory: true)
        let home = fileManager.homeDirectoryForCurrentUser
        agentRoots = [
            .claude: claudeRoot ?? home
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("pets", isDirectory: true),
            .codex: codexRoot ?? home
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("pets", isDirectory: true),
            .gemini: geminiRoot ?? home
                .appendingPathComponent(".gemini", isDirectory: true)
                .appendingPathComponent("pets", isDirectory: true),
        ]
    }

    public func discover() -> [PetDescriptor] {
        var result: [PetDescriptor] = []
        for bundledRoot in bundledRoots {
            result += discoverPackages(in: bundledRoot, source: .bundled)
        }
        result += discoverPackages(in: libraryRoot, source: .pocketnotchLibrary)
        for agent in AgentIdentity.allCases {
            guard let root = agentRoots[agent] else { continue }
            result += discoverPackages(in: root, source: externalSource(for: agent))
        }
        return deduplicated(result).sorted {
            if $0.source.rawValue != $1.source.rawValue {
                return sourceOrder($0.source) < sourceOrder($1.source)
            }
            return $0.manifest.displayName.localizedCaseInsensitiveCompare(
                $1.manifest.displayName
            ) == .orderedAscending
        }
    }

    @discardableResult
    public func importPackage(at packageURL: URL) throws -> PetDescriptor {
        let values = try? packageURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if values?.isDirectory == true {
            return try importDirectory(at: packageURL)
        }

        guard packageURL.pathExtension.caseInsensitiveCompare("zip") == .orderedSame else {
            throw PetLibraryError.unsupportedImport
        }
        if let fileSize = values?.fileSize, fileSize > Self.maximumArchiveSize {
            throw PetLibraryError.archiveTooLarge
        }

        let extractionRoot = fileManager.temporaryDirectory
            .appendingPathComponent("PocketNotchPetImport-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: extractionRoot) }

        try extractArchive(at: packageURL, to: extractionRoot)
        let extractedPackage = try packageRoot(in: extractionRoot)
        return try importDirectory(at: extractedPackage)
    }

    @discardableResult
    public func createCustomPet(
        displayName: String,
        animationURLs: [PetAnimationState: URL]
    ) throws -> PetDescriptor {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw PetLibraryError.invalidIdentifier }
        guard PetAnimationState.allCases.allSatisfy({ animationURLs[$0] != nil }) else {
            throw PetLibraryError.missingStateAnimations
        }

        try fileManager.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        let identifier = "custom-\(UUID().uuidString.lowercased())"
        let temporary = libraryRoot.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
        let destination = libraryRoot.appendingPathComponent(identifier, isDirectory: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)

        do {
            var paths: [String: String] = [:]
            for state in PetAnimationState.allCases {
                guard let sourceURL = animationURLs[state] else {
                    throw PetLibraryError.missingStateAnimations
                }
                try validateAnimatedImage(at: sourceURL, state: state)
                let fileExtension = sourceURL.pathExtension.isEmpty ? "gif" : sourceURL.pathExtension.lowercased()
                let filename = "\(state.rawValue).\(fileExtension)"
                try fileManager.copyItem(at: sourceURL, to: temporary.appendingPathComponent(filename))
                paths[state.rawValue] = filename
            }

            let manifest = PetManifest(
                id: identifier,
                displayName: trimmedName,
                description: "在 PocketNotch 中自定义的状态动图宠物",
                stateAnimationPaths: paths
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(
                to: temporary.appendingPathComponent("pet.json"),
                options: .atomic
            )
            _ = try validatePackage(at: temporary, source: .pocketnotchLibrary)
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }

        return try validatePackage(at: destination, source: .pocketnotchLibrary)
    }

    private func importDirectory(at packageURL: URL) throws -> PetDescriptor {
        let descriptor = try validatePackage(at: packageURL, source: .pocketnotchLibrary)
        try fileManager.createDirectory(at: libraryRoot, withIntermediateDirectories: true)

        let folderName = normalizedIdentifier(descriptor.manifest.id)
        guard !folderName.isEmpty else { throw PetLibraryError.invalidIdentifier }
        let destination = libraryRoot.appendingPathComponent(folderName, isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw PetLibraryError.packageAlreadyExists(descriptor.manifest.displayName)
        }

        let temporary = libraryRoot.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.copyItem(at: packageURL, to: temporary)
            _ = try validatePackage(at: temporary, source: .pocketnotchLibrary)
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
        return try validatePackage(at: destination, source: .pocketnotchLibrary)
    }

    private func extractArchive(at archiveURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, destinationURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw PetLibraryError.invalidArchive
        }
        guard process.terminationStatus == 0 else {
            throw PetLibraryError.invalidArchive
        }
    }

    private func packageRoot(in extractionRoot: URL) throws -> URL {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: extractionRoot,
            includingPropertiesForKeys: keys
        ) else {
            throw PetLibraryError.invalidArchive
        }

        var manifestURLs: [URL] = []
        var extractedSize = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true else {
                throw PetLibraryError.unsafeArchive
            }
            if values.isRegularFile == true {
                extractedSize += values.fileSize ?? 0
                guard extractedSize <= Self.maximumExtractedSize else {
                    throw PetLibraryError.archiveTooLarge
                }
                if url.lastPathComponent == "pet.json" {
                    manifestURLs.append(url)
                }
            }
        }

        guard !manifestURLs.isEmpty else {
            throw PetLibraryError.missingManifest
        }
        guard manifestURLs.count == 1, let manifestURL = manifestURLs.first else {
            throw PetLibraryError.archiveContainsMultiplePackages
        }
        return manifestURL.deletingLastPathComponent()
    }

    public func delete(_ pet: PetDescriptor) throws {
        guard pet.source == .pocketnotchLibrary else {
            throw PetLibraryError.cannotDeleteExternalPet
        }
        let resolvedRoot = libraryRoot.resolvingSymlinksInPath().standardizedFileURL
        let resolvedPackage = pet.packageURL.resolvingSymlinksInPath().standardizedFileURL
        guard isDescendant(resolvedPackage, of: resolvedRoot) else {
            throw PetLibraryError.cannotDeleteExternalPet
        }
        try fileManager.removeItem(at: resolvedPackage)
    }

    public func validatePackage(
        at packageURL: URL,
        source: PetSource
    ) throws -> PetDescriptor {
        let manifestURL = packageURL.appendingPathComponent("pet.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw PetLibraryError.missingManifest
        }
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PetManifest.self, from: data) else {
            throw PetLibraryError.invalidManifest
        }
        let normalizedID = normalizedIdentifier(manifest.id)
        guard !normalizedID.isEmpty,
              normalizedID == manifest.id.lowercased() else {
            throw PetLibraryError.invalidIdentifier
        }

        let resolvedPackage = packageURL.resolvingSymlinksInPath().standardizedFileURL
        let spritesheetURL: URL?
        var stateAnimationURLs: [PetAnimationState: URL] = [:]

        if let relativePath = manifest.spritesheetPath {
            guard !relativePath.isEmpty,
                  !NSString(string: relativePath).isAbsolutePath else {
                throw PetLibraryError.invalidSpritesheetPath
            }
            let resolvedURL = packageURL
                .appendingPathComponent(relativePath)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            guard isDescendant(resolvedURL, of: resolvedPackage) else {
                throw PetLibraryError.invalidSpritesheetPath
            }
            guard fileManager.fileExists(atPath: resolvedURL.path) else {
                throw PetLibraryError.missingSpritesheet
            }
            if let fileSize = try? resolvedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               fileSize > 64 * 1_024 * 1_024 {
                throw PetLibraryError.spritesheetTooLarge
            }
            guard let sourceImage = CGImageSourceCreateWithURL(resolvedURL as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(sourceImage, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else {
                throw PetLibraryError.invalidSpritesheet
            }
            guard width == Int(Self.atlasSize.width), height == Int(Self.atlasSize.height) else {
                throw PetLibraryError.invalidSpritesheetDimensions(width: width, height: height)
            }
            spritesheetURL = resolvedURL
        } else {
            spritesheetURL = nil
            guard let paths = manifest.stateAnimationPaths,
                  PetAnimationState.allCases.allSatisfy({ paths[$0.rawValue] != nil }) else {
                throw PetLibraryError.missingStateAnimations
            }
            for state in PetAnimationState.allCases {
                guard let relativePath = paths[state.rawValue],
                      !relativePath.isEmpty,
                      !NSString(string: relativePath).isAbsolutePath else {
                    throw PetLibraryError.invalidStateAnimation(state.displayName)
                }
                let resolvedURL = packageURL
                    .appendingPathComponent(relativePath)
                    .resolvingSymlinksInPath()
                    .standardizedFileURL
                guard isDescendant(resolvedURL, of: resolvedPackage),
                      fileManager.fileExists(atPath: resolvedURL.path) else {
                    throw PetLibraryError.invalidStateAnimation(state.displayName)
                }
                try validateAnimatedImage(at: resolvedURL, state: state)
                stateAnimationURLs[state] = resolvedURL
            }
        }

        return PetDescriptor(
            id: "\(source.rawValue):\(normalizedID)",
            manifest: manifest,
            packageURL: packageURL,
            spritesheetURL: spritesheetURL,
            stateAnimationURLs: stateAnimationURLs,
            source: source,
            sources: [source],
            defaultAgentIDs: Set(source.agent.map { [$0] } ?? [])
        )
    }

    private func validateAnimatedImage(at url: URL, state: PetAnimationState) throws {
        if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           fileSize > 64 * 1_024 * 1_024 {
            throw PetLibraryError.spritesheetTooLarge
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw PetLibraryError.invalidStateAnimation(state.displayName)
        }
        guard CGImageSourceGetCount(source) > 1 else {
            throw PetLibraryError.stateAnimationNotAnimated(state.displayName)
        }
    }

    private func discoverPackages(in root: URL, source: PetSource) -> [PetDescriptor] {
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return children.compactMap { try? validatePackage(at: $0, source: source) }
    }

    private func normalizedIdentifier(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.path.hasPrefix(rootPath)
    }

    private func sourceOrder(_ source: PetSource) -> Int {
        switch source {
        case .bundled: 0
        case .pocketnotchLibrary: 1
        case .claudeExternal: 2
        case .codexExternal: 3
        case .geminiExternal: 4
        }
    }

    private func externalSource(for agent: AgentIdentity) -> PetSource {
        switch agent {
        case .claude: .claudeExternal
        case .codex: .codexExternal
        case .gemini: .geminiExternal
        }
    }

    private func deduplicated(_ pets: [PetDescriptor]) -> [PetDescriptor] {
        let grouped = Dictionary(grouping: pets) { normalizedIdentifier($0.manifest.id) }
        return grouped.values.compactMap { duplicates in
            guard let canonical = duplicates.min(by: {
                sourceOrder($0.source) < sourceOrder($1.source)
            }) else { return nil }
            let defaultAgentIDs = duplicates.reduce(into: Set<AgentIdentity>()) {
                $0.formUnion($1.defaultAgentIDs)
            }
            let sources = duplicates.reduce(into: Set<PetSource>()) {
                $0.formUnion($1.sources)
            }
            return PetDescriptor(
                id: canonical.id,
                manifest: canonical.manifest,
                packageURL: canonical.packageURL,
                spritesheetURL: canonical.spritesheetURL,
                stateAnimationURLs: canonical.stateAnimationURLs,
                source: canonical.source,
                sources: sources,
                defaultAgentIDs: defaultAgentIDs
            )
        }
    }
}
