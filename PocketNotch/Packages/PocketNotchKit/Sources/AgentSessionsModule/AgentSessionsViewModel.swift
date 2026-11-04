import Foundation

struct AgentSessionInfo: Identifiable, Hashable, Sendable {
    let id: Int
    let agentName: String
    let sessionName: String
    let pid: Int
    let parentPid: Int
    let parentName: String
}

private struct ScriptResult: Sendable {
    let sessions: [AgentSessionInfo]
    let error: String?
}

@MainActor
final class AgentSessionsViewModel: ObservableObject {
    @Published var sessions: [AgentSessionInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let pythonScriptPath: String

    init() {
        let bundle = Bundle.module
        pythonScriptPath = bundle.path(forResource: "get_agent_sessions", ofType: "py") ?? ""
    }

    func refresh() {
        guard !pythonScriptPath.isEmpty else {
            errorMessage = "Python script not found"
            return
        }
        isLoading = true
        errorMessage = nil

        let scriptPath = pythonScriptPath
        Task {
            do {
                let result = try await Self.runScript(scriptPath: scriptPath)
                self.sessions = result.sessions
                self.errorMessage = result.error
            } catch {
                self.sessions = []
                self.errorMessage = "Refresh failed: \(error.localizedDescription)"
            }
            self.isLoading = false
        }
    }

    private static nonisolated func runScript(
        scriptPath: String
    ) throws -> ScriptResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptPath]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            return ScriptResult(sessions: [], error: "Script error: \(stderr.isEmpty ? output : stderr)")
        }

        guard let jsonData = output.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return ScriptResult(sessions: [], error: "Failed to parse JSON")
        }

        let parsed = jsonArray.compactMap { dict -> AgentSessionInfo? in
            guard let pid = dict["pid"] as? Int,
                  let agentName = dict["agent_name"] as? String,
                  let sessionName = dict["session_name"] as? String,
                  let parentPid = dict["parent_pid"] as? Int,
                  let parentName = dict["parent_name"] as? String else {
                return nil
            }
            return AgentSessionInfo(
                id: pid,
                agentName: agentName,
                sessionName: sessionName,
                pid: pid,
                parentPid: parentPid,
                parentName: parentName
            )
        }

        return ScriptResult(sessions: parsed, error: nil)
    }
}
