import Foundation

/// 当前屏幕亮度快照，亮度值归一化到 0...1（1 = 最亮）。
struct BrightnessSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let brightness: Double

    init(id: UUID = UUID(), brightness: Double) {
        self.id = id
        self.brightness = min(max(brightness, 0), 1)
    }

    var displayedPercentage: Int {
        Int((brightness * 100).rounded())
    }
}

/// 亮度键触发的调节命令。
enum BrightnessCommand: Sendable {
    case increase(fineAdjustment: Bool)
    case decrease(fineAdjustment: Bool)
}

/// 亮度步进解析：普通步进 1/16，Option+Shift 细调 1/64（与音量键保持一致）。
enum BrightnessStep {
    static let standard: Double = 1.0 / 16.0
    static let fine: Double = 1.0 / 64.0

    static func delta(fineAdjustment: Bool) -> Double {
        fineAdjustment ? fine : standard
    }

    static func target(from current: Double, command: BrightnessCommand) -> Double {
        let delta = delta(fineAdjustment: command.fineAdjustment)
        switch command {
        case .increase:
            return min(max(current + delta, 0), 1)
        case .decrease:
            return min(max(current - delta, 0), 1)
        }
    }
}

extension BrightnessCommand {
    var fineAdjustment: Bool {
        switch self {
        case .increase(let fineAdjustment), .decrease(let fineAdjustment):
            return fineAdjustment
        }
    }
}