import AVFoundation
import AppKit
import Combine
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class SettingsWallpaperPreviewModel: ObservableObject {
    // Settings only renders a small preview. Keep decoded wallpaper memory bounded
    // even when the source wallpaper is a large 5K/8K image or video frame.
    private static let previewMaximumPixelSize = 768
    private static let exportedWallpaperRootURL = URL(
        fileURLWithPath: "/var/db/Wallpapers",
        isDirectory: true
    )

    @Published private(set) var image: NSImage?

    private var capturedScreen = false
    private var loadingTask: Task<Void, Never>?

    func captureWallpaper(for screen: NSScreen?) {
        guard !capturedScreen else { return }
        capturedScreen = true

        guard let screen else {
            return
        }

        // 壁纸原图可能位于受 TCC 保护的目录（桌面/文稿/下载），读取会再次触发
        // 「文件与文件夹」系统授权弹窗。只要落在受保护目录内就一律跳过原图，
        // 直接退回系统壁纸；该判定不依赖任何授权状态，永不弹窗。
        let desktopImageURL = NSWorkspace.shared.desktopImageURL(for: screen)
        guard let desktopImageURL,
              !Self.isUnderProtectedDirectory(desktopImageURL),
              FileManager.default.isReadableFile(atPath: desktopImageURL.path) else {
            image = Self.makeExportedWallpaperPreview()
            return
        }

        if Self.isVideo(desktopImageURL) {
            let task = Task { [weak self] in
                let image = await Self.makeVideoPoster(url: desktopImageURL)
                    ?? Self.makeExportedWallpaperPreview()
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.image = image
                self.loadingTask = nil
            }
            loadingTask = task
        } else {
            image = Self.makeImagePreview(url: desktopImageURL)
                ?? Self.makeExportedWallpaperPreview()
        }
    }

    func reset() {
        loadingTask?.cancel()
        loadingTask = nil
        capturedScreen = false
        image = nil
    }

    private static func isVideo(_ url: URL) -> Bool {
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.conforms(to: .movie)
        }

        return UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true
    }

    private static func makeImagePreview(url: URL) -> NSImage? {
        autoreleasepool {
            let sourceOptions: [CFString: Any] = [
                kCGImageSourceShouldCache: false
            ]
            guard let source = CGImageSourceCreateWithURL(
                url as CFURL,
                sourceOptions as CFDictionary
            ) else {
                return nil
            }

            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: previewMaximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                thumbnailOptions as CFDictionary
            ) else {
                return nil
            }

            return NSImage(cgImage: cgImage, size: .zero)
        }
    }

    private static func isUnderProtectedDirectory(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
            .standardizedFileURL.path
        guard url.standardizedFileURL.path.hasPrefix(home) else { return false }
        let relative = String(url.standardizedFileURL.path.dropFirst(home.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let firstComponent = relative.split(separator: "/").first.map(String.init) ?? ""
        return self.protectedFolderNames.contains(firstComponent)
    }

    private static let protectedFolderNames: Set<String> = ["Desktop", "Documents", "Downloads"]

    private static func makeExportedWallpaperPreview() -> NSImage? {
        let fileManager = FileManager.default
        let directoryKeys: Set<URLResourceKey> = [.isDirectoryKey]
        guard let userDirectories = try? fileManager.contentsOfDirectory(
            at: exportedWallpaperRootURL,
            includingPropertiesForKeys: Array(directoryKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let fileKeys: Set<URLResourceKey> = [.isRegularFileKey]
        let candidates = userDirectories
            .filter {
                (try? $0.resourceValues(forKeys: directoryKeys).isDirectory) == true
            }
            .flatMap { directory -> [URL] in
                (try? fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: Array(fileKeys),
                    options: [.skipsHiddenFiles]
                )) ?? []
            }
            .filter { url in
                url.deletingPathExtension().lastPathComponent == "Wallpaper"
                    && (try? url.resourceValues(forKeys: fileKeys).isRegularFile) == true
            }

        guard candidates.count == 1 else { return nil }
        return makeImagePreview(url: candidates[0])
    }

    private static func makeVideoPoster(url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration),
              duration.isNumeric else {
            return nil
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = NSSize(
            width: previewMaximumPixelSize,
            height: previewMaximumPixelSize
        )

        let seconds = max(duration.seconds * 0.2, 0)
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        guard let result = try? await generator.image(at: time) else {
            return nil
        }

        return NSImage(cgImage: result.image, size: .zero)
    }
}
