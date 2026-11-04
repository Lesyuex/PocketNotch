import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import AgentEventModule

final class PetLibraryTests: XCTestCase {
    func testDiscoversValidPackageAndDeduplicatesByManifestID() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = root.appendingPathComponent("bundled")
        let library = root.appendingPathComponent("library")
        let codex = root.appendingPathComponent("codex")
        try makePackage(id: "same-pet", under: bundled)
        try makePackage(id: "same-pet", under: codex)

        let pets = PetLibrary(
            bundledRoot: bundled,
            libraryRoot: library,
            codexRoot: codex
        ).discover()

        XCTAssertEqual(pets.map(\.id), ["bundled:same-pet"])
        XCTAssertEqual(pets.first?.defaultAgentIDs, [.codex])
        XCTAssertEqual(pets.first?.sourceLabel, "Pocket Notch内置 · Codex内置")
    }

    func testRejectsSpritesheetOutsidePackage() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("pet")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let manifest = PetManifest(
            id: "unsafe",
            displayName: "Unsafe",
            description: nil,
            spritesheetPath: "../spritesheet.png"
        )
        try JSONEncoder().encode(manifest).write(to: package.appendingPathComponent("pet.json"))

        XCTAssertThrowsError(
            try PetLibrary(bundledRoot: root.appendingPathComponent("none"))
                .validatePackage(at: package, source: .pocketnotchLibrary)
        ) { error in
            XCTAssertEqual(error as? PetLibraryError, .invalidSpritesheetPath)
        }
    }

    func testRejectsWrongAtlasDimensions() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try makePackage(id: "small", under: root, width: 64, height: 64)

        XCTAssertThrowsError(
            try PetLibrary(bundledRoot: root.appendingPathComponent("none"))
                .validatePackage(at: package, source: .pocketnotchLibrary)
        ) { error in
            XCTAssertEqual(
                error as? PetLibraryError,
                .invalidSpritesheetDimensions(width: 64, height: 64)
            )
        }
    }

    func testImportCopiesIntoPocketNotchLibraryWithoutChangingSource() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("source")
        let package = try makePackage(id: "imported", under: sourceRoot)
        let libraryRoot = root.appendingPathComponent("library")
        let library = PetLibrary(
            bundledRoot: root.appendingPathComponent("none"),
            libraryRoot: libraryRoot,
            codexRoot: root.appendingPathComponent("codex")
        )

        let imported = try library.importPackage(at: package)

        XCTAssertEqual(imported.source, .pocketnotchLibrary)
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.appendingPathComponent("pet.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.packageURL.appendingPathComponent("pet.json").path))
    }

    func testImportsZipPackageWithNestedPackageRoot() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("source")
        let package = try makePackage(id: "zipped", under: sourceRoot)
        let archive = root.appendingPathComponent("zipped.zip")
        try createZip(from: package, at: archive)
        let libraryRoot = root.appendingPathComponent("library")
        let library = PetLibrary(
            bundledRoot: root.appendingPathComponent("none"),
            libraryRoot: libraryRoot,
            codexRoot: root.appendingPathComponent("codex")
        )

        let imported = try library.importPackage(at: archive)

        XCTAssertEqual(imported.id, "pocketnotchLibrary:zipped")
        let spritesheetURL = try XCTUnwrap(imported.spritesheetURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: spritesheetURL.path))
    }

    func testCreatesAndLoadsCustomStateAnimationPet() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("animations", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        var animations: [PetAnimationState: URL] = [:]
        for state in PetAnimationState.allCases {
            let url = sourceRoot.appendingPathComponent("\(state.rawValue).gif")
            try writeAnimatedImage(to: url)
            animations[state] = url
        }
        let libraryRoot = root.appendingPathComponent("library")
        let library = PetLibrary(
            bundledRoot: root.appendingPathComponent("none"),
            libraryRoot: libraryRoot,
            codexRoot: root.appendingPathComponent("codex")
        )

        let pet = try library.createCustomPet(displayName: "状态宠物", animationURLs: animations)

        XCTAssertNil(pet.spritesheetURL)
        XCTAssertEqual(pet.stateAnimationURLs.count, PetAnimationState.allCases.count)
        XCTAssertEqual(library.discover().first?.id, pet.id)
        let asset = try XCTUnwrap(PetAtlasAsset.load(from: pet))
        for state in PetAnimationState.allCases {
            XCTAssertEqual(asset.framesByState[state]?.count, 2)
            XCTAssertNotNil(asset.frame(for: state, elapsed: 0.15))
        }
    }

    func testAtlasLoadsEveryPetdexStateAndFrame() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try makePackage(id: "atlas", under: root)

        let asset = try XCTUnwrap(PetAtlasAsset.load(
            from: package.appendingPathComponent("spritesheet.png")
        ))

        for state in PetAnimationState.allCases {
            XCTAssertEqual(asset.framesByState[state]?.count, state.frameDurations.count)
            XCTAssertNotNil(asset.frame(for: state, elapsed: 0))
            XCTAssertNotNil(asset.frame(for: state, elapsed: 100))
        }
    }

    @MainActor
    func testPetControllerUsesAgentDefaultThenFallsBackAfterDeletion() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = root.appendingPathComponent("bundled")
        let libraryRoot = root.appendingPathComponent("library")
        try makePackage(id: "claude", under: bundled)
        let importRoot = root.appendingPathComponent("imports")
        let customPackage = try makePackage(id: "custom", under: importRoot)
        let library = PetLibrary(
            bundledRoot: bundled,
            libraryRoot: libraryRoot,
            codexRoot: root.appendingPathComponent("codex")
        )
        let suiteName = "PetLibraryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AgentActivitySettings(defaults: defaults)
        let controller = AgentPetController(settings: settings, library: library)

        XCTAssertEqual(controller.selectedPet(for: "claude")?.id, "bundled:claude")

        let imported = try controller.importPet(from: customPackage)
        controller.selectPet(id: imported.id, for: .claude)
        XCTAssertEqual(controller.selectedPet(for: "claude")?.id, "pocketnotchLibrary:custom")

        try controller.deletePet(imported)
        XCTAssertEqual(controller.selectedPet(for: "claude")?.id, "bundled:claude")
        XCTAssertNil(settings.petBindings["claude"])
    }

    @MainActor
    func testPetControllerUsesAgentInstallPetThenKunLikeFallback() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = root.appendingPathComponent("bundled")
        let codex = root.appendingPathComponent("codex")
        try makePackage(id: "kun-like", under: bundled)
        try makePackage(id: "codex-pet", under: codex)
        let library = PetLibrary(
            bundledRoot: bundled,
            libraryRoot: root.appendingPathComponent("library"),
            codexRoot: codex,
            claudeRoot: root.appendingPathComponent("claude"),
            geminiRoot: root.appendingPathComponent("gemini")
        )
        let suiteName = "PetLibraryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = AgentPetController(
            settings: AgentActivitySettings(defaults: defaults),
            library: library
        )

        XCTAssertEqual(controller.selectedPet(for: "codex")?.manifest.id, "codex-pet")
        XCTAssertEqual(controller.selectedPet(for: "claude")?.manifest.id, "kun-like")
        XCTAssertEqual(controller.selectedPet(for: "gemini")?.manifest.id, "kun-like")
    }

    @discardableResult
    private func makePackage(
        id: String,
        under root: URL,
        width: Int = 1536,
        height: Int = 1872
    ) throws -> URL {
        let package = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let manifest = PetManifest(
            id: id,
            displayName: id,
            description: nil,
            spritesheetPath: "spritesheet.png"
        )
        try JSONEncoder().encode(manifest).write(to: package.appendingPathComponent("pet.json"))
        try writeImage(width: width, height: height, to: package.appendingPathComponent("spritesheet.png"))
        return package
    }

    private func writeImage(width: Int, height: Int, to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func writeAnimatedImage(to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            2,
            nil
        ))
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        for color in [CGColor(red: 1, green: 0, blue: 0, alpha: 1), CGColor(red: 0, green: 1, blue: 0, alpha: 1)] {
            let context = try XCTUnwrap(CGContext(
                data: nil,
                width: 32,
                height: 32,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(color)
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            let image = try XCTUnwrap(context.makeImage())
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]
            ] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func createZip(from packageURL: URL, at archiveURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", packageURL.path, archiveURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PetLibraryTests-\(UUID().uuidString)", isDirectory: true)
    }
}
