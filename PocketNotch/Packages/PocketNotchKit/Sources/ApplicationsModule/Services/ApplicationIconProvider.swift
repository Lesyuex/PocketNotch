import AppKit

enum ApplicationIconProvider {
    private static let cache = NSCache<NSString, NSImage>()
    private static let renderQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "PocketNotch.ApplicationIconProvider"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    /// 图标绘制在后台完成，避免翻页时数十个 `NSImage` 在主线程懒绘制造成掉帧。
    static func icon(for app: ApplicationItem, renderedSize: CGFloat = 46) async -> NSImage {
        let key = cacheKey(for: app, renderedSize: renderedSize)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        return await withCheckedContinuation { continuation in
            renderQueue.addOperation {
                let cacheKey = key as NSString
                if let cached = cache.object(forKey: cacheKey) {
                    continuation.resume(returning: cached)
                    return
                }

                let image = renderIcon(for: app, renderedSize: renderedSize)
                cache.setObject(image, forKey: cacheKey)
                continuation.resume(returning: image)
            }
        }
    }

    private static func cacheKey(for app: ApplicationItem, renderedSize: CGFloat) -> String {
        "\(app.url.path)#\(Int(renderedSize))"
    }

    private static func renderIcon(for app: ApplicationItem, renderedSize: CGFloat) -> NSImage {
        let source = NSWorkspace.shared.icon(forFile: app.url.path)
        let pixelSide = Int((renderedSize * 2).rounded())
        guard pixelSide > 0,
              let bitmap = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: pixelSide,
                  pixelsHigh: pixelSide,
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            return source
        }

        bitmap.size = NSSize(width: renderedSize, height: renderedSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.cgContext.clear(
            CGRect(x: 0, y: 0, width: pixelSide, height: pixelSide)
        )
        source.draw(
            in: CGRect(x: 0, y: 0, width: pixelSide, height: pixelSide),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: renderedSize, height: renderedSize))
        image.addRepresentation(bitmap)
        return image
    }
}
