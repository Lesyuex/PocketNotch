import Foundation

enum BatteryLevelBand: Equatable, Sendable {
    case normal
    case warning
    case critical
}

public struct BatterySnapshot: Equatable, Sendable {
    public let level: Double
    public let isCharging: Bool
    public let isCharged: Bool
    public let isPowerConnected: Bool

    public init(
        level: Double,
        isCharging: Bool,
        isCharged: Bool,
        isPowerConnected: Bool
    ) {
        self.level = min(max(level, 0), 1)
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.isPowerConnected = isPowerConnected
    }

    public var percentage: Int {
        Int((level * 100).rounded())
    }

    var isFullyCharged: Bool {
        isCharged || (isPowerConnected && percentage >= 100)
    }

    var levelBand: BatteryLevelBand {
        switch level {
        case ...0.2: .critical
        case ...0.5: .warning
        default: .normal
        }
    }

}
