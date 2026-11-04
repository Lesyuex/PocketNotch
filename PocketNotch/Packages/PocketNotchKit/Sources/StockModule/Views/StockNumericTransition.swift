import SwiftUI

extension View {
    func stockNumericTransition(value: Double, reduceMotion: Bool) -> some View {
        contentTransition(.numericText(value: value))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: value)
    }
}
