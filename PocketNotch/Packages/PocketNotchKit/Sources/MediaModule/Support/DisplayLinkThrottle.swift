import Foundation

/// CVDisplayLink 输出回调节流器：把主线程派发限制到目标帧率。
///
/// 面板可能以高于 60Hz（120/240Hz 面板或多显示器合成）回调，
/// 逐帧派发会让切应用瞬间的主队列堆积数倍回调，放大卡顿（见 STUTTER-REPORT 第十节）。
/// 本类只压缩「主线程派发」频率，保证每个回调窗口只放行一个渲染派发。
final class DisplayLinkThrottle {
    private var targetInterval: TimeInterval
    private var nextDueTime: TimeInterval = 0
    private let lock = NSLock()

    init(targetFrameRate: Double = 60) {
        targetInterval = 1.0 / max(targetFrameRate, 1)
    }

    func updateTargetFrameRate(_ targetFrameRate: Double) {
        lock.lock()
        defer { lock.unlock() }
        let normalizedFrameRate = max(targetFrameRate, 1)
        targetInterval = 1.0 / normalizedFrameRate
        nextDueTime = 0
    }

    /// 输出回调里调用（后台线程）。返回 true 时本回调才应派发到主线程。
    /// 采用「下次到期时间」累加，派发间隔稳定收敛到 targetInterval，避免高刷输入下过载漂移。
    func shouldDispatch(at time: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard nextDueTime > 0 else {
            nextDueTime = time + targetInterval
            return true
        }
        guard time >= nextDueTime else { return false }
        nextDueTime += targetInterval
        return true
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        nextDueTime = 0
    }
}
