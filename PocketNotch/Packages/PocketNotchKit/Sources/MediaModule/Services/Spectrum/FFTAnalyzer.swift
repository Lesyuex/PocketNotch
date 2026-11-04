import Foundation
import Accelerate

/// 离线频谱计算器：吃一段单声道 PCM，吐 bandCount 个 [0,1] 归一化频段幅值。
/// 只做纯数学（Hann 窗 + 实数 FFT + 对数分频 + 归一化），不碰任何 CoreAudio 状态，
/// 由 SystemAudioTapService 的发射定时器在非实时线程调用。
final class FFTAnalyzer {
    private let fftSize: Int
    private let log2n: vDSP_Length
    private let halfSize: Int
    private let bandCount: Int

    private let fftSetup: FFTSetup
    private var window: [Float]

    // 对数分频的频段边界（bin 下标），长度 bandCount + 1
    private let bandEdges: [Int]

    // 复用缓冲，避免每帧分配
    private var windowed: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var magnitudes: [Float]

    // 全局单一自动增益：所有频段共用一个近期峰值当分母，保留频段间相对高低。
    // 使用慢速释放，避免单个瞬态结束后整组频柱同时塌落。
    private var runningPeak: Float = 0
    private let peakDecay: Float = 0.90   // 参考 8 月 30 日版本：峰值随节拍更快释放，避免长期占满动态范围
    private let peakFloor: Float = 1e-3   // 分母下限，防静音时底噪被归一化拉满
    private let outputGain: Float = 0.67  // 参考 8 月 30 日版本，保留峰值余量
    // 自动增益只负责适配不同歌曲，最终高度仍保留当前 PCM 帧的真实响度变化。
    private let loudnessFloorRMS: Float = 0.01
    private let loudnessFullScaleRMS: Float = 0.12
    private let minimumLoudnessWeight: Float = 0.35

    init(fftSize: Int, sampleRate: Double, bandCount: Int) {
        self.fftSize = fftSize
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.halfSize = fftSize / 2
        self.bandCount = bandCount

        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

        self.window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        self.windowed = [Float](repeating: 0, count: fftSize)
        self.realp = [Float](repeating: 0, count: fftSize / 2)
        self.imagp = [Float](repeating: 0, count: fftSize / 2)
        self.magnitudes = [Float](repeating: 0, count: fftSize / 2)

        // 使用面向音乐听感的联合分频。采样端保留 4/5/6 条模式边界，
        // 并额外拆出 8k/12k 高频边界，渲染端按样式合并。
        let minFreq = 40.0
        let maxFreq = min(20_000.0, sampleRate / 2)
        let frequencies: [Double]
        if bandCount == 5 {
            frequencies = [40, 160, 400, 1_000, 3_000, maxFreq]
        } else if bandCount == 6 {
            frequencies = [40, 100, 250, 600, 1_500, 4_000, maxFreq]
        } else if bandCount == AudioSpectrumConfiguration.sampledBandCount {
            frequencies = [
                40, 100, 120, 180, 250, 300, 500, 600, 800,
                1_500, 2_000, 2_500, 3_500, 8_000, 12_000, maxFreq
            ]
        } else {
            frequencies = (0...bandCount).map { index in
                let progress = Double(index) / Double(max(bandCount, 1))
                return minFreq * pow(maxFreq / minFreq, progress)
            }
        }

        let minBin = max(1, Int((minFreq / sampleRate * Double(fftSize)).rounded()))
        let maxBin = halfSize
        var edges = [Int]()
        edges.reserveCapacity(bandCount + 1)
        for (index, frequency) in frequencies.enumerated() {
            let desiredBin = Int((frequency / sampleRate * Double(fftSize)).rounded())
            let minimumBin = index == 0 ? minBin : edges[index - 1] + 1
            let remainingEdges = bandCount - index
            let maximumBin = max(minimumBin, maxBin - remainingEdges)
            edges.append(min(max(desiredBin, minimumBin), maximumBin))
        }
        self.bandEdges = edges

    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// 输入至少 fftSize 个样本（取末尾 fftSize 个）；返回 bandCount 个 [0,1] 幅值。
    func magnitudes(from samples: [Float]) -> [Float] {
        guard samples.count >= fftSize else {
            return [Float](repeating: 0, count: bandCount)
        }
        // 直接读取输入数组末尾的 fftSize 个样本，避免 30/45fps 分析路径每帧创建临时 frame 数组。
        samples.withUnsafeBufferPointer { samplesPointer in
            window.withUnsafeBufferPointer { windowPointer in
                windowed.withUnsafeMutableBufferPointer { windowedPointer in
                    let frameStart = samplesPointer.baseAddress! + (samples.count - fftSize)
                    vDSP_vmul(
                        frameStart,
                        1,
                        windowPointer.baseAddress!,
                        1,
                        windowedPointer.baseAddress!,
                        1,
                        vDSP_Length(fftSize)
                    )
                }
            }
        }

        var frameRMS: Float = 0
        vDSP_rmsqv(windowed, 1, &frameRMS, vDSP_Length(fftSize))

        // 打包成 split complex 做实数 FFT
        realp.withUnsafeMutableBufferPointer { realpPtr in
            imagp.withUnsafeMutableBufferPointer { imagpPtr in
                var split = DSPSplitComplex(realp: realpPtr.baseAddress!, imagp: imagpPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { winPtr in
                    winPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { typeConverted in
                        vDSP_ctoz(typeConverted, 2, &split, 1, vDSP_Length(halfSize))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                // 幅值 = sqrt(re^2 + im^2)
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }

        // 归一化 FFT 增益（vDSP 实数 FFT 有 2x 缩放）
        var scale: Float = 1.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(halfSize))

        // 每段用 RMS 保持稳定，再混入少量峰值保留鼓点冲击感；
        // 频段合并与显示灵敏度统一由渲染端处理。
        var bands = [Float](repeating: 0, count: bandCount)
        for band in 0..<bandCount {
            let lo = bandEdges[band]
            let hi = min(max(bandEdges[band + 1], lo + 1), halfSize)
            var peak: Float = 0
            var meanSquare: Float = 0
            magnitudes.withUnsafeBufferPointer { ptr in
                vDSP_maxv(ptr.baseAddress! + lo, 1, &peak, vDSP_Length(hi - lo))
                vDSP_measqv(ptr.baseAddress! + lo, 1, &meanSquare, vDSP_Length(hi - lo))
            }
            let rms = sqrtf(max(meanSquare, 0))
            bands[band] = rms * 0.75 + peak * 0.25
        }

        // 全局自动增益保留频段间线性比例；真实帧响度参与最终高度，避免最强频段
        // 因“当前峰值 / 当前峰值”而长期锁在固定高位。
        let frameMax = bands.max() ?? 0
        runningPeak = max(frameMax, runningPeak * peakDecay)
        let denom = max(runningPeak, peakFloor)
        let loudnessProgress = min(
            max(
                (frameRMS - loudnessFloorRMS)
                    / (loudnessFullScaleRMS - loudnessFloorRMS),
                0
            ),
            1
        )
        let loudnessWeight = minimumLoudnessWeight
            + (1 - minimumLoudnessWeight) * loudnessProgress
        for i in 0..<bandCount {
            let normalized = min(max(bands[i] / denom, 0), 1)
            // 暂不做 dB/gamma 压缩，直接保留线性峰值比例观察真实律动。
            bands[i] = normalized * outputGain * loudnessWeight
        }
        return bands
    }
}
