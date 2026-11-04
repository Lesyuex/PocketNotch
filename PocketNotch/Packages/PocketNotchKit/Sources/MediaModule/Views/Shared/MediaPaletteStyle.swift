import AppKit
import SwiftUI

enum MediaPaletteStyle {
    static func foregroundColors(from colors: [Color]) -> [Color] {
        guard let primary = colors.first else {
            return [.white.opacity(0.92), .white.opacity(0.58)]
        }
        return [.white.opacity(0.92), primary.opacity(0.70)]
    }

    static func backgroundColors(from colors: [Color]) -> [Color] {
        guard let primary = colors.first else {
            return [.white.opacity(0.10), .white.opacity(0.035), .clear]
        }
        let visiblePrimary = boostedForDarkBackground(primary)
        let visibleSecondary = boostedForDarkBackground(colors.dropFirst().first ?? primary)
        return [
            visiblePrimary.opacity(0.40),
            visibleSecondary.opacity(0.20),
            visiblePrimary.opacity(0.06)
        ]
    }

    static func trackColor(from colors: [Color]) -> Color {
        (colors.first ?? .white).opacity(colors.isEmpty ? 0.12 : 0.16)
    }

    static func boostedForDarkBackground(_ color: Color) -> Color {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        let brightestComponent = max(
            nsColor.redComponent,
            nsColor.greenComponent,
            nsColor.blueComponent
        )
        let scale = brightestComponent > 0
            ? max(1, 0.62 / brightestComponent)
            : 1
        return Color(
            red: min(nsColor.redComponent * scale, 1),
            green: min(nsColor.greenComponent * scale, 1),
            blue: min(nsColor.blueComponent * scale, 1)
        )
    }
}
