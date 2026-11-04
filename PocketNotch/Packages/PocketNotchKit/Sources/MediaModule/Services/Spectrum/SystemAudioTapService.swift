import Foundation
import CoreAudio
import AudioToolbox
import Accelerate
import PocketNotchShared
import os.lock

/// 系统音频捕获 + FFT 的唯一隔离点（与 MediaRemoteService 平级）。
/// CoreAudio Process Tap 是 macOS 14.4+ 的脆弱系统 API，所有 tap/聚合设备/FFT 只允许出现在此文件。
/// 对外只吐 [Float] 归一化频段幅值。任何一步失败 → 内部回落 SimulatedAudioSpectrumProvider，保证 compact 两侧内容持续可用。
///
/// 关键约束：
/// - IOProc 跑在实时音频线程，回调里【只拷样本】，绝不做 FFT/加锁重活以外的事。
/// - FFT 放独立定时器（30/45fps）离线算，天然节流。
/// - start 只在播放时调、stop 在暂停/收起立即调（耗电铁律，由 ViewModel 把关）。
@available(macOS 14.4, *)
final class SystemAudioTapService: AudioSpectrumProviding {
    private static let setupQueueKey = DispatchSpecificKey<Void>()

    let bandCount: Int

    var isRealAudioCapture: Bool { true }

    // 1024 点提供约 43Hz 的频率分辨率，减少实时视觉延迟；低频稳定性由 RMS/Peak 混合维持。
    private let fftSize = 1024
    private var emitFPS: Double
    private var updateRate: MusicSpectrumUpdateRate
    private var emitHandler: (([Float]) -> Void)?

    // tap / 聚合设备 / IOProc 句柄
    private var tapID: AUAudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(label: "com.pocketnotch.audiotap.io", qos: .userInitiated)
    private let setupQueue = DispatchQueue(label: "com.pocketnotch.audiotap.setup")

    // 最近 fftSize 个单声道样本，IOProc 写、定时器读，锁保护
    private var sampleLock = os_unfair_lock_s()
    private var sampleBuffer: [Float]
    private var analysisBuffer: [Float]
    /// 单声道降混 scratch（仅 ioQueue 实时回调写），避免每块逐样本分配。
    private var monoSamples: [Float]
    private var emitTimer: DispatchSourceTimer?
    private var analyzer: FFTAnalyzer?
    private let lifecycleGeneration = OSAllocatedUnfairLock(initialState: UInt64(0))

    // 真实建链成功的信号（tap+聚合设备+IOProc+启动全部成功），供授权探测轮询读取
    private var chainReadyLock = os_unfair_lock_s()
    private var chainEstablishedByBuild = false

    // 失败回落
    private let fallback: SimulatedAudioSpectrumProvider
    private var usingFallback = false

    init(
        bandCount: Int = AudioSpectrumConfiguration.sampledBandCount,
        updateRate: MusicSpectrumUpdateRate = .smooth
    ) {
        self.bandCount = bandCount
        self.updateRate = updateRate
        self.emitFPS = updateRate.fftUpdateRate
        self.sampleBuffer = [Float](repeating: 0, count: fftSize)
        self.analysisBuffer = [Float](repeating: 0, count: fftSize)
        self.monoSamples = [Float](repeating: 0, count: fftSize)
        self.fallback = SimulatedAudioSpectrumProvider(bandCount: bandCount, fps: 24)
        setupQueue.setSpecific(key: Self.setupQueueKey, value: ())
    }

    deinit {
        stop()
    }

    func start(onUpdate: @escaping ([Float]) -> Void) {
        stop()
        os_unfair_lock_lock(&chainReadyLock)
        chainEstablishedByBuild = false
        os_unfair_lock_unlock(&chainReadyLock)
        let generation = lifecycleGeneration.withLock { value in
            value &+= 1
            return value
        }
        setupQueue.async { [weak self] in
            guard let self else { return }
            let isCurrent = self.lifecycleGeneration.withLock { $0 == generation }
            guard isCurrent else { return }
            do {
                try self.buildTap()
                try self.buildAggregateDevice()
                try self.installIOProc()
                os_unfair_lock_lock(&self.chainReadyLock)
                self.chainEstablishedByBuild = true
                os_unfair_lock_unlock(&self.chainReadyLock)
                self.startEmitTimer(onUpdate: onUpdate)
                PocketNotchLog.media.debug("SystemAudioTap started (tap=\(self.tapID), agg=\(self.aggregateID))")
            } catch {
                PocketNotchLog.media.warning("SystemAudioTap setup failed, falling back: \(String(describing: error), privacy: .public)")
                self.teardownCoreAudio()
                self.startFallback(onUpdate: onUpdate)
            }
        }
    }

    /// 探测链路是否已建好（tap + 聚合设备 + IOProc + 启动全部成功）。
    /// 授权被拒绝时建链/启动会失败，因此「建链成功」本身即是已授权的信号，
    /// 不依赖当前系统是否正在出声。轮询直到建好或超时。
    func probeChainEstablished(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            os_unfair_lock_lock(&chainReadyLock)
            let ready = chainEstablishedByBuild
            os_unfair_lock_unlock(&chainReadyLock)
            if ready { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return false
    }

    func stop() {
        lifecycleGeneration.withLock { $0 &+= 1 }
        if DispatchQueue.getSpecific(key: Self.setupQueueKey) != nil {
            performStopCleanup()
        } else {
            setupQueue.sync {
                performStopCleanup()
            }
        }
    }

    func updateRate(_ updateRate: MusicSpectrumUpdateRate) {
        setupQueue.async { [weak self] in
            guard let self else { return }
            self.updateRate = updateRate
            self.emitFPS = updateRate.fftUpdateRate
            guard !self.usingFallback,
                  self.analyzer != nil,
                  let handler = self.emitHandler else { return }
            self.emitTimer?.cancel()
            self.emitTimer = nil
            self.startEmitTimer(onUpdate: handler)
        }
    }

    private func performStopCleanup() {
        emitTimer?.cancel()
        emitTimer = nil
        emitHandler = nil
        if usingFallback {
            fallback.stop()
            usingFallback = false
        }
        teardownCoreAudio()
    }

    private func startFallback(onUpdate: @escaping ([Float]) -> Void) {
        usingFallback = true
        fallback.start(onUpdate: onUpdate)
    }

    // MARK: - CoreAudio tap 建立

    private func buildTap() throws {
        // 全局立体声 tap：抓「全部进程」，排除列表传空=谁都不排除。
        // 【坑】stereoMixdownOfProcesses:[] 是「只混列出的进程」→ 空=静音；
        //       全系统捕获必须用 GlobalTapButExclude。muteBehavior=.unmuted 让系统照常出声。
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap: AUAudioObjectID = 0
        let status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr, tap != 0 else {
            throw TapError.createTapFailed(status)
        }
        tapID = tap
    }

    private func buildAggregateDevice() throws {
        let tapUID = try stringProperty(tapID, kAudioTapPropertyUID) ?? UUID().uuidString
        let aggUID = "com.pocketnotch.audiotap.aggregate"
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "PocketNotch Audio Tap",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]

        var agg: AudioObjectID = 0
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &agg)
        guard status == noErr, agg != 0 else {
            throw TapError.createAggregateFailed(status)
        }
        aggregateID = agg
    }

    private func installIOProc() throws {
        let sampleRate = (try? doubleProperty(aggregateID, kAudioDevicePropertyNominalSampleRate)) ?? 44_100
        analyzer = FFTAnalyzer(fftSize: fftSize, sampleRate: sampleRate, bandCount: bandCount)

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, ioQueue) {
            [weak self] _, inInputData, _, _, _ in
            self?.consume(inInputData)
        }
        guard status == noErr, let procID else {
            throw TapError.createIOProcFailed(status)
        }
        ioProcID = procID

        let startStatus = AudioDeviceStart(aggregateID, procID)
        guard startStatus == noErr else {
            throw TapError.deviceStartFailed(startStatus)
        }
    }

    /// 实时线程：只把最新样本拷进环形缓冲，绝不做 FFT；多通道先做保相位的 mono downmix。
    private func consume(_ bufferList: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: bufferList)
        )
        guard !buffers.isEmpty else { return }

        let first = buffers[0]
        let firstChannels = max(Int(first.mNumberChannels), 1)
        let isInterleaved = buffers.count == 1 && firstChannels > 1
        let frameCount: Int
        if isInterleaved {
            frameCount = Int(first.mDataByteSize)
                / MemoryLayout<Float>.size
                / firstChannels
        } else {
            frameCount = buffers.reduce(Int.max) { current, buffer in
                let channels = max(Int(buffer.mNumberChannels), 1)
                let count = Int(buffer.mDataByteSize)
                    / MemoryLayout<Float>.size
                    / channels
                return min(current, count)
            }
        }
        guard frameCount > 0 else { return }

        let copiedFrameCount = min(frameCount, fftSize)
        // 取末尾 copiedFrameCount 帧做 mono downmix，vDSP 跨步累加替代逐样本通道循环。
        monoSamples.withUnsafeMutableBufferPointer { mono in
            guard let monoBase = mono.baseAddress else { return }

            if isInterleaved, let raw = first.mData {
                let samples = raw.assumingMemoryBound(to: Float.self)
                let channelCount = firstChannels
                let sourceFrameOffset = (frameCount - copiedFrameCount) * channelCount
                vDSP_vclr(monoBase, 1, vDSP_Length(copiedFrameCount))
                for channel in 0..<channelCount {
                    vDSP_vadd(
                        samples + sourceFrameOffset + channel, channelCount,
                        monoBase, 1,
                        monoBase, 1,
                        vDSP_Length(copiedFrameCount)
                    )
                }
                var scale = 1 / Float(channelCount)
                vDSP_vsmul(monoBase, 1, &scale, monoBase, 1, vDSP_Length(copiedFrameCount))
            } else {
                let channelCount = buffers.reduce(0) { $0 + max(Int($1.mNumberChannels), 1) }
                vDSP_vclr(monoBase, 1, vDSP_Length(copiedFrameCount))
                for buffer in buffers {
                    let channels = max(Int(buffer.mNumberChannels), 1)
                    guard let raw = buffer.mData else { continue }
                    let samples = raw.assumingMemoryBound(to: Float.self)
                    let sourceFrameOffset = (frameCount - copiedFrameCount) * channels
                    for channel in 0..<channels {
                        vDSP_vadd(
                            samples + sourceFrameOffset + channel, channels,
                            monoBase, 1,
                            monoBase, 1,
                            vDSP_Length(copiedFrameCount)
                        )
                    }
                }
                var scale = 1 / Float(max(channelCount, 1))
                vDSP_vsmul(monoBase, 1, &scale, monoBase, 1, vDSP_Length(copiedFrameCount))
            }

            // 环形缓冲原地更新：保留旧样本 + 写入最新 downmix 样本。
            os_unfair_lock_lock(&sampleLock)
            defer { os_unfair_lock_unlock(&sampleLock) }
            sampleBuffer.withUnsafeMutableBufferPointer { buffer in
                guard let destination = buffer.baseAddress else { return }
                if copiedFrameCount < fftSize {
                    let retainedFrameCount = fftSize - copiedFrameCount
                    memmove(
                        destination,
                        destination + copiedFrameCount,
                        retainedFrameCount * MemoryLayout<Float>.stride
                    )
                }
                let destinationStartFrame = fftSize - copiedFrameCount
                memcpy(
                    destination + destinationStartFrame,
                    monoBase,
                    copiedFrameCount * MemoryLayout<Float>.stride
                )
            }
        }
    }

    private func startEmitTimer(onUpdate: @escaping ([Float]) -> Void) {
        emitHandler = onUpdate
        let timer = DispatchSource.makeTimerSource(queue: ioQueue)
        timer.schedule(deadline: .now() + 1.0 / emitFPS, repeating: 1.0 / emitFPS)
        timer.setEventHandler { [weak self] in
            guard let self, let analyzer = self.analyzer else { return }
            os_unfair_lock_lock(&self.sampleLock)
            self.analysisBuffer.withUnsafeMutableBufferPointer { destination in
                self.sampleBuffer.withUnsafeBufferPointer { source in
                    guard let destinationAddress = destination.baseAddress,
                          let sourceAddress = source.baseAddress else {
                        return
                    }
                    destinationAddress.update(from: sourceAddress, count: self.fftSize)
                }
            }
            os_unfair_lock_unlock(&self.sampleLock)
            let bands = analyzer.magnitudes(from: self.analysisBuffer)
            onUpdate(bands)
        }
        emitTimer = timer
        PocketNotchLog.media.debug(
            "Spectrum FFT timer configured mode=\(self.updateRate.rawValue, privacy: .public) fps=\(self.emitFPS, privacy: .public) fft=\(self.fftSize, privacy: .public)"
        )
        timer.resume()
    }

    // MARK: - 拆除

    private func teardownCoreAudio() {
        if aggregateID != 0, let procID = ioProcID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        ioProcID = nil
        if aggregateID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = 0
        }
        if tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }
        analyzer = nil
    }

    // MARK: - 属性读取

    private func stringProperty(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) {
            $0.withMemoryRebound(to: UInt8.self, capacity: Int(size)) { raw in
                AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, raw)
            }
        }
        guard status == noErr else { throw TapError.propertyReadFailed(selector, status) }
        return value as String?
    }

    private func doubleProperty(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Double>.size)
        var value: Double = 0
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr else { throw TapError.propertyReadFailed(selector, status) }
        return value
    }

    enum TapError: Error {
        case createTapFailed(OSStatus)
        case createAggregateFailed(OSStatus)
        case createIOProcFailed(OSStatus)
        case deviceStartFailed(OSStatus)
        case propertyReadFailed(AudioObjectPropertySelector, OSStatus)
    }
}

/// 快速授权判定（只读 TCC，不建 tap、不弹窗）。可在启动期与 1s 轮询里安全调用。
/// 「屏幕与系统音频录制」授权或纯「系统音频录制」授权都算已授权。
@available(macOS 14.4, *)
public func isSystemAudioRecordingGranted() -> Bool {
    systemAudioRecordingAuthorization() == .granted
}

@available(macOS 14.4, *)
private let audioRecordingRequestLock = OSAllocatedUnfairLock(initialState: false)

/// 触发「系统音频录制」授权弹窗并探测建链结果：首次启动含 Process Tap 的聚合设备时，
/// 系统自动弹出「录制你的系统音频」纯音频授权。这里真实建链一次、停留片刻即拆链，不做持续采集。
///
/// 授权被拒绝时建链/启动会失败；因此「真实建链成功」本身就是已授权信号，与系统是否正在出声无关。
/// 成功后写入本地标记供只读判定兜底。单飞：已有探测在跑时直接返回 false，由 1s 轮询重试。
@available(macOS 14.4, *)
public func requestSystemAudioRecordingAccess() async -> Bool {
    let acquired = audioRecordingRequestLock.withLock { state -> Bool in
        guard !state else { return false }
        state = true
        return true
    }
    guard acquired else { return false }

    let established = await Task.detached(priority: .userInitiated) {
        let probe = SystemAudioTapService()
        probe.start(onUpdate: { _ in })
        let ready = probe.probeChainEstablished(timeout: 2)
        probe.stop()
        return ready
    }.value

    if established {
        markSystemAudioRecordingChainGranted()
    }
    invalidateSystemAudioRecordingAuthorizationCache()
    audioRecordingRequestLock.withLock { $0 = false }
    return established
}
