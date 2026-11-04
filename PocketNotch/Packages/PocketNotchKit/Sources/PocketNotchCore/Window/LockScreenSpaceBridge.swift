import AppKit
import Darwin
import Foundation
import PocketNotchShared

/// Hosts content-sized lock-screen panels above loginwindow. Keep the Space
/// alive across lock cycles and order out its panels on unlock; tearing down
/// a system-level Space is unnecessary during the desktop transition.
@MainActor
public final class LockScreenSpaceBridge {
    public static let shared = LockScreenSpaceBridge()

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsToSpace = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private var frameworkHandle: UnsafeMutableRawPointer?
    private var connection: Int32?
    private var lockScreenSpace: Int32?
    private var addWindowsToSpace: AddWindowsToSpace?
    private var attemptedPrivateSpace = false

    private init() {}

    private func ensurePrivateSpace() -> Bool {
        guard !attemptedPrivateSpace else { return isAvailable }
        attemptedPrivateSpace = true
        guard frameworkHandle == nil, lockScreenSpace == nil else {
            return isAvailable
        }

        let frameworkPath = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
        guard let frameworkHandle = dlopen(frameworkPath, RTLD_NOW),
              let mainConnection: MainConnectionID = Self.loadSymbol(
                "SLSMainConnectionID",
                from: frameworkHandle
              ),
              let createSpace: SpaceCreate = Self.loadSymbol(
                "SLSSpaceCreate",
                from: frameworkHandle
              ),
              let setAbsoluteLevel: SpaceSetAbsoluteLevel = Self.loadSymbol(
                "SLSSpaceSetAbsoluteLevel",
                from: frameworkHandle
              ),
              let showSpaces: ShowSpaces = Self.loadSymbol(
                "SLSShowSpaces",
                from: frameworkHandle
              ),
              let addWindows: AddWindowsToSpace = Self.loadSymbol(
                "SLSSpaceAddWindowsAndRemoveFromSpaces",
                from: frameworkHandle
              ) else {
            PocketNotchLog.core.error("Lock-screen Space unavailable: required SkyLight symbol missing")
            return false
        }

        let connection = mainConnection()
        let space = createSpace(connection, 1, 0)
        guard connection != 0, space != 0 else {
            PocketNotchLog.core.error("Lock-screen Space creation failed")
            return false
        }

        // Matches Notification Center's lock-screen layer used by SkyLightWindow.
        let notificationCenterAtScreenLockLevel: Int32 = 400
        let levelResult = setAbsoluteLevel(
            connection,
            space,
            notificationCenterAtScreenLockLevel
        )
        let showResult = showSpaces(connection, [space] as CFArray)
        PocketNotchLog.core.info(
            "Lock-screen Space initialized: space=\(space, privacy: .public) levelResult=\(levelResult, privacy: .public) showResult=\(showResult, privacy: .public)"
        )

        self.frameworkHandle = frameworkHandle
        self.connection = connection
        lockScreenSpace = space
        addWindowsToSpace = addWindows
        return true
    }

    public var isAvailable: Bool {
        frameworkHandle != nil
            && connection != nil
            && lockScreenSpace != nil
            && addWindowsToSpace != nil
    }

    @discardableResult
    public func delegateWindow(_ window: NSWindow) -> Bool {
        let windowNumber = window.windowNumber
        guard windowNumber > 0 else { return false }
        guard ensurePrivateSpace(),
              let connection,
              let lockScreenSpace,
              let addWindowsToSpace else {
            return false
        }

        let result = addWindowsToSpace(
            connection,
            lockScreenSpace,
            [windowNumber] as CFArray,
            7
        )
        PocketNotchLog.core.info(
            "Lock-screen window delegated: window=\(windowNumber, privacy: .public) space=\(lockScreenSpace, privacy: .public) result=\(result, privacy: .public)"
        )
        return true
    }

    private static func loadSymbol<T>(
        _ name: String,
        from handle: UnsafeMutableRawPointer
    ) -> T? {
        guard let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }
}
