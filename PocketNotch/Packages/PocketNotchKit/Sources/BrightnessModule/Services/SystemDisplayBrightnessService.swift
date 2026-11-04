import CoreGraphics
import Foundation
import PocketNotchShared

/// 私有框架（DisplayServices）隔离点：所有脆弱/私有 API 只允许出现在此文件。
/// API 失效或需上架时只改这一处，其余代码只消费 `BrightnessProviding` 接口。
final class SystemDisplayBrightnessService: BrightnessProviding {
    private typealias GetBrightnessFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChangeBrightnessFunction = @convention(c) (CGDirectDisplayID) -> Bool

    private static let frameworkPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    private let frameworkHandle: UnsafeMutableRawPointer?
    private let mainDisplayID = CGMainDisplayID()
    private let getBrightness: GetBrightnessFunction?
    private let setBrightness: SetBrightnessFunction?
    private let canChangeBrightness: CanChangeBrightnessFunction?

    init() {
        frameworkHandle = dlopen(Self.frameworkPath, RTLD_NOW)
        getBrightness = Self.loadSymbol(
            "DisplayServicesGetBrightness",
            from: frameworkHandle,
            as: GetBrightnessFunction.self
        )
        setBrightness = Self.loadSymbol(
            "DisplayServicesSetBrightness",
            from: frameworkHandle,
            as: SetBrightnessFunction.self
        )
        canChangeBrightness = Self.loadSymbol(
            "DisplayServicesCanChangeBrightness",
            from: frameworkHandle,
            as: CanChangeBrightnessFunction.self
        )
        if frameworkHandle == nil {
            PocketNotchLog.system.warning("DisplayServices framework failed to load")
        }
        if getBrightness == nil {
            PocketNotchLog.system.warning("DisplayServicesGetBrightness symbol is unavailable")
        }
        if setBrightness == nil {
            PocketNotchLog.system.warning("DisplayServicesSetBrightness symbol is unavailable")
        }
    }

    deinit {
        if let frameworkHandle {
            dlclose(frameworkHandle)
        }
    }

    func currentBrightness() -> Double? {
        guard let getBrightness else {
            PocketNotchLog.system.warning("currentBrightness: DisplayServicesGetBrightness unavailable")
            return nil
        }
        var value: Float = 0
        let result = getBrightness(mainDisplayID, &value)
        guard result == 0, value.isFinite else {
            PocketNotchLog.system.warning(
                "currentBrightness: get failed (result=\(result, privacy: .public), value=\(value, privacy: .public))"
            )
            return nil
        }
        let brightness = Double(min(max(value, 0), 1))
        PocketNotchLog.system.info("currentBrightness -> \(brightness, privacy: .public)")
        return brightness
    }

    func perform(_ command: BrightnessCommand) -> Bool {
        guard let setBrightness, let current = currentBrightness() else {
            PocketNotchLog.system.warning("perform: setBrightness unavailable or current brightness unknown")
            return false
        }
        if let canChangeBrightness {
            let canChange = canChangeBrightness(mainDisplayID)
            PocketNotchLog.system.info("perform: canChangeBrightness -> \(canChange, privacy: .public)")
            guard canChange else { return false }
        }
        let target = BrightnessStep.target(from: current, command: command)
        let result = setBrightness(mainDisplayID, Float(target))
        PocketNotchLog.system.info(
            "perform: DisplayServicesSetBrightness(result=\(result, privacy: .public), target=\(target, privacy: .public))"
        )
        return result == 0
    }

    private static func loadSymbol<T>(_ name: String, from handle: UnsafeMutableRawPointer?, as type: T.Type) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }
}