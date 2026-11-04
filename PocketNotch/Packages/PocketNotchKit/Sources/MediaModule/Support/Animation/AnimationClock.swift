import Foundation

/// 统一动画时钟：把连续时间戳换算成带上限的 deltaTime。
struct AnimationClock {
    private(set) var lastTimestamp: CFTimeInterval = 0
    var maxDelta: CFTimeInterval = 1.0 / 30.0

    mutating func reset() {
        lastTimestamp = 0
    }

    mutating func sample(at timestamp: CFTimeInterval) -> CFTimeInterval {
        defer { lastTimestamp = timestamp }
        guard lastTimestamp > 0 else { return 0 }
        let delta = max(timestamp - lastTimestamp, 0)
        return min(delta, maxDelta)
    }
}
