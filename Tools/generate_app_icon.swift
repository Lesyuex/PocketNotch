import AppKit

struct IconSlot {
    let pointSize: Int
    let scale: Int

    var pixelSize: Int { pointSize * scale }
    var filename: String { "pocketnotch-notch-\(pointSize)@\(scale)x.png" }
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "PocketNotch/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let slots = [
    IconSlot(pointSize: 16, scale: 1),
    IconSlot(pointSize: 16, scale: 2),
    IconSlot(pointSize: 32, scale: 1),
    IconSlot(pointSize: 32, scale: 2),
    IconSlot(pointSize: 128, scale: 1),
    IconSlot(pointSize: 128, scale: 2),
    IconSlot(pointSize: 256, scale: 1),
    IconSlot(pointSize: 256, scale: 2),
    IconSlot(pointSize: 512, scale: 1),
    IconSlot(pointSize: 512, scale: 2)
]

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

func drawIcon(pixelSize: Int) -> NSImage {
    let size = CGFloat(pixelSize)
    let image = NSImage(size: CGSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high
    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    let iconInset = scaled(56, size)
    let iconRect = bounds.insetBy(dx: iconInset, dy: iconInset)
    let iconClip = roundedIconPath(in: iconRect)
    iconClip.addClip()

    let background = NSGradient(colors: [
        NSColor(calibratedRed: 1.00, green: 0.12, blue: 0.53, alpha: 1),
        NSColor(calibratedRed: 0.58, green: 0.16, blue: 0.86, alpha: 1),
        NSColor(calibratedRed: 0.22, green: 0.30, blue: 1.00, alpha: 1)
    ])!
    background.draw(in: iconRect, angle: -42)

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

    return image
}

extension NSShadow {
    func apply(_ configure: (NSShadow) -> Void) {
        configure(self)
        set()
    }
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "IconRender", code: 1)
    }
    try data.write(to: url)
}

for slot in slots {
    let image = drawIcon(pixelSize: slot.pixelSize)
    try writePNG(image, to: outputDirectory.appendingPathComponent(slot.filename))
}

let images = slots.map { slot in
    """
        {
          "filename" : "\(slot.filename)",
          "idiom" : "mac",
          "scale" : "\(slot.scale)x",
          "size" : "\(slot.pointSize)x\(slot.pointSize)"
        }
    """
}.joined(separator: ",\n")

let contents = """
{
  "images" : [
\(images)
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

try contents.write(to: outputDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Generated app icon set at \(outputDirectory.path)")
