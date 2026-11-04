import SwiftUI

public enum IslandPopoverCellDensity {
    case compact
    case standard

    var height: CGFloat {
        switch self {
        case .compact: return 26
        case .standard: return 34
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .compact: return 6
        case .standard: return 8
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact: return 5
        case .standard: return 6
        }
    }

    var hoverOpacity: Double {
        switch self {
        case .compact: return 0.08
        case .standard: return 0.05
        }
    }

    var pressedOpacity: Double {
        switch self {
        case .compact: return 0.12
        case .standard: return 0.08
        }
    }
}

public enum IslandPopoverCellSelectionStyle {
    case none
    case prominent

    var fill: Color? {
        switch self {
        case .none: return nil
        case .prominent: return .white.opacity(0.92)
        }
    }
}

public struct IslandPopoverCell<Label: View>: View {
    private let density: IslandPopoverCellDensity
    private let selectionStyle: IslandPopoverCellSelectionStyle
    private let isSelected: Bool
    private let isHighlighted: Bool
    private let isEnabled: Bool
    private let alignment: Alignment
    private let action: () -> Void
    private let label: () -> Label

    public init(
        density: IslandPopoverCellDensity = .standard,
        selectionStyle: IslandPopoverCellSelectionStyle = .none,
        isSelected: Bool = false,
        isHighlighted: Bool = false,
        isEnabled: Bool = true,
        alignment: Alignment = .leading,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.density = density
        self.selectionStyle = selectionStyle
        self.isSelected = isSelected
        self.isHighlighted = isHighlighted
        self.isEnabled = isEnabled
        self.alignment = alignment
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(
            IslandPopoverCellStyle(
                density: density,
                selectedFill: isSelected ? selectionStyle.fill : nil,
                isHighlighted: isHighlighted,
                isEnabled: isEnabled,
                alignment: alignment
            )
        )
        .disabled(!isEnabled)
    }
}

private struct IslandPopoverCellStyle: ButtonStyle {
    let density: IslandPopoverCellDensity
    let selectedFill: Color?
    let isHighlighted: Bool
    let isEnabled: Bool
    let alignment: Alignment

    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: density.height, alignment: alignment)
            .padding(.horizontal, density.horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: density.cornerRadius, style: .continuous)
                    .fill(fill(isPressed: configuration.isPressed))
            )
            .contentShape(
                RoundedRectangle(cornerRadius: density.cornerRadius, style: .continuous)
            )
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isHovering = true
                case .ended:
                    isHovering = false
                }
            }
            .animation(.easeOut(duration: 0.10), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private func fill(isPressed: Bool) -> Color {
        if let selectedFill {
            return selectedFill
        }
        if isHighlighted {
            return .primary.opacity(0.14)
        }
        guard isEnabled else {
            return .clear
        }
        if isPressed {
            return .primary.opacity(density.pressedOpacity)
        }
        if isHovering {
            return .primary.opacity(density.hoverOpacity)
        }
        return .clear
    }
}
