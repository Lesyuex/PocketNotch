import Foundation

/// 归一化错误。
public enum AgentEventError: Error, Equatable {
    case unknownEventType(String)
    case invalidPayload(String)
}

/// 把来自不同 Agent 的原始 JSON 负载转换为统一的 `AgentEvent`。
///
/// 各家 CLI 上报的字段名存在差异，这里用一套宽松的字段桥接规则抽取
/// 必要信息（会话、类型、工具/文件/命令/消息、时间戳），并把事件名映射到
/// `EventType`。缺省而又可推断的字段会自动补全。
public enum AgentEventNormalizer {

    /// 会话 id 的候选字段名。
    private static let sessionIDKeys = ["sessionId", "session_id", "sessionID", "conversation_id", "thread_id"]
    /// 事件类型/名字的候选字段名。
    private static let typeKeys = ["event", "type", "name", "phase"]
    /// 工具名 / 动作名的候选字段名。
    private static let actionKeys = ["tool", "action", "step", "toolName", "tool_name"]
    /// 文件路径候选字段名。
    private static let fileKeys = ["file", "path", "filePath", "file_path"]
    /// 命令候选字段名。
    private static let commandKeys = ["command", "cmd", "bash", "shell"]
    /// 消息候选字段名。
    private static let messageKeys = ["message", "output", "detail", "summary", "text"]
    /// 产生 Hook 的桌面宿主名称候选字段名。
    private static let sourceApplicationKeys = ["sourceApplication", "source_application", "sourceApp", "source_app", "termProgram", "term_program"]
    /// 产生 Hook 的桌面宿主 bundle ID 候选字段名。
    private static let sourceBundleIdentifierKeys = ["sourceBundleIdentifier", "source_bundle_identifier", "sourceBundleId", "source_bundle_id"]
    /// 时间戳候选字段名。
    private static let timestampKeys = ["timestamp", "time", "ts", "created_at"]
    private static let pidKeys = ["pid", "processId", "process_id"]
    private static let parentPIDKeys = ["ppid", "parentPid", "parent_pid"]
    private static let exitCodeKeys = ["exitCode", "exit_code", "status"]
    private static let stopRequestedKeys = ["stopRequested", "stop_requested"]

    public static func normalize(agentID: String, payload: [String: Any]) throws -> AgentEvent {
        let agent = firstString(payload, ["agent", "company", "name"]) ?? canonical(agentID)
        let sessionId = firstString(payload, sessionIDKeys) ?? UUID().uuidString
        guard let rawType = firstString(payload, typeKeys), !rawType.isEmpty,
              let type = EventType(rawName: rawType) else {
            throw AgentEventError.unknownEventType(firstString(payload, typeKeys) ?? "missing")
        }

        return AgentEvent(
            id: firstString(payload, ["id", "eventId", "event_id"]) ?? UUID().uuidString,
            agent: agent,
            sessionId: sessionId,
            type: type,
            action: firstString(payload, actionKeys),
            file: firstString(payload, fileKeys),
            command: firstString(payload, commandKeys),
            message: firstString(payload, messageKeys),
            sourceApplication: firstString(payload, sourceApplicationKeys),
            sourceBundleIdentifier: firstString(payload, sourceBundleIdentifierKeys),
            pid: firstInt32(payload, pidKeys),
            parentPID: firstInt32(payload, parentPIDKeys),
            exitCode: firstInt32(payload, exitCodeKeys),
            stopRequested: firstBool(payload, stopRequestedKeys) ?? false,
            source: firstString(payload, ["source"]).flatMap(AgentEventSource.init(rawValue:)),
            timestamp: firstDate(payload, timestampKeys) ?? Date()
        )
    }

    // MARK: - Helpers

    private static func canonical(_ agentID: String) -> String {
        agentID.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "cli", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func firstString(_ payload: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = payload[key] {
                if let string = value as? String, !string.isEmpty { return string }
                if let number = value as? NSNumber { return String(describing: number) }
            }
        }
        return nil
    }

    private static func firstDate(_ payload: [String: Any], _ keys: [String]) -> Date? {
        for key in keys {
            guard let value = payload[key] else { continue }
            switch value {
            case let number as NSNumber:
                return Date(timeIntervalSince1970: number.doubleValue)
            case let string as String:
                if let seconds = Double(string) { return Date(timeIntervalSince1970: seconds) }
                if let date = ISO8601DateFormatter().date(from: string) { return date }
                if let date = Self.rfc3339Formatter.date(from: string) { return date }
            default:
                continue
            }
        }
        return nil
    }

    private static func firstInt32(_ payload: [String: Any], _ keys: [String]) -> Int32? {
        for key in keys {
            guard let value = payload[key] else { continue }
            switch value {
            case let number as NSNumber:
                return number.int32Value
            case let string as String:
                if let value = Int32(string) { return value }
            default:
                continue
            }
        }
        return nil
    }

    private static func firstBool(_ payload: [String: Any], _ keys: [String]) -> Bool? {
        for key in keys {
            guard let value = payload[key] else { continue }
            switch value {
            case let bool as Bool:
                return bool
            case let number as NSNumber:
                return number.boolValue
            case let string as String:
                switch string.lowercased() {
                case "1", "true", "yes":
                    return true
                case "0", "false", "no":
                    return false
                default:
                    continue
                }
            default:
                continue
            }
        }
        return nil
    }

    private static let rfc3339Formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }()
}
