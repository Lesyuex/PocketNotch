import Foundation

/// 待办事项来源：系统「提醒事项」（可勾选/删除）或系统「日历」日程（只读展示）。
enum TodoItemKind: Equatable, Sendable {
    case reminder
    case calendarEvent
}

/// 一条待办事项：系统「提醒事项」/「日历日程」的轻量快照。
/// 提醒按 `id`（calendar item identifier）关联回 EventKit；日程的 id 为 event identifier。
struct TodoItem: Identifiable, Equatable {
    let id: String
    var title: String
    var isCompleted: Bool
    let createdAt: Date
    /// 截止时间（提醒的 dueDate / 日程的开始时间）；无时间的条目为 nil（仅日期提醒）。
    var dueDate: Date?
    /// 是否带有具体时分（区分「仅日期」与「日期+时间」）。
    var hasTime: Bool
    /// 备注（提醒事项的 notes 字段）。
    var notes: String
    /// 所属提醒列表的 id（写入/移动目标）；nil 表示跟随系统默认列表。
    var listID: String?
    /// 所属提醒列表名称（仅展示用）；日程为其所在日历名。
    var listTitle: String?
    /// 来源类型：决定交互（提醒可勾选/删除，日程只读）。
    var kind: TodoItemKind

    init(
        id: String,
        title: String,
        isCompleted: Bool = false,
        createdAt: Date = Date.now,
        dueDate: Date? = nil,
        hasTime: Bool = false,
        notes: String = "",
        listID: String? = nil,
        listTitle: String? = nil,
        kind: TodoItemKind = .reminder
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.hasTime = hasTime
        self.notes = notes
        self.listID = listID
        self.listTitle = listTitle
        self.kind = kind
    }

    /// 紧凑时间文案（如 "10:30"），无具体时分时返回 nil。
    var timeText: String? {
        guard hasTime, let dueDate else { return nil }
        return dueDate.formatted(
            .dateTime.hour(.defaultDigits(amPM: .omitted)).minute(.defaultDigits)
        )
    }

    /// 日程为只读：不参与完成勾选。
    var isToggleable: Bool { kind == .reminder }

    /// 日程为只读：不提供删除。
    var isDeletable: Bool { kind == .reminder }
}