import Foundation

/// Agent 运行的「事实事件」类型。
///
/// 这里只描述 Agent 发生了什么，不代表 UI 状态、优先级或展示方式
/// （那些由更上层的 State Manager / Activity Scheduler 决定）。
public enum EventType: String, Codable, Sendable, CaseIterable {
    /// 会话开始
    case sessionStart
    /// 会话被正常关闭
    case sessionEnd
    /// Agent 开始运行
    case agentStart
    /// 思考中
    case thinking
    /// 开始使用工具
    case toolStart
    /// 工具执行结束
    case toolEnd
    /// 开始执行命令
    case commandStart
    /// 命令执行结束
    case commandEnd
    /// 等待用户确认
    case waitingApproval
    /// 任务已完成
    case completed
    /// 任务失败
    case failed
    /// 用户或外部发起停止请求
    case stopRequested
}

extension EventType {
    /// 从各家 Agent 私有事件名归一化到统一事件类型。
    /// 兼容 snake_case / camelCase / kebab-case 等多种写法。
    public init?(rawName: String) {
        switch rawName.lowercased() {
        case "sessionstart", "session_start", "session-start", "session.started", "session_started", "session.init":
            self = .sessionStart
        case "sessionend", "session_end", "session-end", "session.ended", "session_ended", "session.close", "session_closed":
            self = .sessionEnd
        case "agentstart", "agent_start", "agent-start", "agent.started", "agent_started":
            self = .agentStart
        case "thinking", "think", "thinking.start":
            self = .thinking
        case "toolstart", "tool_start", "tool-start", "tool.started", "tool_use":
            self = .toolStart
        case "toolend", "tool_end", "tool-end", "tool.finished":
            self = .toolEnd
        case "commandstart", "command_start", "command-start", "command.started", "cmd_start":
            self = .commandStart
        case "commandend", "command_end", "command-end", "command.finished", "cmd_end":
            self = .commandEnd
        case "waitingapproval", "waiting_approval", "waiting-approval", "waiting_for_approval",
             "approval_required", "permission_required", "waitinguser", "waiting-user", "await_approval":
            self = .waitingApproval
        case "completed", "complete", "done", "finished", "task_completed", "task_complete", "agent.finished":
            self = .completed
        case "failed", "fail", "failure", "error", "task_failed", "agent.failed", "aborted":
            self = .failed
        case "stoprequested", "stop_requested", "stop-requested", "stop", "terminate_requested":
            self = .stopRequested
        default:
            return nil
        }
    }
}
