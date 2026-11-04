import CoreAudio
import Foundation
import PocketNotchShared

private struct AudioOutputDeviceDescriptor: Sendable {
    let name: String
    let modelName: String?
    let transportType: UInt32
}

/// 监听系统默认输出设备及其音量、静音属性。首次读取只建立基线，之后的输出切换与音量变化分别通知 UI。
final class SystemAudioOutputVolumeService: AudioOutputVolumeProviding {
    private let listenerQueue = DispatchQueue(label: "com.pocketnotch.audio-output-volume")
    private let listenerQueueKey = DispatchSpecificKey<Void>()
    private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

    private var isObserving = false
    private var outputDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var latestSnapshot: AudioOutputVolumeSnapshot?
    private var hasOutputDeviceBaseline = false
    private var onVolumeChange: (@Sendable (AudioOutputVolumeSnapshot) -> Void)?
    private var onOutputDeviceChange: (@Sendable (AudioOutputDeviceSnapshot) -> Void)?
    private var onOutputDevicesChange: (@Sendable () -> Void)?

    private var defaultOutputListener: AudioObjectPropertyListenerBlock?
    private var outputDevicesListener: AudioObjectPropertyListenerBlock?
    private var devicePropertyListener: AudioObjectPropertyListenerBlock?

    init() {
        listenerQueue.setSpecific(key: listenerQueueKey, value: ())
    }

    func startObserving(
        onVolumeChange: @Sendable @escaping (AudioOutputVolumeSnapshot) -> Void,
        onOutputDeviceChange: @Sendable @escaping (AudioOutputDeviceSnapshot) -> Void
    ) {
        listenerQueue.async { [weak self] in
            guard let self, !self.isObserving else { return }
            self.isObserving = true
            self.onVolumeChange = onVolumeChange
            self.onOutputDeviceChange = onOutputDeviceChange
            self.installDefaultOutputListener()
            self.installOutputDevicesListener()
            self.bindToDefaultOutputDevice()
        }
    }

    func stopObserving() {
        let cleanup = { [self] in
            guard isObserving else { return }
            removeDeviceListeners()
            removeDefaultOutputListener()
            removeOutputDevicesListener()
            outputDeviceID = AudioObjectID(kAudioObjectUnknown)
            latestSnapshot = nil
            hasOutputDeviceBaseline = false
            onVolumeChange = nil
            onOutputDeviceChange = nil
            onOutputDevicesChange = nil
            isObserving = false
        }
        if DispatchQueue.getSpecific(key: listenerQueueKey) != nil {
            cleanup()
        } else {
            listenerQueue.sync(execute: cleanup)
        }
    }

    func currentOutputDevice() -> AudioOutputDeviceSnapshot? {
        let operation: () -> AudioOutputDeviceSnapshot? = { [self] in
            if outputDeviceID == kAudioObjectUnknown {
                bindToDefaultOutputDevice()
            }
            guard outputDeviceID != kAudioObjectUnknown,
                  let descriptor = readDeviceDescriptor(deviceID: outputDeviceID) else {
                return nil
            }
            return AudioOutputDeviceSnapshot(
                deviceName: descriptor.name,
                deviceSymbolName: AudioOutputDeviceSymbol.name(
                    deviceName: descriptor.name,
                    transportType: descriptor.transportType,
                    modelName: descriptor.modelName
                ),
                isBluetoothHeadphones: Self.isBluetoothHeadphones(transportType: descriptor.transportType),
                isWiredHeadphones: Self.isWiredHeadphones(
                    transportType: descriptor.transportType,
                    deviceName: descriptor.name,
                    modelName: descriptor.modelName
                )
            )
        }
        if DispatchQueue.getSpecific(key: listenerQueueKey) != nil {
            return operation()
        }
        return listenerQueue.sync(execute: operation)
    }

    func availableOutputDevices() -> [AudioOutputDevice] {
        let operation = { [self] in readAvailableOutputDevices() }
        if DispatchQueue.getSpecific(key: listenerQueueKey) != nil {
            return operation()
        }
        return listenerQueue.sync(execute: operation)
    }

    func currentVolumeSnapshot() -> AudioOutputVolumeSnapshot? {
        let operation: () -> AudioOutputVolumeSnapshot? = { [self] in
            if outputDeviceID == kAudioObjectUnknown {
                bindToDefaultOutputDevice()
            }
            guard outputDeviceID != kAudioObjectUnknown else { return nil }
            return readSnapshot(deviceID: outputDeviceID)
        }
        if DispatchQueue.getSpecific(key: listenerQueueKey) != nil {
            return operation()
        }
        return listenerQueue.sync(execute: operation)
    }

    func selectOutputDevice(id: UInt32) -> Bool {
        let operation = { [self] in selectOutputDeviceOnListenerQueue(id: AudioObjectID(id)) }
        if DispatchQueue.getSpecific(key: listenerQueueKey) != nil {
            return operation()
        }
        return listenerQueue.sync(execute: operation)
    }

    func setOutputVolume(_ volume: Float) -> Bool {
        let operation = { [self] in setOutputVolumeOnListenerQueue(volume) }
        if DispatchQueue.getSpecific(key: listenerQueueKey) != nil {
            return operation()
        }
        return listenerQueue.sync(execute: operation)
    }

    func setOutputDevicesChangeHandler(_ onChange: @Sendable @escaping () -> Void) {
        let operation = { [self] in onOutputDevicesChange = onChange }
        if DispatchQueue.getSpecific(key: listenerQueueKey) != nil {
            operation()
        } else {
            listenerQueue.sync(execute: operation)
        }
    }

    func perform(_ command: AudioOutputVolumeCommand) -> Bool {
        let operation = { [self] in performOnListenerQueue(command) }
        if DispatchQueue.getSpecific(key: listenerQueueKey) != nil {
            return operation()
        }
        return listenerQueue.sync(execute: operation)
    }

    deinit {
        stopObserving()
    }

    private func installDefaultOutputListener() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.bindToDefaultOutputDevice()
        }
        var address = Self.defaultOutputAddress
        let status = AudioObjectAddPropertyListenerBlock(systemObjectID, &address, listenerQueue, listener)
        guard status == noErr else {
            PocketNotchLog.media.warning("Default audio output listener failed: \(status)")
            return
        }
        defaultOutputListener = listener
    }

    private func removeDefaultOutputListener() {
        guard let defaultOutputListener else { return }
        var address = Self.defaultOutputAddress
        AudioObjectRemovePropertyListenerBlock(systemObjectID, &address, listenerQueue, defaultOutputListener)
        self.defaultOutputListener = nil
    }

    private func installOutputDevicesListener() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.onOutputDevicesChange?()
        }
        var address = Self.outputDevicesAddress
        let status = AudioObjectAddPropertyListenerBlock(systemObjectID, &address, listenerQueue, listener)
        guard status == noErr else {
            PocketNotchLog.media.warning("Audio output devices listener failed: \(status)")
            return
        }
        outputDevicesListener = listener
    }

    private func removeOutputDevicesListener() {
        guard let outputDevicesListener else { return }
        var address = Self.outputDevicesAddress
        AudioObjectRemovePropertyListenerBlock(systemObjectID, &address, listenerQueue, outputDevicesListener)
        self.outputDevicesListener = nil
    }

    private func bindToDefaultOutputDevice() {
        let previousDeviceID = outputDeviceID
        removeDeviceListeners()

        guard let deviceID = readDefaultOutputDevice(), deviceID != kAudioObjectUnknown else {
            outputDeviceID = AudioObjectID(kAudioObjectUnknown)
            latestSnapshot = nil
            return
        }

        outputDeviceID = deviceID
        installDeviceListeners(on: deviceID)
        latestSnapshot = readSnapshot(deviceID: deviceID)
        publishOutputDeviceChange(
            for: deviceID,
            previousDeviceID: previousDeviceID
        )
    }

    private func publishOutputDeviceChange(
        for deviceID: AudioObjectID,
        previousDeviceID: AudioObjectID
    ) {
        guard let descriptor = readDeviceDescriptor(deviceID: deviceID) else { return }

        let snapshot = AudioOutputDeviceSnapshot(
            deviceName: descriptor.name,
            deviceSymbolName: AudioOutputDeviceSymbol.name(
                deviceName: descriptor.name,
                transportType: descriptor.transportType,
                modelName: descriptor.modelName
            ),
            isBluetoothHeadphones: Self.isBluetoothHeadphones(transportType: descriptor.transportType),
            isWiredHeadphones: Self.isWiredHeadphones(
                transportType: descriptor.transportType,
                deviceName: descriptor.name,
                modelName: descriptor.modelName
            )
        )
        let hasBaseline = hasOutputDeviceBaseline
        hasOutputDeviceBaseline = true

        // 首次读取只建立当前默认输出基线；CoreAudio 对同一设备的重复回调也不重复提示。
        guard hasBaseline, previousDeviceID != deviceID else { return }
        onOutputDeviceChange?(snapshot)
    }

    private static func isBluetoothHeadphones(transportType: UInt32) -> Bool {
        transportType == kAudioDeviceTransportTypeBluetooth
            || transportType == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func isWiredHeadphones(
        transportType: UInt32,
        deviceName: String,
        modelName: String?
    ) -> Bool {
        AudioOutputDeviceSymbol.isWiredHeadphones(
            deviceName: deviceName,
            transportType: transportType,
            modelName: modelName
        )
    }

    private func installDeviceListeners(on deviceID: AudioObjectID) {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleDevicePropertyChange()
        }

        var didInstall = false
        for var address in Self.deviceListenerAddresses {
            let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, listenerQueue, listener)
            if status == noErr {
                didInstall = true
            } else {
                PocketNotchLog.media.debug(
                    "Audio output property listener unavailable (selector=\(address.mSelector), status=\(status))"
                )
            }
        }
        if didInstall {
            devicePropertyListener = listener
        }
    }

    private func removeDeviceListeners() {
        guard outputDeviceID != kAudioObjectUnknown, let devicePropertyListener else { return }
        for var address in Self.deviceListenerAddresses {
            AudioObjectRemovePropertyListenerBlock(outputDeviceID, &address, listenerQueue, devicePropertyListener)
        }
        self.devicePropertyListener = nil
    }

    private func handleDevicePropertyChange() {
        guard outputDeviceID != kAudioObjectUnknown,
              let snapshot = readSnapshot(deviceID: outputDeviceID) else { return }

        defer { latestSnapshot = snapshot }
        guard let previous = latestSnapshot, volumeChanged(from: previous, to: snapshot) else { return }
        onVolumeChange?(snapshot)
    }

    private func volumeChanged(
        from previous: AudioOutputVolumeSnapshot,
        to current: AudioOutputVolumeSnapshot
    ) -> Bool {
        abs(previous.volume - current.volume) > 0.0005 || previous.isMuted != current.isMuted
    }

    private func performOnListenerQueue(_ command: AudioOutputVolumeCommand) -> Bool {
        if outputDeviceID == kAudioObjectUnknown {
            bindToDefaultOutputDevice()
        }
        guard outputDeviceID != kAudioObjectUnknown else { return false }

        let didHandle: Bool
        switch command {
        case .increase(let fineAdjustment):
            didHandle = adjustVolume(
                deviceID: outputDeviceID,
                delta: fineAdjustment ? 1 / 64 : 1 / 16
            )
        case .decrease(let fineAdjustment):
            didHandle = adjustVolume(
                deviceID: outputDeviceID,
                delta: fineAdjustment ? -1 / 64 : -1 / 16
            )
        case .toggleMute:
            didHandle = toggleMute(deviceID: outputDeviceID)
        }

        if didHandle {
            publishCurrentSnapshot(force: true)
        }
        return didHandle
    }

    private func adjustVolume(deviceID: AudioObjectID, delta: Float) -> Bool {
        if readMute(deviceID: deviceID), !setMute(false, deviceID: deviceID) {
            return false
        }

        if let mainVolume = CoreAudioPropertyStore.readFloatProperty(
            objectID: deviceID,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ), CoreAudioPropertyStore.isPropertySettable(
            objectID: deviceID,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ) {
            let target = min(max(mainVolume + delta, 0), 1)
            return CoreAudioPropertyStore.setFloatProperty(
                target,
                objectID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeOutput,
                element: kAudioObjectPropertyElementMain
            )
        }

        var didFindWritableChannel = false
        var allWritesSucceeded = true
        for channel in 1...32 {
            let element = AudioObjectPropertyElement(channel)
            guard let channelVolume = CoreAudioPropertyStore.readFloatProperty(
                objectID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeOutput,
                element: element
            ), CoreAudioPropertyStore.isPropertySettable(
                objectID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeOutput,
                element: element
            ) else { continue }

            didFindWritableChannel = true
            let target = min(max(channelVolume + delta, 0), 1)
            allWritesSucceeded = CoreAudioPropertyStore.setFloatProperty(
                target,
                objectID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeOutput,
                element: element
            ) && allWritesSucceeded
        }
        return didFindWritableChannel && allWritesSucceeded
    }

    private func setOutputVolumeOnListenerQueue(_ volume: Float) -> Bool {
        if outputDeviceID == kAudioObjectUnknown {
            bindToDefaultOutputDevice()
        }
        guard outputDeviceID != kAudioObjectUnknown else { return false }

        let target = min(max(volume, 0), 1)
        if target > 0, readMute(deviceID: outputDeviceID), !setMute(false, deviceID: outputDeviceID) {
            return false
        }

        let didSetVolume: Bool
        if CoreAudioPropertyStore.isPropertySettable(
            objectID: outputDeviceID,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ) {
            didSetVolume = CoreAudioPropertyStore.setFloatProperty(
                target,
                objectID: outputDeviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeOutput,
                element: kAudioObjectPropertyElementMain
            )
        } else {
            var didFindWritableChannel = false
            var allWritesSucceeded = true
            for channel in 1...32 {
                let element = AudioObjectPropertyElement(channel)
                guard CoreAudioPropertyStore.isPropertySettable(
                    objectID: outputDeviceID,
                    selector: kAudioDevicePropertyVolumeScalar,
                    scope: kAudioDevicePropertyScopeOutput,
                    element: element
                ) else { continue }

                didFindWritableChannel = true
                allWritesSucceeded = CoreAudioPropertyStore.setFloatProperty(
                    target,
                    objectID: outputDeviceID,
                    selector: kAudioDevicePropertyVolumeScalar,
                    scope: kAudioDevicePropertyScopeOutput,
                    element: element
                ) && allWritesSucceeded
            }
            didSetVolume = didFindWritableChannel && allWritesSucceeded
        }

        if didSetVolume {
            publishCurrentSnapshot(force: true)
        }
        return didSetVolume
    }

    private func toggleMute(deviceID: AudioObjectID) -> Bool {
        setMute(!readMute(deviceID: deviceID), deviceID: deviceID)
    }

    private func setMute(_ isMuted: Bool, deviceID: AudioObjectID) -> Bool {
        if CoreAudioPropertyStore.isPropertySettable(
            objectID: deviceID,
            selector: kAudioDevicePropertyMute,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ) {
            return CoreAudioPropertyStore.setBooleanProperty(
                isMuted,
                objectID: deviceID,
                selector: kAudioDevicePropertyMute,
                scope: kAudioDevicePropertyScopeOutput,
                element: kAudioObjectPropertyElementMain
            )
        }

        var didFindWritableChannel = false
        var allWritesSucceeded = true
        for channel in 1...32 {
            let element = AudioObjectPropertyElement(channel)
            guard CoreAudioPropertyStore.isPropertySettable(
                objectID: deviceID,
                selector: kAudioDevicePropertyMute,
                scope: kAudioDevicePropertyScopeOutput,
                element: element
            ) else { continue }

            didFindWritableChannel = true
            allWritesSucceeded = CoreAudioPropertyStore.setBooleanProperty(
                isMuted,
                objectID: deviceID,
                selector: kAudioDevicePropertyMute,
                scope: kAudioDevicePropertyScopeOutput,
                element: element
            ) && allWritesSucceeded
        }
        return didFindWritableChannel && allWritesSucceeded
    }

    private func publishCurrentSnapshot(force: Bool) {
        guard let snapshot = readSnapshot(deviceID: outputDeviceID) else { return }
        let shouldPublish = force
            || latestSnapshot.map { volumeChanged(from: $0, to: snapshot) } == true
        latestSnapshot = snapshot
        if shouldPublish {
            onVolumeChange?(snapshot)
        }
    }

    private func readDefaultOutputDevice() -> AudioObjectID? {
        var address = Self.defaultOutputAddress
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : nil
    }

    private func readSnapshot(deviceID: AudioObjectID) -> AudioOutputVolumeSnapshot? {
        guard let volume = readVolume(deviceID: deviceID),
              let descriptor = readDeviceDescriptor(deviceID: deviceID) else { return nil }
        return AudioOutputVolumeSnapshot(
            volume: volume,
            isMuted: readMute(deviceID: deviceID),
            deviceName: descriptor.name,
            deviceSymbolName: AudioOutputDeviceSymbol.name(
                deviceName: descriptor.name,
                transportType: descriptor.transportType,
                modelName: descriptor.modelName
            ),
            isBuiltIn: descriptor.transportType == kAudioDeviceTransportTypeBuiltIn
        )
    }

    private func readDeviceDescriptor(deviceID: AudioObjectID) -> AudioOutputDeviceDescriptor? {
        guard deviceID != kAudioObjectUnknown else { return nil }
        let name = CoreAudioPropertyStore.readStringProperty(
            objectID: deviceID,
            selector: kAudioObjectPropertyName,
            scope: kAudioObjectPropertyScopeGlobal
        ) ?? "Audio Output"
        let transportType = CoreAudioPropertyStore.readUInt32Property(
            objectID: deviceID,
            selector: kAudioDevicePropertyTransportType,
            scope: kAudioObjectPropertyScopeGlobal
        ) ?? kAudioDeviceTransportTypeUnknown
        return AudioOutputDeviceDescriptor(
            name: name,
            modelName: CoreAudioPropertyStore.readStringProperty(
                objectID: deviceID,
                selector: kAudioObjectPropertyModelName,
                scope: kAudioObjectPropertyScopeGlobal
            ),
            transportType: transportType
        )
    }

    private func readAvailableOutputDevices() -> [AudioOutputDevice] {
        var address = Self.outputDevicesAddress
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            systemObjectID,
            &address,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        guard AudioObjectGetPropertyData(
            systemObjectID,
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return []
        }

        let currentDeviceID = readDefaultOutputDevice()
        let devices = deviceIDs.compactMap { deviceID -> (AudioOutputDevice, isBuiltIn: Bool)? in
            guard isOutputDevice(deviceID),
                  let descriptor = readDeviceDescriptor(deviceID: deviceID) else {
                return nil
            }
            return (
                AudioOutputDevice(
                    id: UInt32(deviceID),
                    deviceName: descriptor.name,
                    deviceSymbolName: AudioOutputDeviceSymbol.name(
                        deviceName: descriptor.name,
                        transportType: descriptor.transportType,
                        modelName: descriptor.modelName
                    ),
                    isCurrent: deviceID == currentDeviceID,
                    isBluetoothHeadphones: Self.isBluetoothHeadphones(transportType: descriptor.transportType)
                ),
                descriptor.transportType == kAudioDeviceTransportTypeBuiltIn
            )
        }
        return devices.filter(\.isBuiltIn).map(\.0)
            + devices.filter { !$0.isBuiltIn }.map(\.0)
    }

    private func isOutputDevice(_ deviceID: AudioObjectID) -> Bool {
        guard CoreAudioPropertyStore.readBooleanProperty(
            objectID: deviceID,
            selector: kAudioDevicePropertyDeviceIsAlive,
            scope: kAudioObjectPropertyScopeGlobal,
            element: kAudioObjectPropertyElementMain
        ) != false else {
            return false
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize >= MemoryLayout<AudioBufferList>.size else {
            return false
        }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        let bufferList = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            bufferList
        ) == noErr else {
            return false
        }
        return UnsafeMutableAudioBufferListPointer(bufferList).contains {
            $0.mNumberChannels > 0
        }
    }

    private func selectOutputDeviceOnListenerQueue(id deviceID: AudioObjectID) -> Bool {
        guard readAvailableOutputDevices().contains(where: { $0.id == UInt32(deviceID) }) else {
            return false
        }
        if readDefaultOutputDevice() == deviceID {
            return true
        }

        let didSetDefaultOutput = CoreAudioPropertyStore.setAudioObjectIDProperty(
            deviceID,
            objectID: systemObjectID,
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        )
        guard didSetDefaultOutput else { return false }

        _ = CoreAudioPropertyStore.setAudioObjectIDProperty(
            deviceID,
            objectID: systemObjectID,
            selector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        )
        bindToDefaultOutputDevice()
        return true
    }

    private func readMute(deviceID: AudioObjectID) -> Bool {
        if let mainMute = CoreAudioPropertyStore.readBooleanProperty(
            objectID: deviceID,
            selector: kAudioDevicePropertyMute,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ) {
            return mainMute
        }

        return (1...32).contains { channel in
            CoreAudioPropertyStore.readBooleanProperty(
                objectID: deviceID,
                selector: kAudioDevicePropertyMute,
                scope: kAudioDevicePropertyScopeOutput,
                element: AudioObjectPropertyElement(channel)
            ) == true
        }
    }

    private func readVolume(deviceID: AudioObjectID) -> Float? {
        if let mainVolume = CoreAudioPropertyStore.readFloatProperty(
            objectID: deviceID,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ) {
            return min(max(mainVolume, 0), 1)
        }

        let channelVolumes = (1...32).compactMap { channel in
            CoreAudioPropertyStore.readFloatProperty(
                objectID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeOutput,
                element: AudioObjectPropertyElement(channel)
            )
        }
        guard !channelVolumes.isEmpty else { return nil }
        return channelVolumes.reduce(0, +) / Float(channelVolumes.count)
    }

    private static let defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static let outputDevicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static let deviceListenerAddresses = [
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementWildcard
        ),
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementWildcard
        )
    ]
}
