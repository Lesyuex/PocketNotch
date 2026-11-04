import Combine
import CoreAudio
import Foundation

/// 系统默认输出设备的音量快照。
struct SystemVolumeSnapshot: Equatable {
    /// 0...1 的音量刻度。
    var level: Double
    var isMuted: Bool
}

/// 通过 CoreAudio 观察默认输出设备的音量与静音变化。
///
/// 监听三处属性：默认输出设备切换（系统对象）、音量刻度、静音开关（设备对象）。
/// 回调统一汇入主线程的 `changes` Publisher，UI 层只消费该信号。
@MainActor
final class SystemVolumeObserver {
    /// 每次音量/静音/设备切换时发出最新快照（含初始读取）。
    let changes: AnyPublisher<SystemVolumeSnapshot, Never>

    private let changeSubject = PassthroughSubject<SystemVolumeSnapshot, Never>()
    private var defaultDeviceListenerInstalled = false
    private var observedDeviceID: AudioDeviceID?
    /// 当前设备上真正带音量刻度的声道元素（读不到主元素时逐个探测）。
    private var volumeElement: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    private var isRunning = false

    init() {
        changes = changeSubject
            .throttle(for: .milliseconds(40), scheduler: DispatchQueue.main, latest: true)
            .eraseToAnyPublisher()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        installDefaultDeviceListener()
        refreshObservedDevice()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        removeDeviceListener()
        removeDefaultDeviceListener()
    }

    func currentSnapshot() -> SystemVolumeSnapshot {
        readVolume()
    }

    /// 拖动调节：写回音量刻度；若设备支持静音且当前静音，先解除静音。
    func setLevel(_ level: Double) {
        guard let deviceID = observedDeviceID, deviceID != kAudioObjectUnknown else { return }
        let clamped = Float32(min(max(level, 0), 1))

        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: volumeElement
        )
        var scalar = clamped
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(deviceID, &volumeAddress, 0, nil, size, &scalar)

        if let muted: UInt32 = Self.readProperty(
            deviceID,
            selector: kAudioDevicePropertyMute,
            scope: kAudioObjectPropertyScopeOutput,
            element: volumeElement
        ), muted != 0 {
            var unmuted = UInt32(0)
            var muteAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: volumeElement
            )
            var muteSize = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectSetPropertyData(deviceID, &muteAddress, 0, nil, muteSize, &unmuted)
        }
    }

    // MARK: - 设备监听

    private func installDefaultDeviceListener() {
        guard !defaultDeviceListenerInstalled else { return }
        defaultDeviceListenerInstalled = true
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main
        ) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.refreshObservedDevice()
            }
        }
    }

    private func removeDefaultDeviceListener() {
        guard defaultDeviceListenerInstalled else { return }
        defaultDeviceListenerInstalled = false
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main
        ) { _, _ in }
    }

    private func refreshObservedDevice() {
        guard isRunning else { return }
        let deviceID = Self.defaultOutputDeviceID()
        guard deviceID != observedDeviceID else {
            // 设备没变也重读一次：设备切换通知可能伴随状态刷新。
            emitCurrent()
            return
        }
        removeDeviceListener()
        observedDeviceID = deviceID
        if deviceID != kAudioObjectUnknown {
            volumeElement = Self.discoverVolumeElement(on: deviceID)
            installDeviceListener(on: deviceID)
        }
        emitCurrent()
    }

    private func installDeviceListener(on deviceID: AudioDeviceID) {
        // 监听用通配元素：任何声道的音量/静音变化都触发一次重读。
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementWildcard
        )
        AudioObjectAddPropertyListenerBlock(
            deviceID,
            &volumeAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.emitCurrent()
            }
        }

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementWildcard
        )
        AudioObjectAddPropertyListenerBlock(
            deviceID,
            &muteAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.emitCurrent()
            }
        }
    }

    private func removeDeviceListener() {
        guard let deviceID = observedDeviceID, deviceID != kAudioObjectUnknown else { return }
        observedDeviceID = nil
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementWildcard
        )
        AudioObjectRemovePropertyListenerBlock(deviceID, &volumeAddress, DispatchQueue.main) { _, _ in }
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementWildcard
        )
        AudioObjectRemovePropertyListenerBlock(deviceID, &muteAddress, DispatchQueue.main) { _, _ in }
    }

    private func emitCurrent() {
        guard isRunning else { return }
        changeSubject.send(readVolume())
    }

    // MARK: - 读取

    private func readVolume() -> SystemVolumeSnapshot {
        guard let deviceID = observedDeviceID, deviceID != kAudioObjectUnknown else {
            return SystemVolumeSnapshot(level: 0, isMuted: true)
        }

        var isMuted = false
        let muted: UInt32? = Self.readProperty(
            deviceID,
            selector: kAudioDevicePropertyMute,
            scope: kAudioObjectPropertyScopeOutput,
            element: volumeElement
        ) ?? Self.readProperty(
            deviceID,
            selector: kAudioDevicePropertyMute,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementWildcard
        )
        if let muted {
            isMuted = muted != 0
        }

        var level: Double
        let scalar: Float32? = Self.readProperty(
            deviceID,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput,
            element: volumeElement
        )
        if let scalar {
            level = Double(scalar)
        } else {
            // 不支持音量刻度的设备（如部分聚合设备）视为固定电平。
            level = isMuted ? 0 : 1
        }

        return SystemVolumeSnapshot(level: min(max(level, 0), 1), isMuted: isMuted)
    }

    /// 探测设备上支持音量刻度的输出声道：优先主元素，然后通配，最后逐个声道。
    private static func discoverVolumeElement(on deviceID: AudioDeviceID) -> AudioObjectPropertyElement {
        let candidates: [AudioObjectPropertyElement] = [
            kAudioObjectPropertyElementMain,
            kAudioObjectPropertyElementWildcard,
            1, 2, 3, 4
        ]
        for element in candidates {
            if Self.hasProperty(
                deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput,
                element: element,
                expectedSize: UInt32(MemoryLayout<Float32>.size)
            ) {
                return element
            }
        }
        return kAudioObjectPropertyElementMain
    }

    private static func hasProperty(
        _ deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        expectedSize: UInt32
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr
            && size == expectedSize
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else {
            return kAudioObjectUnknown
        }
        return deviceID
    }

    private static func readProperty<T>(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> T? {
        var value: T?
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
            return nil
        }
        var scratch = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { scratch.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, scratch) == noErr else {
            return nil
        }
        value = scratch.load(as: T.self)
        return value
    }
}
