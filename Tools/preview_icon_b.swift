import AppKit

// 复用 generate_app_icon.swift 的缩放逻辑与刘海路径构造（方案 B：黑岛内嵌频谱条）

func scaled(_ value: CGFloat, _ size: CGFloat) -> CGFloat {
    value / 1024 * size
}

func roundedIconPath(in rect: CGRect) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.224, yRadius: rect.height * 0.224)
}

func notchPath(in rect: CGRect) -> NSBezierPath {
    let size = rect.width
    let topY = rect.maxY
    let topHalfWidth = scaled(232, size)
    let spread = scaled(92, size)
    let shoulderOuterX = rect.midX + topHalfWidth + spread
    let shoulderInnerX = rect.midX + topHalfWidth + scaled(36, size)
    let sideX = rect.midX + topHalfWidth
    let shoulderY = topY - scaled(48, size)
    let sideBottomY = topY - scaled(116, size)
    let bottomY = topY - scaled(204, size)
    let radius = scaled(88, size)
    let control = radius * 0.5522847498

    let path = NSBezierPath()
    path.move(to: CGPoint(x: rect.midX - topHalfWidth - spread, y: topY))
    path.line(to: CGPoint(x: shoulderOuterX, y: topY))

    path.curve(
        to: CGPoint(x: shoulderInnerX, y: shoulderY),
        controlPoint1: CGPoint(x: shoulderOuterX - scaled(44, size), y: topY),
        controlPoint2: CGPoint(x: shoulderInnerX + scaled(48, size), y: topY - scaled(8, size))
    )
    path.curve(
        to: CGPoint(x: sideX, y: sideBottomY),
        controlPoint1: CGPoint(x: shoulderInnerX - scaled(6, size), y: shoulderY - scaled(30, size)),
        controlPoint2: CGPoint(x: sideX, y: sideBottomY + scaled(28, size))
    )

    path.line(to: CGPoint(x: sideX, y: bottomY + radius))
    path.curve(
        to: CGPoint(x: sideX - radius, y: bottomY),
        controlPoint1: CGPoint(x: sideX, y: bottomY + radius - control),
        controlPoint2: CGPoint(x: sideX - radius + control, y: bottomY)
    )
    path.line(to: CGPoint(x: rect.midX - topHalfWidth + radius, y: bottomY))
    path.curve(
        to: CGPoint(x: rect.midX - topHalfWidth, y: bottomY + radius),
        controlPoint1: CGPoint(x: rect.midX - topHalfWidth + radius - control, y: bottomY),
        controlPoint2: CGPoint(x: rect.midX - topHalfWidth, y: bottomY + radius - control)
    )
    path.line(to: CGPoint(x: rect.midX - topHalfWidth, y: sideBottomY))
    path.curve(
        to: CGPoint(x: rect.midX - topHalfWidth - scaled(36, size), y: shoulderY),
        controlPoint1: CGPoint(x: rect.midX - topHalfWidth, y: sideBottomY + scaled(28, size)),
        controlPoint2: CGPoint(x: rect.midX - topHalfWidth - scaled(36, size) + scaled(6, size), y: shoulderY - scaled(30, size))
    )
    path.curve(
        to: CGPoint(x: rect.midX - topHalfWidth - spread, y: topY),
        controlPoint1: CGPoint(x: rect.midX - topHalfWidth - scaled(36, size) - scaled(48, size), y: topY - scaled(8, size)),
        controlPoint2: CGPoint(x: rect.midX - topHalfWidth - spread + scaled(44, size), y: topY)
    )
    path.close()
    return path
}

func drawPreview(pixelSize: Int, outPath: String) throws {
    let size = CGFloat(pixelSize)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { throw NSError(domain: "Preview", code: 1) }
    rep.size = CGSize(width: size, height: size)
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "Preview", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high

    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    let iconInset = scaled(56, size)
    let iconRect = bounds.insetBy(dx: iconInset, dy: iconInset)
    let iconClip = roundedIconPath(in: iconRect)
    iconClip.addClip()

    // 1. 背景渐变（沿用现有：粉→紫→蓝，-42°）
    let background = NSGradient(colors: [
        NSColor(calibratedRed: 1.00, green: 0.12, blue: 0.53, alpha: 1),
        NSColor(calibratedRed: 0.58, green: 0.16, blue: 0.86, alpha: 1),
        NSColor(calibratedRed: 0.22, green: 0.30, blue: 1.00, alpha: 1)
    ])!
    background.draw(in: iconRect, angle: -42)

    // 2. 上层光晕（淡白，增强"舞台感"）
    let glowPath = NSBezierPath(ovalIn: CGRect(
        x: iconRect.minX - scaled(110, size),
        y: iconRect.maxY - scaled(300, size),
        width: scaled(520, size),
        height: scaled(420, size)
    ))
    NSColor.white.withAlphaComponent(0.18).setFill()
    glowPath.fill()

    let lowerGlow = NSBezierPath(ovalIn: CGRect(
        x: iconRect.midX - scaled(90, size),
        y: iconRect.minY - scaled(170, size),
        width: scaled(620, size),
        height: scaled(500, size)
    ))
    NSColor(calibratedRed: 0.75, green: 0.90, blue: 1.0, alpha: 0.18).setFill()
    lowerGlow.fill()

    // 3. 岛身下方的灵动光晕（hover 溢出感，islandHoverGlow 天蓝）
    let islandGlow = NSBezierPath(ovalIn: CGRect(
        x: iconRect.midX - scaled(150, size),
        y: iconRect.midY - scaled(150, size),
        width: scaled(300, size),
        height: scaled(300, size)
    ))
    NSColor(calibratedRed: 0.34, green: 0.78, blue: 1.0, alpha: 0.35).setFill()
    islandGlow.fill()

    // 4. 黑岛本体
    let notch = notchPath(in: iconRect)
    NSGraphicsContext.saveGraphicsState()
    NSShadow().apply {
        $0.shadowOffset = CGSize(width: 0, height: -scaled(8, size))
        $0.shadowBlurRadius = scaled(28, size)
        $0.shadowColor = NSColor.black.withAlphaComponent(0.35)
    }
    NSColor(calibratedWhite: 0.015, alpha: 1).setFill()
    notch.fill()
    NSGraphicsContext.restoreGraphicsState()

    // 5. 岛内频谱条（方案 B 的灵魂）—— 天蓝渐变，模拟音频频谱
    //    在岛身中部偏下绘制一排竖条，高度非对称（模拟随机频谱）
    let barCount = 9
    let barsAreaLeft = rect(iconRect).minX + scaled(132, size)
    let barsAreaRight = rect(iconRect).maxX - scaled(132, size)
    let barsAreaWidth = barsAreaRight - barsAreaLeft
    let barGap = scaled(22, size)
    let barWidth = (barsAreaWidth - barGap * CGFloat(barCount - 1)) / CGFloat(barCount)
    let barsBottomY = iconRect.maxY - scaled(58, size)
    // 非对称随机频谱高度（相对中心锚点上下生长，模拟振动）
    let heights: [CGFloat] = [0.30, 0.52, 0.40, 0.86, 0.62, 0.95, 0.48, 0.72, 0.34]
    let maxBarHeight = scaled(92, size)

    let barGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.34, green: 0.78, blue: 1.0, alpha: 1),   // islandHoverGlow
        NSColor(calibratedRed: 0.62, green: 0.90, blue: 1.0, alpha: 1)    // 更亮的蓝
    ])!

    for (i, h) in heights.enumerated() {
        let barHeight = maxBarHeight * h
        let barX = barsAreaLeft + CGFloat(i) * (barWidth + barGap)
        let barRect = CGRect(
            x: barX,
            y: barsBottomY - barHeight,
            width: barWidth,
            height: barHeight
        )
        let barPath = NSBezierPath(roundedRect: barRect, xRadius: barWidth * 0.5, yRadius: barWidth * 0.5)
        // 顶部加一点高光，让频谱"亮"在黑底上
        barGradient.draw(in: barPath, angle: 90)
    }

    // 6. 顶部细高光（沿用现有 shine，增强背板材质感）
    let shine = NSBezierPath()
    shine.move(to: CGPoint(x: iconRect.minX + scaled(96, size), y: iconRect.maxY - scaled(82, size)))
    shine.curve(
        to: CGPoint(x: iconRect.maxX - scaled(100, size), y: iconRect.maxY - scaled(108, size)),
        controlPoint1: CGPoint(x: iconRect.midX - scaled(150, size), y: iconRect.maxY - scaled(16, size)),
        controlPoint2: CGPoint(x: iconRect.midX + scaled(160, size), y: iconRect.maxY - scaled(24, size))
    )
    NSColor.white.withAlphaComponent(0.18).setStroke()
    shine.lineWidth = max(1, scaled(9, size))
    shine.lineCapStyle = .round
    shine.stroke()

    // 输出
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:])
    else { throw NSError(domain: "Preview", code: 1) }
    try data.write(to: URL(fileURLWithPath: outPath))
    print("Wrote preview to \(outPath)")
}

extension NSShadow {
    func apply(_ configure: (NSShadow) -> Void) {
        configure(self)
        set()
    }
}

// 辅助：获取 CGRect
func rect(_ r: CGRect) -> CGRect { r }

let outPath = CommandLine.arguments.dropFirst().first ?? "/tmp/pocketnotch_icon_b_preview.png"
try drawPreview(pixelSize: 1024, outPath: outPath)