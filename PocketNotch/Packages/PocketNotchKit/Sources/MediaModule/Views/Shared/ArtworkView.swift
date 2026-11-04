import AppKit
import ImageIO
import SwiftUI

struct ArtworkView: View {
    let data: Data?
    let fallbackSystemName: String
    let size: CGFloat
    var height: CGFloat?
    var cornerRadius: CGFloat = 8
    var maximumTransformScale: CGFloat = 1
    // 正圆裁剪：compact 前导区域使用（播放时旋转，圆形轮廓不随旋转扫动）。其他态默认圆角矩形。
    var circular: Bool = false
    @Environment(\.displayScale) private var displayScale

    private var renderedHeight: CGFloat { height ?? size }

    var body: some View {
        Group {
            if let data,
               let image = ArtworkImageCache.shared.image(
                   from: data,
                   displaySize: max(size, renderedHeight),
                   displayScale: displayScale,
                   maximumTransformScale: maximumTransformScale
               ) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
            } else {
                fallback
            }
        }
        .frame(width: size, height: renderedHeight)
        .clipShape(clipShape)
        .contentShape(clipShape)
    }

    private var fallback: some View {
        Image(systemName: fallbackSystemName)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: size, height: renderedHeight)
            .background(.white.opacity(0.1))
    }

    private var clipShape: AnyShape {
        if circular {
            return AnyShape(Circle())
        }
        return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private final class ArtworkImageCache {
    static let shared = ArtworkImageCache()

    private let cache = NSCache<ArtworkImageCacheKey, NSImage>()

    private init() {
        // Album artwork is decoded into much larger pixel buffers than its Data payload.
        // Keep this cache small so switching tracks cannot retain a large working set.
        cache.countLimit = 24
        cache.totalCostLimit = 16 * 1024 * 1024
    }

    func image(
        from data: Data,
        displaySize: CGFloat,
        displayScale: CGFloat,
        maximumTransformScale: CGFloat
    ) -> NSImage? {
        let normalizedDisplaySize = max(displaySize, 1)
        let normalizedDisplayScale = max(displayScale, 1)
        let normalizedTransformScale = max(maximumTransformScale, 1)
        let maxPixelSize = max(
            1,
            Int(ceil(normalizedDisplaySize * normalizedDisplayScale * normalizedTransformScale))
        )
        let key = ArtworkImageCacheKey(
            dataCount: data.count,
            dataHash: data.hashValue,
            maxPixelSize: maxPixelSize
        )
        if let image = cache.object(forKey: key) {
            return image
        }
        guard let image = downsampledImage(
            from: data,
            maxPixelSize: maxPixelSize,
            displayScale: normalizedDisplayScale
        ) else {
            return nil
        }
        cache.setObject(image, forKey: key, cost: image.pixelCost)
        return image
    }

    private func downsampledImage(
        from data: Data,
        maxPixelSize: Int,
        displayScale: CGFloat
    ) -> NSImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return NSImage(data: data)
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return NSImage(data: data)
        }
        let pointSize = CGSize(
            width: CGFloat(cgImage.width) / displayScale,
            height: CGFloat(cgImage.height) / displayScale
        )
        return NSImage(cgImage: cgImage, size: pointSize)
    }
}

private final class ArtworkImageCacheKey: NSObject {
    private let dataCount: Int
    private let dataHash: Int
    private let maxPixelSize: Int

    init(dataCount: Int, dataHash: Int, maxPixelSize: Int) {
        self.dataCount = dataCount
        self.dataHash = dataHash
        self.maxPixelSize = maxPixelSize
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(dataCount)
        hasher.combine(dataHash)
        hasher.combine(maxPixelSize)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ArtworkImageCacheKey else { return false }
        return dataCount == other.dataCount
            && dataHash == other.dataHash
            && maxPixelSize == other.maxPixelSize
    }
}

private extension NSImage {
    var pixelCost: Int {
        guard let representation = representations.first else { return 1 }
        return max(1, representation.pixelsWide * representation.pixelsHigh * 4)
    }
}
