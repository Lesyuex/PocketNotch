import AppKit
import ImageIO
import SwiftUI

/// 单根频柱的纵向渐变：顶部、底部分别来自封面对应色带的协调色。
public struct SpectrumBarGradient: Equatable {
    public let top: Color
    public let bottom: Color

    public init(top: Color, bottom: Color) { self.top = top; self.bottom = bottom }
}

/// 封面取色器：吃封面 Data，吐 2-3 个用于旋律条渐变的主色。
/// 纯图像处理，缩到小图采样（快），量化分桶挑最鲜明的主色。
/// 只在封面变化时调一次（由 ViewModel 把关），绝不每帧算——守耗电铁律。
enum ArtworkPalette {
    /// 返回按视觉权重排序的主色（最多 3 个）。取不到色 → 空数组（调用方回落白色）。
    static func colors(from data: Data?, maxCount: Int = 3) -> [Color] {
        guard let data, let image = NSImage(data: data),
              let rgba = downsampledRGBA(image, side: 24) else {
            return []
        }

        // 量化到粗网格分桶，累计每桶像素数与平均色，挑鲜明且占比大的桶。
        var buckets: [Int: Bucket] = [:]
        var i = 0
        while i + 3 < rgba.count {
            let r = Float(rgba[i]) / 255
            let g = Float(rgba[i + 1]) / 255
            let b = Float(rgba[i + 2]) / 255
            let a = Float(rgba[i + 3]) / 255
            i += 4
            guard a > 0.35 else { continue }               // 跳过透明像素
            let (h, s, v) = hsv(r, g, b)
            guard v > 0.12 else { continue }               // 跳过近黑（背景常见）

            // 桶 key：色相 12 档 + 明度 3 档，让不同颜色分开、明暗归并
            let key = Int(h * 12) * 10 + Int(v * 3)
            var bucket = buckets[key] ?? Bucket()
            bucket.add(r: r, g: g, b: b, saturation: s, value: v)
            buckets[key] = bucket
        }
        guard !buckets.isEmpty else { return [] }

        // 权重 = 像素占比 × (0.8 + 饱和度) → 偏爱鲜明色，但不忽略占大面积的低饱和主色
        let ranked = buckets.values
            .map { (color: $0.averageColor, weight: Float($0.count) * (0.8 + $0.avgSaturation)) }
            .sorted { $0.weight > $1.weight }

        let picked = ranked.prefix(maxCount).map { $0.color }
        if picked.count >= 2 { return picked }

        // 只有单一主色 → 造明暗变体，仍能渐变
        if let base = picked.first {
            return [base.adjusted(brightness: 1.25), base, base.adjusted(brightness: 0.65)]
        }
        return []
    }

    private struct Bucket {
        var count = 0
        var rSum: Float = 0, gSum: Float = 0, bSum: Float = 0, sSum: Float = 0
        mutating func add(r: Float, g: Float, b: Float, saturation: Float, value: Float) {
            count += 1; rSum += r; gSum += g; bSum += b; sSum += saturation
        }
        var avgSaturation: Float { count > 0 ? sSum / Float(count) : 0 }
        var averageColor: Color {
            let n = Float(max(count, 1))
            return Color(red: Double(rSum / n), green: Double(gSum / n), blue: Double(bSum / n))
        }
    }

    /// 封面右缘取色：信息区向右侧延伸时用，保证色场与封面的衔接处颜色连续。
    /// 采样最右 1/3 列的平均色；封面中央多扎眼都没关系，只关心边缘到底长什么样。
    /// 返回 [边缘平均色, 稍暗变体]，取不到 → 空数组。
    static func edgeColors(from data: Data?, maxCount: Int = 2) -> [Color] {
        guard let data, let image = NSImage(data: data),
              let rgba = downsampledRGBA(image, side: 24) else {
            return []
        }

        let side = 24
        let edgeStart = side * 2 / 3
        var rSum: Float = 0, gSum: Float = 0, bSum: Float = 0
        var count = 0
        var y = 0
        while y < side {
            var x = edgeStart
            while x < side {
                let i = (y * side + x) * 4
                let a = Float(rgba[i + 3]) / 255
                guard a > 0.35 else { x += 1; continue }
                rSum += Float(rgba[i]) / 255
                gSum += Float(rgba[i + 1]) / 255
                bSum += Float(rgba[i + 2]) / 255
                count += 1
                x += 1
            }
            y += 1
        }
        guard count > 0 else { return [] }

        let n = Float(count)
        let edge = Color(red: Double(rSum / n), green: Double(gSum / n), blue: Double(bSum / n))
        return [edge, edge.adjusted(brightness: 0.72)]
    }

    /// 缩到 side×side 读原始 RGBA 字节。用 CGContext 画一遍，绕开位图对齐/色彩空间的坑。
    /// 封面右缘纵向色带（逐行平均色）：扩展区贴邻封面时的无缝来源。
    /// 每行取最右 edgeColumns 列的平均色——只保留该行的色调与明暗，
    /// 不携带可辨认内容（人物/文字/图案会在逐行平均中化成色晕）。
    /// 返回 side×side×4 的 RGBA 字节（row-major，每行整行同色），线程安全便于后台构建。
    static func edgeProfileRGBA(from data: Data?, side: Int = 24, edgeColumns: Int = 6) -> [UInt8]? {
        guard let data, let image = NSImage(data: data),
              let rgba = downsampledRGBA(image, side: side) else {
            return nil
        }

        var strip = [UInt8](repeating: 0, count: side * side * 4)
        var y = 0
        while y < side {
            var rSum: Float = 0, gSum: Float = 0, bSum: Float = 0, count = 0
            var x = side - edgeColumns
            while x < side {
                let i = (y * side + x) * 4
                let a = Float(rgba[i + 3]) / 255
                guard a > 0.35 else { x += 1; continue }
                rSum += Float(rgba[i]) / 255
                gSum += Float(rgba[i + 1]) / 255
                bSum += Float(rgba[i + 2]) / 255
                count += 1
                x += 1
            }
            if count > 0 {
                let n = Float(count)
                let r = UInt8(min(Double(rSum / n) * 255, 255))
                let g = UInt8(min(Double(gSum / n) * 255, 255))
                let b = UInt8(min(Double(bSum / n) * 255, 255))
                var x = 0
                while x < side {
                    let i = (y * side + x) * 4
                    strip[i] = r
                    strip[i + 1] = g
                    strip[i + 2] = b
                    strip[i + 3] = 255
                    x += 1
                }
            }
            y += 1
        }
        return strip
    }

    /// 把逐行色带字节转成 NSImage（主线程调用，构造轻量）。
    static func stripImage(fromStripRGBA rgba: [UInt8], side: Int) -> NSImage? {
        guard rgba.count == side * side * 4 else { return nil }
        var copy = rgba
        guard let ctx = CGContext(
            data: &copy, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
    }

    private static func downsampledRGBA(_ image: NSImage, side: Int) -> [UInt8]? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bytesPerRow = side * 4
        var buffer = [UInt8](repeating: 0, count: side * bytesPerRow)
        guard let ctx = CGContext(
            data: &buffer, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        return buffer
    }

    private static func hsv(_ r: Float, _ g: Float, _ b: Float) -> (h: Float, s: Float, v: Float) {
        let mx = max(r, g, b), mn = min(r, g, b)
        let delta = mx - mn
        var h: Float = 0
        if delta > 0 {
            if mx == r { h = (g - b) / delta }
            else if mx == g { h = 2 + (b - r) / delta }
            else { h = 4 + (r - g) / delta }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx > 0 ? delta / mx : 0, mx)
    }
}

private extension Color {
    func adjusted(brightness factor: Double) -> Color {
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? .white
        return Color(
            red: min(Double(ns.redComponent) * factor, 1),
            green: min(Double(ns.greenComponent) * factor, 1),
            blue: min(Double(ns.blueComponent) * factor, 1)
        )
    }
}
