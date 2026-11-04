import SwiftUI

public struct KeyboardIconShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: 352, y: 64))
        path.addCurve(to: CGPoint(x: 320, y: 32), control1: CGPoint(x: 352, y: 46.3), control2: CGPoint(x: 337.7, y: 32))
        path.addCurve(to: CGPoint(x: 288, y: 64), control1: CGPoint(x: 302.3, y: 32), control2: CGPoint(x: 288, y: 46.3))
        path.addLine(to: CGPoint(x: 288, y: 128))
        path.addLine(to: CGPoint(x: 192, y: 128))
        path.addCurve(to: CGPoint(x: 96, y: 224), control1: CGPoint(x: 139, y: 128), control2: CGPoint(x: 96, y: 171))
        path.addLine(to: CGPoint(x: 96, y: 448))
        path.addCurve(to: CGPoint(x: 192, y: 544), control1: CGPoint(x: 96, y: 501), control2: CGPoint(x: 139, y: 544))
        path.addLine(to: CGPoint(x: 448, y: 544))
        path.addCurve(to: CGPoint(x: 544, y: 448), control1: CGPoint(x: 501, y: 544), control2: CGPoint(x: 544, y: 501))
        path.addLine(to: CGPoint(x: 544, y: 224))
        path.addCurve(to: CGPoint(x: 448, y: 128), control1: CGPoint(x: 544, y: 171), control2: CGPoint(x: 501, y: 128))
        path.addLine(to: CGPoint(x: 352, y: 128))
        path.addLine(to: CGPoint(x: 352, y: 64))
        path.closeSubpath()

        path.move(to: CGPoint(x: 160, y: 432))
        path.addCurve(to: CGPoint(x: 184, y: 408), control1: CGPoint(x: 160, y: 418.7), control2: CGPoint(x: 170.7, y: 408))
        path.addLine(to: CGPoint(x: 216, y: 408))
        path.addCurve(to: CGPoint(x: 240, y: 432), control1: CGPoint(x: 229.3, y: 408), control2: CGPoint(x: 240, y: 418.7))
        path.addCurve(to: CGPoint(x: 216, y: 456), control1: CGPoint(x: 240, y: 445.3), control2: CGPoint(x: 229.3, y: 456))
        path.addLine(to: CGPoint(x: 184, y: 456))
        path.addCurve(to: CGPoint(x: 160, y: 432), control1: CGPoint(x: 170.7, y: 456), control2: CGPoint(x: 160, y: 445.3))
        path.closeSubpath()

        path.move(to: CGPoint(x: 280, y: 432))
        path.addCurve(to: CGPoint(x: 304, y: 408), control1: CGPoint(x: 280, y: 418.7), control2: CGPoint(x: 290.7, y: 408))
        path.addLine(to: CGPoint(x: 336, y: 408))
        path.addCurve(to: CGPoint(x: 360, y: 432), control1: CGPoint(x: 349.3, y: 408), control2: CGPoint(x: 360, y: 418.7))
        path.addCurve(to: CGPoint(x: 336, y: 456), control1: CGPoint(x: 360, y: 445.3), control2: CGPoint(x: 349.3, y: 456))
        path.addLine(to: CGPoint(x: 304, y: 456))
        path.addCurve(to: CGPoint(x: 280, y: 432), control1: CGPoint(x: 290.7, y: 456), control2: CGPoint(x: 280, y: 445.3))
        path.closeSubpath()

        path.move(to: CGPoint(x: 400, y: 432))
        path.addCurve(to: CGPoint(x: 424, y: 408), control1: CGPoint(x: 400, y: 418.7), control2: CGPoint(x: 410.7, y: 408))
        path.addLine(to: CGPoint(x: 456, y: 408))
        path.addCurve(to: CGPoint(x: 480, y: 432), control1: CGPoint(x: 469.3, y: 408), control2: CGPoint(x: 480, y: 418.7))
        path.addCurve(to: CGPoint(x: 456, y: 456), control1: CGPoint(x: 480, y: 445.3), control2: CGPoint(x: 469.3, y: 456))
        path.addLine(to: CGPoint(x: 424, y: 456))
        path.addCurve(to: CGPoint(x: 400, y: 432), control1: CGPoint(x: 410.7, y: 456), control2: CGPoint(x: 400, y: 445.3))
        path.closeSubpath()

        path.move(to: CGPoint(x: 224, y: 240))
        path.addCurve(to: CGPoint(x: 272, y: 288), control1: CGPoint(x: 250.5, y: 240), control2: CGPoint(x: 272, y: 261.5))
        path.addCurve(to: CGPoint(x: 224, y: 336), control1: CGPoint(x: 272, y: 314.5), control2: CGPoint(x: 250.5, y: 336))
        path.addCurve(to: CGPoint(x: 176, y: 288), control1: CGPoint(x: 197.5, y: 336), control2: CGPoint(x: 176, y: 314.5))
        path.addCurve(to: CGPoint(x: 224, y: 240), control1: CGPoint(x: 176, y: 261.5), control2: CGPoint(x: 197.5, y: 240))
        path.closeSubpath()

        path.move(to: CGPoint(x: 368, y: 288))
        path.addCurve(to: CGPoint(x: 416, y: 240), control1: CGPoint(x: 368, y: 261.5), control2: CGPoint(x: 389.5, y: 240))
        path.addCurve(to: CGPoint(x: 464, y: 288), control1: CGPoint(x: 442.5, y: 240), control2: CGPoint(x: 464, y: 261.5))
        path.addCurve(to: CGPoint(x: 416, y: 336), control1: CGPoint(x: 464, y: 314.5), control2: CGPoint(x: 442.5, y: 336))
        path.addCurve(to: CGPoint(x: 368, y: 288), control1: CGPoint(x: 389.5, y: 336), control2: CGPoint(x: 368, y: 314.5))
        path.closeSubpath()

        path.move(to: CGPoint(x: 64, y: 288))
        path.addCurve(to: CGPoint(x: 32, y: 256), control1: CGPoint(x: 64, y: 270.3), control2: CGPoint(x: 49.7, y: 256))
        path.addLine(to: CGPoint(x: 0, y: 256))
        path.addLine(to: CGPoint(x: 0, y: 384))
        path.addLine(to: CGPoint(x: 32, y: 416))
        path.addCurve(to: CGPoint(x: 64, y: 384), control1: CGPoint(x: 49.7, y: 416), control2: CGPoint(x: 64, y: 401.7))
        path.addLine(to: CGPoint(x: 64, y: 288))
        path.closeSubpath()

        path.move(to: CGPoint(x: 608, y: 256))
        path.addCurve(to: CGPoint(x: 576, y: 288), control1: CGPoint(x: 590.3, y: 256), control2: CGPoint(x: 576, y: 270.3))
        path.addLine(to: CGPoint(x: 576, y: 384))
        path.addCurve(to: CGPoint(x: 608, y: 416), control1: CGPoint(x: 576, y: 401.7), control2: CGPoint(x: 590.3, y: 416))
        path.addLine(to: CGPoint(x: 640, y: 416))
        path.addLine(to: CGPoint(x: 640, y: 256))
        path.addLine(to: CGPoint(x: 608, y: 256))
        path.closeSubpath()

        let box = path.boundingRect
        let scale = min(rect.width / box.width, rect.height / box.height)
        var transform = CGAffineTransform(translationX: -box.midX, y: -box.midY)
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        transform = transform.concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY))
        return path.applying(transform)
    }
}