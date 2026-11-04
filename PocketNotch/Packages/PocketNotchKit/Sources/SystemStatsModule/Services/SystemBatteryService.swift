import Foundation
import IOKit.ps

private func batteryPowerSourceDidChange(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let service = Unmanaged<SystemBatteryService>.fromOpaque(context).takeUnretainedValue()
    // 通知源挂在 main runloop 上，回调必然在主线程执行。
    MainActor.assumeIsolated {
        service.notifyPowerSourceChange()
    }
}

/// 通过 IOKit 读取内置电池，并使用电源源通知实现事件驱动刷新。
/// 仅限主线程访问：IOPS 回调落在 main runloop，VM 也在 MainActor 上持有本服务。
@MainActor
final class SystemBatteryService: BatteryProviding {
    private var changeHandler: (() -> Void)?
    private var notificationSource: CFRunLoopSource?

    func currentSnapshot() -> BatterySnapshot? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue()
                    as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else {
                continue
            }

            let currentCapacity = number(description[kIOPSCurrentCapacityKey]) ?? 0
            let maximumCapacity = max(number(description[kIOPSMaxCapacityKey]) ?? 100, 1)
            let state = description[kIOPSPowerSourceStateKey] as? String
            let isPowerConnected = state == kIOPSACPowerValue
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let isCharged = description[kIOPSIsChargedKey] as? Bool ?? false

            return BatterySnapshot(
                level: currentCapacity / maximumCapacity,
                isCharging: isCharging,
                isCharged: isCharged,
                isPowerConnected: isPowerConnected
            )
        }

        return nil
    }

    func startObserving(_ handler: @escaping () -> Void) {
        stopObserving()
        changeHandler = handler

        guard let unmanagedSource = IOPSNotificationCreateRunLoopSource(
            batteryPowerSourceDidChange,
            Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        let source = unmanagedSource.takeRetainedValue()
        notificationSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    func stopObserving() {
        if let notificationSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), notificationSource, .defaultMode)
        }
        notificationSource = nil
        changeHandler = nil
    }

    fileprivate func notifyPowerSourceChange() {
        changeHandler?()
    }

    private func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    isolated deinit {
        stopObserving()
    }
}
