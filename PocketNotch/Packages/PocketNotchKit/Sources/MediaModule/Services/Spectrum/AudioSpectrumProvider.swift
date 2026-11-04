import ApplicationServices
import Foundation
import os.lock

/// Coalesces high-frequency spectrum callbacks so the main actor processes only
/// the newest pending frame instead of retaining a backlog of Tasks.
final class SpectrumDeliveryGate: @unchecked Sendable {
    private struct State {
        var latestValues: [Float]?
        var deliveryScheduled = false
        var generation: UInt64 = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func enqueue(
        _ values: [Float],
        apply: @escaping @MainActor ([Float]) -> Void
    ) {
        let currentGeneration = state.withLock { state -> UInt64? in
            state.latestValues = values
            guard !state.deliveryScheduled else { return nil }
            state.deliveryScheduled = true
            return state.generation
        }
        guard let currentGeneration else { return }

        Task { @MainActor [weak self] in
            self?.deliver(
                generation: currentGeneration,
                apply: apply
            )
        }
    }

    func reset() {
        state.withLock {
            $0.generation &+= 1
            $0.latestValues = nil
            $0.deliveryScheduled = false
        }
    }

    @MainActor
    private func deliver(
        generation taskGeneration: UInt64,
        apply: @escaping @MainActor ([Float]) -> Void
    ) {
        let delivery = state.withLock { state -> (isCurrent: Bool, values: [Float]?) in
            guard taskGeneration == state.generation else { return (false, nil) }
            let values = state.latestValues
            state.latestValues = nil
            state.deliveryScheduled = false
            return (true, values)
        }
        guard delivery.isCurrent else { return }

        if let values = delivery.values {
            apply(values)
        }

        let nextGeneration = state.withLock { state -> UInt64? in
            guard state.latestValues != nil, !state.deliveryScheduled else { return nil }
            state.deliveryScheduled = true
            return state.generation
        }
        guard let nextGeneration else { return }
        Task { @MainActor [weak self] in
            self?.deliver(generation: nextGeneration, apply: apply)
        }
    }
}

/// 动态旋律条统一配置。采样端保留 15 个联合频段，渲染端可无缝映射为四条、五条或六条。
enum AudioSpectrumConfiguration {
    // 保留 4/5/6 条模式的联合边界，渲染端再按样式合并。
    // 高频额外拆出 8k/12k 边界，保留 12k～20kHz 的空气感但可单独降权。
    static let sampledBandCount = 15

    private static let fourBarResponseExponents: [CGFloat] = [1.3, 1.2, 1.1, 1.0]
    private static let fiveBarResponseExponents: [CGFloat] = [1.3, 1.2, 1.1, 1.0, 1.0]
    private static let sixBarResponseExponents: [CGFloat] = [1.34, 1.28, 1.2, 1.14, 1.08, 1.0]
    // 联合边界：40 / 100 / 120 / 180 / 250 / 300 / 500 / 600 / 800 /
    // 1500 / 2000 / 2500 / 3500 / 8000 / 12000 / 20000 Hz。
    // 四条：40–180、180–500、500–2000、2000–20000 Hz。
    private static let fourBarBandGroups = [[0, 1, 2], [3, 4, 5], [6, 7, 8, 9], [10, 11, 12, 13, 14]]
    // 五条：40–120、120–300、300–800、800–2500、2500–20000 Hz。
    private static let fiveBarBandGroups = [[0, 1], [2, 3, 4], [5, 6, 7], [8, 9, 10], [11, 12, 13, 14]]
    // 六条：40–100、100–250、250–600、600–1500、1500–3500、3500–20000 Hz。
    private static let sixBarBandGroups = [[0], [1, 2, 3], [4, 5, 6], [7, 8], [9, 10, 11], [12, 13, 14]]

    private static let fourBarHighFrequencyWeights: [Float] = [1.0, 1.0, 1.0, 0.8, 0.35]
    private static let fiveBarHighFrequencyWeights: [Float] = [1.0, 1.0, 0.8, 0.35]
    private static let sixBarHighFrequencyWeights: [Float] = [1.0, 0.8, 0.35]

    static func renderedLevels(
        from sampledBands: [Float],
        configuration: MusicSpectrumConfiguration
    ) -> [CGFloat] {
        let sourceLevels: [Float]
        switch configuration.style {
        case .four:
            if sampledBands.count >= sampledBandCount {
                sourceLevels = fourBarBandGroups.enumerated().map { index, group in
                    aggregate(sampledBands, group: group, weights: index == 3 ? fourBarHighFrequencyWeights : nil)
                }
            } else {
                sourceLevels = Array(sampledBands.prefix(configuration.style.barCount))
            }
        case .five:
            if sampledBands.count >= sampledBandCount {
                sourceLevels = fiveBarBandGroups.enumerated().map { index, group in
                    aggregate(sampledBands, group: group, weights: index == 4 ? fiveBarHighFrequencyWeights : nil)
                }
            } else {
                sourceLevels = Array(sampledBands.prefix(configuration.style.barCount))
            }
        case .seven:
            if sampledBands.count >= sampledBandCount {
                sourceLevels = sixBarBandGroups.enumerated().map { index, group in
                    aggregate(sampledBands, group: group, weights: index == 5 ? sixBarHighFrequencyWeights : nil)
                }
            } else {
                sourceLevels = Array(sampledBands.prefix(configuration.style.barCount))
            }
        }

        let exponents: [CGFloat]
        switch configuration.style {
        case .four: exponents = fourBarResponseExponents
        case .five: exponents = fiveBarResponseExponents
        case .seven: exponents = sixBarResponseExponents
        }
        // 保持原有灵敏度映射：默认值 0.5 对应增益 1.0。
        let sensitivityGain = 0.65 + min(max(configuration.sensitivity, 0), 1) * 0.70

        return (0..<configuration.style.barCount).map { index in
            guard sourceLevels.indices.contains(index) else { return 0 }
            let clamped = min(max(CGFloat(sourceLevels[index]), 0), 1)
            let exponent = exponents.indices.contains(index) ? exponents[index] : 1
            return min(pow(clamped, exponent) * sensitivityGain, 1)
        }
    }

    private static func aggregate(
        _ sampledBands: [Float],
        group: [Int],
        weights: [Float]?
    ) -> Float {
        guard !group.isEmpty else { return 0 }
        let values = group.enumerated().compactMap { offset, index -> (value: Float, weight: Float)? in
            guard sampledBands.indices.contains(index) else { return nil }
            let weight = weights?.indices.contains(offset) == true ? weights![offset] : 1
            return (min(max(sampledBands[index], 0), 1), weight)
        }
        guard !values.isEmpty else { return 0 }
        guard weights != nil else { return values.map(\.value).max() ?? 0 }

        // 高频合并采用加权 RMS + 少量峰值：3/3.5～8k 为主体，
        // 8～12k 次之，12～20k 仅作为空气感补充。
        let weightSum = values.reduce(Float.zero) { $0 + $1.weight }
        let weightedMeanSquare = values.reduce(Float.zero) {
            $0 + ($1.value * $1.weight) * ($1.value * $1.weight)
        } / max(weightSum, 1e-3)
        let weightedRMS = sqrtf(max(weightedMeanSquare, 0))
        let weightedPeak = values.map { $0.value * $0.weight }.max() ?? 0
        return min(weightedRMS * 0.75 + weightedPeak * 0.25, 1)
    }

    static func attackTimeConstant(for attackTime: Double) -> CGFloat {
        // 参考 8 月 30 日版本，默认值 0.5 对应 45ms；数值越大，上升越快。
        CGFloat(0.065 - min(max(attackTime, 0), 1) * 0.040)
    }

    static func releaseTimeConstant(for releaseTime: Double) -> CGFloat {
        // 默认值 0.5 对应约 115ms；数值越大，回落越快。
        CGFloat(0.170 - min(max(releaseTime, 0), 1) * 0.110)
    }

    /// 律动细节映射到输入死区；默认值 0.5 对应 0.015 幅值阈值。
    /// 细节越高，越容易响应小幅频谱变化；目标更新阈值仍由渲染器固定控制。
    static func inputDeadband(for rhythmDetail: Double) -> CGFloat {
        let detail = min(max(rhythmDetail, 0), 1)
        return CGFloat(0.025 - detail * 0.020)
    }
}

/// 频谱数据源统一契约。对外只吐一组 [0,1] 归一化幅值（每个元素 = 一根条）。
/// Phase 1 用 SimulatedAudioSpectrumProvider 假源；Phase 2 换成 SystemAudioTapService（真实 tap+FFT），
/// 视图与 ViewModel 不用改——脆弱/私有的音频捕获全隔离在实现里。
protocol AudioSpectrumProviding: AnyObject {
    var bandCount: Int { get }
    /// 启动采样。onUpdate 回调频段幅值（[0,1]），调用方负责跳主线程与节流。
    func start(onUpdate: @escaping ([Float]) -> Void)
    /// 调整频谱目标更新频率；实现应尽量保留已有采样链路。
    func updateRate(_ updateRate: MusicSpectrumUpdateRate)
    /// 停止采样，释放一切资源（耗电铁律：暂停/收起必须调）。
    func stop()
    /// 是否为真实系统音频捕获源。占位源/模拟源为 false，真实 Tap 为 true，
    /// 供按需授权判断「当前是否已经用上真实捕获、是否需要升级」。
    var isRealAudioCapture: Bool { get }
}

extension AudioSpectrumProviding {
    func updateRate(_ updateRate: MusicSpectrumUpdateRate) {
        // 默认实现供模拟源和测试桩使用；真实 Tap 会重设 FFT 定时器。
    }

    var isRealAudioCapture: Bool { false }
}

/// 系统「屏幕与系统音频录制」授权状态。启动期读它决定能否恢复真实音频捕获：
/// 只读 TCC（CGPreflight / TCCAccessPreflight），不建 tap、不弹窗（TCC 授权持久，重启后无需重新授权）。
var isSystemAudioCaptureAuthorized: Bool {
    if #available(macOS 14.4, *) {
        return isSystemAudioRecordingGranted()
    }
    return false
}

/// 按系统能力与授权状态选 provider：macOS 14.4+ 且用户已授权音频捕获时用真实 Process Tap
/// （内部失败会自动回落假源），否则一律用静态占位源（不产假律动）。
/// 未授权时绝不在启动阶段碰音频捕获，也不模拟播放假数据。
func makeSpectrumProvider(
    isCaptureEnabled: Bool,
    bandCount: Int = AudioSpectrumConfiguration.sampledBandCount,
    updateRate: MusicSpectrumUpdateRate = .smooth
) -> AudioSpectrumProviding {
    if isCaptureEnabled, #available(macOS 14.4, *) {
        switch systemAudioRecordingAuthorization() {
        case .granted:
            return SystemAudioTapService(bandCount: bandCount, updateRate: updateRate)
        case .notDetermined, .denied:
            return StaticAudioSpectrumPlaceholder(bandCount: bandCount)
        }
    } else {
        return StaticAudioSpectrumPlaceholder(bandCount: bandCount)
    }
}

/// 未授权 / 未启用时的静态占位源：启动时只吐一帧全零，此后不再产数，
/// 渲染端保持平稳的静止形态，不模拟假律动，也不消耗资源。
final class StaticAudioSpectrumPlaceholder: AudioSpectrumProviding {
    let bandCount: Int

    init(bandCount: Int = AudioSpectrumConfiguration.sampledBandCount) {
        self.bandCount = bandCount
    }

    func start(onUpdate: @escaping ([Float]) -> Void) {
        onUpdate([Float](repeating: 0, count: bandCount))
    }

    func stop() {}
}

/// Phase 1 假源：与音乐无关的正弦律动，仅用于把渲染管线跑通。约 24fps。
final class SimulatedAudioSpectrumProvider: AudioSpectrumProviding {
    let bandCount: Int
    private let interval: TimeInterval
    private var timer: DispatchSourceTimer?
    private var phase: Double = 0

    init(bandCount: Int = AudioSpectrumConfiguration.sampledBandCount, fps: Double = 24) {
        self.bandCount = bandCount
        self.interval = 1.0 / fps
    }

    deinit {
        stop()
    }

    func start(onUpdate: @escaping ([Float]) -> Void) {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.phase += self.interval * 3.0
            let values = (0..<self.bandCount).map { index -> Float in
                let p = self.phase + Double(index) * 0.7
                return Float((sin(p) + 1) * 0.5)
            }
            onUpdate(values)
        }
        self.timer = timer
        timer.resume()
    }

    func updateRate(_ updateRate: MusicSpectrumUpdateRate) {
        // 模拟源仅用于无授权/失败回落，保持其固定节奏即可。
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}
