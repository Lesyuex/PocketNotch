import Foundation

/// JSON Lines 文件 sink：每个事件追加一行 JSON，便于后续用 jq 等工具分析。
public final class JSONLFileSink: EventSink {
    private let fileURL: URL
    private let fileHandle: FileHandle?
    private let encoder: JSONEncoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        var handle: FileHandle?
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            handle = try FileHandle(forWritingTo: fileURL)
            try handle?.seekToEnd()
        } catch {
            handle = nil
        }
        self.fileHandle = handle
    }

    public func handle(_ event: AgentEvent) {
        guard let handle = fileHandle,
              let data = try? encoder.encode(event) else { return }
        var line = data
        line.append(0x0A)
        try? handle.write(contentsOf: line)
    }
}