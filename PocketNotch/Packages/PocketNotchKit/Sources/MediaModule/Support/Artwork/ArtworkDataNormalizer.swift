import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Keeps artwork payloads bounded before they enter long-lived media snapshots.
/// MediaRemote may return the original album image, which can be many megabytes.
enum ArtworkDataNormalizer {
    /// 归一化后的最大边长。实际显示的最大封面是 Now Page 卡片 48pt@3x = 144px，
    /// 256 已留足余量：纹理远小于显示栅格时，旋转逐帧重采样不会漏采样，
    /// 边缘不会闪出像素点（原 768 是需求的 5 倍多，纯属浪费）。
    private static let maximumPixelSize = 256
    /// 超过这个字节数才归一化。阈值要覆盖「像素超限但字节不高」的情况：
    /// 一张 1000px / 450KB 的封面若绕过归一化，仍会以大纹理进旋转层而闪烁。
    private static let maximumInputBytes = 200 * 1024
    private static let compressionQuality: CGFloat = 0.84

    private static let cache = ArtworkNormalizationCache()

    /// MediaRemote 对同一首歌会高频重发字典；超阈值的封面每次都走
    /// `CGImageSource` 解码再 JPEG 重编码。按原始字节内容判重，命中时直接
    /// 复用上一次的归一化结果 —— 每张不同的封面只会真正处理一次。
    static func normalized(_ data: Data?) -> Data? {
        guard let data, !data.isEmpty else { return nil }
        guard data.count > maximumInputBytes else { return data }
        if let normalized = cache.normalizedData(for: data) {
            return normalized
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary
              ) else {
            return data
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return data
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return data }
        let normalized = output as Data
        cache.store(normalized, for: data)
        return normalized
    }
}

/// 单槽归一化缓存：只保留最近一张大封面，按原始字节内容判重。
/// 命中复用让 `info.artworkData`、`displayArtwork`、`lastPaletteArtwork`
/// 指向同一份归一化缓冲，避免同一首歌反复持有多份大对象。
private final class ArtworkNormalizationCache: @unchecked Sendable {
    private let lock = NSLock()
    private var lastRawData: Data?
    private var lastNormalizedData: Data?

    func normalizedData(for rawData: Data) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let lastRawData, lastRawData == rawData else { return nil }
        return lastNormalizedData
    }

    func store(_ normalized: Data, for rawData: Data) {
        lock.lock()
        defer { lock.unlock() }
        lastRawData = rawData
        lastNormalizedData = normalized
    }
}
