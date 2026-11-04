import AppKit
import Foundation

/// 读取并缓存播放应用的系统原始图标；圆形裁剪等视觉策略由视图层决定。
class ApplicationIconProvider {
    private var cache: (pid: Int32, data: Data)?

    func iconData(forPID pid: Int32?) -> Data? {
        guard let pid, pid > 0 else { return nil }
        if let cache, cache.pid == pid {
            return cache.data
        }
        guard let app = NSRunningApplication(processIdentifier: pid),
              let icon = app.icon,
              let data = Self.transparentPNGData(from: icon) else {
            return nil
        }
        cache = (pid, data)
        return data
    }

    private static func transparentPNGData(from icon: NSImage) -> Data? {
        let pixelSize = 256
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.cgContext.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        icon.draw(
            in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }

    func reset() {
        cache = nil
    }
}
