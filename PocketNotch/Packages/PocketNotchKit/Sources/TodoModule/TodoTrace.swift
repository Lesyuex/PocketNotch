import Foundation
import os

/// 待办链路的文件追踪：追加写入 ~/Library/Logs/PocketNotch/pocketnotch-todo.log，
/// 免去 Console 过滤；同时保留 OSLog 到统一日志。
enum TodoTrace {
    private static let queue = DispatchQueue(label: "com.pocketnotch.app.todotrace")
    private static let logger = Logger(subsystem: "com.pocketnotch.app", category: "todo")
    private static let url = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/PocketNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pocketnotch-todo.log")
    }()

    static func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
        queue.async {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            let line = "[\(formatter.string(from: Date()))] \(message)\n"
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
            }
        }
    }
}