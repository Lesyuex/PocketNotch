import QuartzCore
import PocketNotchShared

/// 展开/收起动画真实帧率采样器（仅用于验证与性能分析）。
///
/// 原理：展开/收起动画由 SwiftUI 隐式动画驱动，每渲染一帧 `expansionProgress`
/// 都会更新一次，并由视图层的 `onChange(of: phaseController.expansionProgress)`
/// 反向感知。在动画窗口内逐帧记录 `CACurrentMediaTime()` 时间戳，结束后按
/// 时间戳间隔计算平均帧率、峰值帧率与掉帧数。
///
/// 开关（任选其一，未开启时 `begin/frame/end` 均为空操作，零开销）：
/// 1. 启动参数  `--pocketnotch-fps-meter`
/// 2. 环境变量  `POCKETNOTCH_FPS_METER=1`
/// 3. `defaults write com.pocketnotch.app PocketNotchFPSMeterEnabled -bool YES`
///
/// 输出：OSLog（subsystem `com.pocketnotch.app` category `core`）+ stdout，
/// Xcode 控制台与 Console.app 均可查看。
@MainActor
public final class AnimationFPSMeter {
    public enum Session: Sendable {
        case expanding
        case collapsing

        public var label: String {
            switch self {
            case .expanding: "expand"
            case .collapsing: "collapse"
            }
        }
    }

    private var session: Session?
    private var timestamps: [CFTimeInterval] = []

    public static var isEnabled: Bool {
        if CommandLine.arguments.contains("--pocketnotch-fps-meter") { return true }
        if ProcessInfo.processInfo.environment["POCKETNOTCH_FPS_METER"] == "1" { return true }
        return UserDefaults.standard.bool(forKey: "PocketNotchFPSMeterEnabled")
    }

    public init() {}

    /// 动画开始。会丢弃上一次未完成的采样。
    public func begin(_ session: Session) {
        guard Self.isEnabled else { return }
        self.session = session
        timestamps.removeAll(keepingCapacity: true)
    }

    /// 每帧调用一次。由视图层在 `expansionProgress` 每次变化时触发。
    public func frame() {
        guard Self.isEnabled, session != nil else { return }
        timestamps.append(CACurrentMediaTime())
    }

    /// 动画结束（进入稳定终态）时调用，输出统计并重置。
    public func end() {
        guard Self.isEnabled, session != nil else { return }
        let label = session?.label ?? "?"
        defer {
            session = nil
            timestamps.removeAll(keepingCapacity: true)
        }

        let targetRate = max(DisplayRefreshRateMonitor.shared.refreshRate, 1)
        guard let message = Self.makeReport(
            label: label,
            samples: timestamps,
            targetRate: targetRate
        ) else { return }
        PocketNotchLog.core.info("\(message, privacy: .public)")
        print(message)
    }

    /// 纯统计计算：从逐帧时间戳生成报告，样本不足或时长异常时返回 nil。
    nonisolated static func makeReport(
        label: String,
        samples: [CFTimeInterval],
        targetRate: Double
    ) -> String? {
        guard samples.count >= 2 else { return nil }
        let duration = samples.last! - samples.first!
        guard duration > 0.001 else { return nil }

        let frameCount = samples.count
        let averageFPS = Double(frameCount - 1) / duration

        // 最小帧间隔对应瞬时最高帧率；超过目标刷新周期 25% 记为一次掉帧。
        let targetPeriod = 1.0 / max(targetRate, 1)
        var minInterval = Double.greatestFiniteMagnitude
        var dropped = 0
        for index in 1..<samples.count {
            let interval = samples[index] - samples[index - 1]
            if interval < minInterval { minInterval = interval }
            if interval > targetPeriod * 1.25 {
                dropped += 1
            }
        }

        let peakFPS = minInterval > 0 ? 1.0 / minInterval : 0
        return String(
            format: "PocketNotch FPS meter [%@]: frames=%d duration=%.2fs avg=%.1ffps "
                + "peak=%.1ffps target=%.0fHz dropped=%d (%.1f%%)",
            label,
            frameCount,
            duration,
            averageFPS,
            peakFPS,
            targetRate,
            dropped,
            Double(dropped) / Double(frameCount - 1) * 100
        )
    }
}