import AppKit
import CoreAudio
import Darwin
import Foundation

protocol AudioProcessActivityProviding: Sendable {
    func isProducingOutput(forAppPID pid: Int32) -> Bool?
}

final class AudioProcessActivityReader: AudioProcessActivityProviding, @unchecked Sendable {
    func isProducingOutput(forAppPID pid: Int32) -> Bool? {
        guard pid > 0, let outputPIDs = producingOutputPIDs() else { return nil }

        let sourceApplication = NSRunningApplication(processIdentifier: pid)
        for outputPID in outputPIDs {
            if outputPID == pid || isRelatedAudioProcess(
                outputPID,
                sourceApplication: sourceApplication
            ) {
                return true
            }
        }

        return false
    }

    /// 返回当前真正输出声音的常规应用。浏览器通常由 Helper 子进程写入音频，
    /// `isProducingOutput` 会把这些子进程归属回浏览器主进程。
    func producingOutputApplications(excludingPID: Int32? = nil) -> [NSRunningApplication] {
        guard let outputPIDs = producingOutputPIDs() else { return [] }
        return NSWorkspace.shared.runningApplications.filter { application in
            let pid = application.processIdentifier
            guard pid > 0,
                  pid != excludingPID,
                  !application.isTerminated,
                  application.activationPolicy == .regular else {
                return false
            }
            return outputPIDs.contains { outputPID in
                outputPID == pid || isRelatedAudioProcess(
                    outputPID,
                    sourceApplication: application
                )
            }
        }
    }

    func preferredProducingOutputApplication(
        excludingPID: Int32? = nil,
        preferredPIDs: [Int32] = []
    ) -> NSRunningApplication? {
        let applications = producingOutputApplications(excludingPID: excludingPID)
        for preferredPID in preferredPIDs {
            if let preferred = applications.first(where: {
                $0.processIdentifier == preferredPID
            }) {
                return preferred
            }
        }
        if let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let frontmost = applications.first(where: { $0.processIdentifier == frontmostPID }) {
            return frontmost
        }
        return applications.sorted { lhs, rhs in
            let lhsIdentity = lhs.bundleIdentifier ?? lhs.localizedName ?? ""
            let rhsIdentity = rhs.bundleIdentifier ?? rhs.localizedName ?? ""
            if lhsIdentity != rhsIdentity { return lhsIdentity < rhsIdentity }
            return lhs.processIdentifier < rhs.processIdentifier
        }.first
    }

    private func producingOutputPIDs() -> [Int32]? {
        guard let processObjects = processObjects() else { return nil }
        return processObjects.compactMap { objectID in
            guard readUInt32(objectID, selector: kAudioProcessPropertyIsRunningOutput) == 1 else {
                return nil
            }
            return readPID(objectID)
        }
    }

    private func processObjects() -> [AudioObjectID]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            systemObject,
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return nil
        }

        var objects = [AudioObjectID](
            repeating: 0,
            count: Int(size) / MemoryLayout<AudioObjectID>.size
        )
        guard AudioObjectGetPropertyData(
            systemObject,
            &address,
            0,
            nil,
            &size,
            &objects
        ) == noErr else {
            return nil
        }
        return objects
    }

    private func readPID(_ objectID: AudioObjectID) -> Int32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            &pid
        ) == noErr else {
            return nil
        }
        return Int32(pid)
    }

    private func readUInt32(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            &value
        ) == noErr else {
            return nil
        }
        return value
    }

    private func isRelatedAudioProcess(
        _ outputPID: Int32,
        sourceApplication: NSRunningApplication?
    ) -> Bool {
        guard let sourceApplication else { return false }

        // 优先通过 NSRunningApplication 获取输出进程信息（常规应用）
        if let outputApplication = NSRunningApplication(processIdentifier: outputPID) {
            if let sourceBundleIdentifier = sourceApplication.bundleIdentifier,
               sourceBundleIdentifier == outputApplication.bundleIdentifier {
                return true
            }

            if let sourceName = sourceApplication.localizedName,
               let outputName = outputApplication.localizedName {
                // 直接名称匹配或前缀匹配（如 "Google Chrome" → "Google Chrome Helper"）
                if outputName == sourceName || outputName.hasPrefix(sourceName + " ") {
                    return true
                }

                // 补充匹配：bundleIdentifier 后缀匹配
                if let sourceBundle = sourceApplication.bundleIdentifier,
                   let outputBundle = outputApplication.bundleIdentifier,
                   sourceBundle.count > 0, outputBundle.count > 0 {
                    if sourceBundle == "com.apple.Safari",
                       outputBundle == "com.apple.WebKit.WebContent" {
                        return true
                    }
                }
            }
        }

        // 当 NSRunningApplication 无法识别输出进程时（如 Chrome 的音频辅助进程
        // utility-sub-type=audio.mojom.AudioService），通过 proc_pidpath 获取进程路径
        // 来匹配主应用名称。
        guard let sourceName = sourceApplication.localizedName,
              let outputPath = processPath(for: outputPID) else {
            return false
        }

        // 从路径中提取应用名称（如 "Google Chrome"）
        // 路径格式: /Applications/Google Chrome.app/Contents/Frameworks/.../Google Chrome Helper.app/...
        let pathComponents = outputPath.split(separator: "/")
        for component in pathComponents {
            if component.hasSuffix(".app") {
                let appName = component.dropLast(4) // 去掉 .app 后缀
                // 检查应用名是否包含主应用名称（如 "Google Chrome Helper" 包含 "Google Chrome"）
                if appName == sourceName || appName.hasPrefix(sourceName + " ") {
                    return true
                }
            }
        }

        return false
    }

    /// 通过 proc_pidpath 获取进程的可执行文件路径
    private func processPath(for pid: Int32) -> String? {
        var buf = [Int8](repeating: 0, count: Int(MAXPATHLEN))
        let len = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard len > 0 else { return nil }
        return String(cString: buf)
    }
}
