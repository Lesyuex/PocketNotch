import AppKit
import SwiftUI

/// 频谱柱取色器接口：吃封面 + 柱数，吐每根柱子的上/下色。
/// 两个实现分别对应「主色锚定 + 微扰」与「双主色渐变 + 明暗」，由设置切换。
public protocol SpectrumBarColorProvider {
    func barGradients(artwork: Data?, count: Int) -> [SpectrumBarGradient]
}

/// 频谱柱取色方案。
public enum SpectrumBarColorMode: String, CaseIterable, Identifiable, Sendable {
    case anchor

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .anchor: "主色锚定"
        }
    }

    public var description: String {
        switch self {
        case .anchor: "以封面主色为主，柱子保留少量缓变细节"
        }
    }

    public func makeProvider() -> any SpectrumBarColorProvider {
        switch self {
        case .anchor: AnchorSpectrumBarProvider()
        }
    }
}

// MARK: - 共享采样工具

private struct RGB: Equatable {
    var r: Float; var g: Float; var b: Float

    init(_ r: Float, _ g: Float, _ b: Float) { self.r = r; self.g = g; self.b = b }

    var color: Color { Color(red: Double(r), green: Double(g), blue: Double(b)) }

    static func + (lhs: RGB, rhs: RGB) -> RGB { RGB(lhs.r + rhs.r, lhs.g + rhs.g, lhs.b + rhs.b) }
    static func - (lhs: RGB, rhs: RGB) -> RGB { RGB(lhs.r - rhs.r, lhs.g - rhs.g, lhs.b - rhs.b) }
    static func * (lhs: RGB, rhs: Float) -> RGB { RGB(lhs.r * rhs, lhs.g * rhs, lhs.b * rhs) }
}

private func lerp(_ a: RGB, _ b: RGB, _ t: Float) -> RGB { a + (b - a) * t }

private func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
    min(max(v, lo), hi)
}

private func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int {
    min(max(v, lo), hi)
}

/// 把封面缩到 width×height，返回按行优先排列的 RGB 数组（已忽略透明像素，回退黑）。
private func sampleArtwork(_ data: Data?, width: Int, height: Int) -> [RGB]? {
    guard let data, let image = NSImage(data: data) else { return nil }
    let size = NSSize(width: width, height: height)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: width * 4,
        bitsPerPixel: 32
    )
    rep?.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep!)
    image.draw(in: NSRect(origin: .zero, size: size),
               from: .zero,
               operation: .copy,
               fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    var pixels = [RGB]()
    pixels.reserveCapacity(width * height)
    for y in 0..<height {
        for x in 0..<width {
            if let c = rep?.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                pixels.append(RGB(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent)))
            } else {
                pixels.append(RGB(0, 0, 0))
            }
        }
    }
    return pixels
}

private func hsv(_ c: RGB) -> (h: Float, s: Float, v: Float) {
    let mx = max(c.r, max(c.g, c.b))
    let mn = min(c.r, min(c.g, c.b))
    let d = mx - mn
    let s = mx == 0 ? 0 : d / mx
    var h: Float = 0
    if d > 0 {
        if mx == c.r {
            h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6)
        } else if mx == c.g {
            h = (c.b - c.r) / d + 2
        } else {
            h = (c.r - c.g) / d + 4
        }
        h /= 6
        if h < 0 { h += 1 }
    }
    return (h, s, mx)
}

/// 分桶挑主色：按色相 12 档 × 明度 3 桶，权重 = 像素数 × (0.8 + 饱和度)。
private func pickPrimaryColors(_ pixels: [RGB], maxCount: Int) -> [RGB] {
    struct Bucket { var count = 0; var r: Float = 0; var g: Float = 0; var b: Float = 0; var s: Float = 0 }
    var buckets: [Int: Bucket] = [:]
    for p in pixels {
        let (h, s, v) = hsv(p)
        guard v > 0.12 else { continue }
        let key = Int(h * 12) * 10 + Int(v * 3)
        var bucket = buckets[key] ?? Bucket()
        bucket.count += 1
        bucket.r += p.r; bucket.g += p.g; bucket.b += p.b; bucket.s += s
        buckets[key] = bucket
    }
    guard !buckets.isEmpty else { return [] }
    let ranked = buckets.values.map { b -> (RGB, Float) in
        let n = Float(b.count)
        let avg = RGB(b.r / n, b.g / n, b.b / n)
        return (avg, n * (0.8 + b.s / n))
    }.sorted { $0.1 > $1.1 }
    return ranked.prefix(maxCount).map { $0.0 }
}

/// 一维高斯平滑。
private func gaussianSmooth(_ values: [RGB], sigma: Float) -> [RGB] {
    guard values.count > 1, sigma > 0 else { return values }
    let radius = max(1, Int(sigma * 3))
    var weights: [Float] = []
    for i in -radius...radius {
        weights.append(exp(-(Float(i) * Float(i)) / (Float(2) * sigma * sigma)))
    }
    let sum = weights.reduce(0, +)
    var out = [RGB]()
    out.reserveCapacity(values.count)
    for i in 0..<values.count {
        var acc = RGB(0, 0, 0)
        for j in -radius...radius {
            let idx = clamp(i + j, 0, values.count - 1)
            acc = acc + values[idx] * weights[j + radius]
        }
        out.append(acc * (1 / sum))
    }
    return out
}

private func gaussianSmoothScalar(_ values: [Float], sigma: Float) -> [Float] {
    guard values.count > 1, sigma > 0 else { return values }
    let radius = max(1, Int(sigma * 3))
    var weights: [Float] = []
    for i in -radius...radius {
        weights.append(exp(-(Float(i) * Float(i)) / (Float(2) * sigma * sigma)))
    }
    let sum = weights.reduce(0, +)
    var out = [Float]()
    out.reserveCapacity(values.count)
    for i in 0..<values.count {
        var acc: Float = 0
        for j in -radius...radius {
            let idx = clamp(i + j, 0, values.count - 1)
            acc += values[idx] * weights[j + radius]
        }
        out.append(acc / sum)
    }
    return out
}

private func luminance(_ c: RGB) -> Float { 0.299 * c.r + 0.587 * c.g + 0.114 * c.b }

private func withLuminance(_ c: RGB, _ l: Float) -> RGB {
    let cur = luminance(c)
    let d = l - cur
    return RGB(clamp(c.r + d, 0, 1), clamp(c.g + d, 0, 1), clamp(c.b + d, 0, 1))
}

/// 主色过暗时整体提亮，避免暗色封面导致频谱柱几乎不可见。
private let darkPrimaryFloor: Float = 0.26
private let darkPrimaryLift: Float = 0.20

private func liftDarkPrimary(_ c: RGB) -> RGB {
    let l = luminance(c)
    guard l < darkPrimaryFloor else { return c }
    return withLuminance(c, clamp(l + darkPrimaryLift, 0, 1))
}

// MARK: - 实现一：主色锚定 + 微扰

/// 所有柱子以主色为基，叠加 5% 经大 σ 平滑的局部色相细节，上下各取自己的局部色。
struct AnchorSpectrumBarProvider: SpectrumBarColorProvider {
    private let detailWeight: Float = 0.80
    private let luminanceSpan: Float = 0.10

    func barGradients(artwork: Data?, count: Int) -> [SpectrumBarGradient] {
        guard count > 0,
              let pixels = sampleArtwork(artwork, width: count, height: 4),
              let rawPrimary = pickPrimaryColors(pixels, maxCount: 1).first else {
            return []
        }
        let primary = liftDarkPrimary(rawPrimary)
        let primaryLum = luminance(primary)

        var topLocals = [RGB]()
        var bottomLocals = [RGB]()
        topLocals.reserveCapacity(count)
        bottomLocals.reserveCapacity(count)
        for x in 0..<count {
            var t = RGB(0, 0, 0); var b = RGB(0, 0, 0)
            for y in 0..<2 { t = t + pixels[y * count + x] }
            for y in 2..<4 { b = b + pixels[y * count + x] }
            topLocals.append(t * 0.5)
            bottomLocals.append(b * 0.5)
        }

        let smoothTop = gaussianSmooth(topLocals, sigma: Float(count) / 6)
        let smoothBottom = gaussianSmooth(bottomLocals, sigma: Float(count) / 6)

        return (0..<count).map { i in
            let detailTop = (smoothTop[i] - primary) * detailWeight
            let detailBottom = (smoothBottom[i] - primary) * detailWeight
            var top = primary + detailTop
            var bottom = primary + detailBottom
            top = withLuminance(top, clamp(luminance(top), primaryLum - luminanceSpan, primaryLum + luminanceSpan))
            bottom = withLuminance(bottom, clamp(luminance(bottom), primaryLum - luminanceSpan, primaryLum + luminanceSpan))
            return SpectrumBarGradient(top: top.color, bottom: bottom.color)
        }
    }
}

