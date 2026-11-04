protocol AudioOutputVolumeProviding: AnyObject {
    func startObserving(
        onVolumeChange: @Sendable @escaping (AudioOutputVolumeSnapshot) -> Void,
        onOutputDeviceChange: @Sendable @escaping (AudioOutputDeviceSnapshot) -> Void
    )
    func stopObserving()
    func currentOutputDevice() -> AudioOutputDeviceSnapshot?
    func currentVolumeSnapshot() -> AudioOutputVolumeSnapshot?
    func availableOutputDevices() -> [AudioOutputDevice]
    func selectOutputDevice(id: UInt32) -> Bool
    func setOutputVolume(_ volume: Float) -> Bool
    func setOutputDevicesChangeHandler(_ onChange: @Sendable @escaping () -> Void)
    /// 返回 true 表示 PocketNotch 已完成调节，调用方可以吞掉系统音量键事件。
    func perform(_ command: AudioOutputVolumeCommand) -> Bool
}

extension AudioOutputVolumeProviding {
    func currentOutputDevice() -> AudioOutputDeviceSnapshot? { nil }
    func currentVolumeSnapshot() -> AudioOutputVolumeSnapshot? { nil }
    func availableOutputDevices() -> [AudioOutputDevice] { [] }
    func selectOutputDevice(id: UInt32) -> Bool { false }
    func setOutputVolume(_ volume: Float) -> Bool { false }
    func setOutputDevicesChangeHandler(_ onChange: @Sendable @escaping () -> Void) {}
}
