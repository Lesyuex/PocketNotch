import AppKit
import Foundation

/// 「此刻」页用户信息（时间文案、问候语·用户名、头像数据）的共享读取逻辑。
/// NowSnapshotView 与右侧用户区共用，避免重复实现账户读取。
enum NowPageUserContent {
    static let userName: String = {
        let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? NSUserName() : full
    }()

    static func greeting(for date: Date) -> String {
        let base: String
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: base = "早上好"
        case 12..<18: base = "下午好"
        case 18..<24: base = "晚上好"
        default: base = "夜深了"
        }
        guard !userName.isEmpty else { return base }
        return "\(base)，\(userName)"
    }

    static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// 当前登录用户头像的 JPEG/图片数据（免权限读取）。失败返回 nil。
    static func avatarData() -> Data? {
        if let data = embeddedPhotoData() {
            return data
        }
        guard let path = picturePath() else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    /// 读取账户记录内嵌的 JPEGPhoto（真实账户头像，免权限）。失败返回 nil。
    private static func embeddedPhotoData() -> Data? {
        let hex = dsclValue("JPEGPhoto")
            .split(separator: "\n")
            .dropFirst()
            .joined()
            .filter(\.isHexDigit)
        guard !hex.isEmpty else { return nil }
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[index..<end], radix: 16) {
                data.append(byte)
            }
            index = end
        }
        return data.isEmpty ? nil : data
    }

    /// 通过 `dscl` 读取当前用户账户的指定属性（免权限）。失败返回空字符串。
    private static func dsclValue(_ attribute: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        process.arguments = [".", "-read", "/Users/\(NSUserName())", attribute]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 通过 `dscl` 读取账户照片路径（兜底）。失败返回 nil。
    private static func picturePath() -> String? {
        let lines = dsclValue("Picture")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return lines.first { !$0.isEmpty && $0 != "Picture:" } ?? nil
    }
}