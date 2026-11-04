import Foundation

struct MediaRemoteProcessResult {
    let output: String?
    let error: String?
}

/// 统一执行媒体降级所需的系统子进程，集中处理 stdin、退出码和 stderr。
enum MediaRemoteProcessRunner {
    static func runOsaScript(_ script: String) -> MediaRemoteProcessResult {
        run(
            executablePath: "/usr/bin/osascript",
            standardInput: script,
            startupErrorPrefix: "osascript 启动失败",
            emptyOutputIsNil: false
        )
    }

    static func runSwiftSnippet(_ source: String) -> MediaRemoteProcessResult {
        run(
            executablePath: "/usr/bin/swift",
            arguments: ["-e", source],
            startupErrorPrefix: "swift helper 启动失败",
            emptyOutputIsNil: true
        )
    }

    private static func run(
        executablePath: String,
        arguments: [String] = [],
        standardInput: String? = nil,
        startupErrorPrefix: String,
        emptyOutputIsNil: Bool
    ) -> MediaRemoteProcessResult {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        let input = standardInput == nil ? nil : Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        var outputData = Data()
        var errorData = Data()
        let outputQueue = DispatchQueue(label: "pocketnotch.processRunner.output")
        let errorQueue = DispatchQueue(label: "pocketnotch.processRunner.error")
        outputQueue.async { outputData = output.fileHandleForReading.readDataToEndOfFile() }
        errorQueue.async { errorData = error.fileHandleForReading.readDataToEndOfFile() }

        do {
            try process.run()
            if let standardInput, let input {
                input.fileHandleForWriting.write(Data(standardInput.utf8))
                input.fileHandleForWriting.closeFile()
            }
            process.waitUntilExit()
        } catch {
            outputQueue.sync {}
            errorQueue.sync {}
            return MediaRemoteProcessResult(
                output: nil,
                error: "\(startupErrorPrefix)：\(error.localizedDescription)"
            )
        }

        outputQueue.sync {}
        errorQueue.sync {}

        let outputText = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            let errorText = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let executableName = URL(fileURLWithPath: executablePath).lastPathComponent
            return MediaRemoteProcessResult(
                output: nil,
                error: errorText?.isEmpty == false
                    ? errorText
                    : "\(executableName) 退出码 \(process.terminationStatus)"
            )
        }

        let normalizedOutput = emptyOutputIsNil && outputText?.isEmpty != false ? nil : outputText
        return MediaRemoteProcessResult(output: normalizedOutput, error: nil)
    }
}
