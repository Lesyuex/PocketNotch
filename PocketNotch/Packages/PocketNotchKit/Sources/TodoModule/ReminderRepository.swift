import EventKit
import Foundation
import OSLog

enum ReminderRepositoryError: LocalizedError {
    case noReminderList
    case saveFailed(calendarTitle: String, underlying: String)

    var errorDescription: String? {
        switch self {
        case .noReminderList:
            return "未找到可用的提醒列表，请在「提醒事项」中先创建一个列表。"
        case .saveFailed(let calendarTitle, let underlying):
            return "写入提醒列表「\(calendarTitle)」失败：\(underlying)"
        }
    }
}

/// 提醒事项授权状态（EventKit 类型的轻量映射，避免把 EventKit 泄漏到业务层）。
enum ReminderAuthorizationState {
    case notDetermined, authorized, denied, restricted
}

/// 提醒事项数据边界。EventKit 只存在于本层的 `EventKitReminderRepository`，
/// 其余代码通过该协议读取/写入系统日历。
protocol ReminderRepository: AnyObject {
    /// 系统提醒/日历数据发生外部变化（如系统 App 里改动）时回调。
    var onDidChange: (() -> Void)? { get set }
    func requestAccess() async -> Bool
    /// 请求完成后的最终授权状态，用于给用户针对性的引导（基于提醒事项权限）。
    func authorizationState() async -> ReminderAuthorizationState
    /// 拉取指定日期内所有未完成的提醒事项（无截止时间的提醒只出现在「今天」）。
    func fetchPending(on date: Date) async throws -> [TodoItem]
    /// 拉取指定日期开始的事件/日程（含全天日程），只读展示。
    func fetchEvents(on date: Date) async throws -> [TodoItem]
    /// 可写的提醒列表（供新增/编辑时选择目标列表）。
    func fetchLists() async throws -> [ReminderListInfo]
    /// 新建提醒列表并返回其快照。
    func addList(title: String) async throws -> ReminderListInfo
    func add(title: String, dueDate: Date, hasTime: Bool, notes: String, listID: String?) async throws
    func update(
        id: String,
        title: String,
        dueDate: Date?,
        hasTime: Bool,
        notes: String,
        listID: String?
    ) async throws
    func setCompleted(_ id: String, completed: Bool) async throws
    func remove(id: String) async throws
}

/// 提醒列表的轻量快照（选择目标列表用）。
struct ReminderListInfo: Equatable, Sendable {
    let id: String
    let title: String
    let isDefault: Bool
}

/// EventKit 实现：把系统「提醒事项」当作待办数据源，不做本地落盘。
final class EventKitReminderRepository: ReminderRepository {
    private var store = EKEventStore()
    private var changeObserver: NSObjectProtocol?

    var onDidChange: (() -> Void)?

    init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.onDidChange?()
        }
    }

    deinit {
        guard let changeObserver else { return }
        NotificationCenter.default.removeObserver(changeObserver)
    }

    func requestAccess() async -> Bool {
        let remindersGranted = await withCheckedContinuation { continuation in
            store.requestFullAccessToReminders { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        TodoTrace.log("requestReminders granted=\(remindersGranted) status=\(String(describing: EKEventStore.authorizationStatus(for: .reminder)))")
        // 日历日程是可选项：请求失败/拒绝只影响日程展示，不阻塞待办。
        let eventsGranted = await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        TodoTrace.log("requestEvents granted=\(eventsGranted) status=\(String(describing: EKEventStore.authorizationStatus(for: .event)))")
        return remindersGranted
    }

    func authorizationState() async -> ReminderAuthorizationState {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: return .notDetermined
        case .authorized, .writeOnly, .fullAccess: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .notDetermined
        }
    }

    func fetchPending(on date: Date) async throws -> [TodoItem] {
        let reminders = try await allReminders()
        let calendar = Calendar.current
        let result = reminders
            // 展示该日期下的全部状态（含已完成，UI 以删除线区分）。
            .filter { reminder in
                guard let due = Self.dueDate(reminder) else {
                    return calendar.isDateInToday(date)
                }
                return calendar.isDate(due, inSameDayAs: date)
            }
            .sorted { Self.dueDate($0) ?? .distantFuture < Self.dueDate($1) ?? .distantFuture }
            .map { todoItem(from: $0) }
        if result.isEmpty && !reminders.isEmpty {
            // 有提醒但当天没有匹配项：可能是它们都带非今天日期，属预期。
            Logger(subsystem: "com.pocketnotch.app", category: "todo")
                .info("\(reminders.count) total, none on \(date, privacy: .public)")
        }
        return result
    }

    func fetchEvents(on date: Date) async throws -> [TodoItem] {
        guard calendarsAccessible else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: nil
        )
        return store.events(matching: predicate)
            .filter { event in
                guard !event.isAllDay else { return true }
                return event.startDate >= start && event.startDate < end
            }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                TodoItem(
                    id: "evt-\(event.eventIdentifier ?? "")",
                    title: event.title,
                    createdAt: event.creationDate ?? .now,
                    dueDate: event.startDate,
                    hasTime: !event.isAllDay,
                    listID: event.calendar?.calendarIdentifier,
                    listTitle: event.calendar?.title,
                    kind: .calendarEvent
                )
            }
    }

    func add(title: String, dueDate: Date, hasTime: Bool, notes: String, listID: String?) async throws {
        TodoTrace.log("repo.add begin cals=\(self.store.calendars(for: .reminder).count) default=\(self.store.defaultCalendarForNewReminders()?.title ?? "nil")")
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        let calendar = calendar(withID: listID)
            ?? store.defaultCalendarForNewReminders()
            ?? store.calendars(for: .reminder).first(where: { $0.allowsContentModifications })
            ?? store.calendars(for: .reminder).first
        guard let calendar else {
            TodoTrace.log("repo.add FAILED no writable list")
            throw ReminderRepositoryError.noReminderList
        }
        reminder.calendar = calendar
        if hasTime {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        } else {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day],
                from: dueDate
            )
        }
        do {
            try store.save(reminder, commit: true)
            TodoTrace.log("repo.add saved title=\(title) cal=\(calendar.title) writeok=\(calendar.allowsContentModifications)")
        } catch {
            TodoTrace.log("repo.add save FAILED \(String(describing: error)) -> fresh store retry")
            // 旧 store 长时间运行后可能写不进，用全新 store 重试一次。
            try await retryAddWithFreshStore(title: title, dueDate: dueDate, hasTime: hasTime, notes: notes, listID: listID)
        }
    }

    private func retryAddWithFreshStore(title: String, dueDate: Date, hasTime: Bool, notes: String, listID: String?) async throws {
        let fresh = EKEventStore()
        TodoTrace.log("repo.fresh-store begin cals=\(fresh.calendars(for: .reminder).count) default=\(fresh.defaultCalendarForNewReminders()?.title ?? "nil")")
        let reminder = EKReminder(eventStore: fresh)
        reminder.title = title
        reminder.notes = notes
        let calendar = fresh.calendar(withIdentifier: listID ?? "")
            ?? fresh.defaultCalendarForNewReminders()
            ?? fresh.calendars(for: .reminder).first(where: { $0.allowsContentModifications })
            ?? fresh.calendars(for: .reminder).first
        guard let calendar else {
            TodoTrace.log("repo.fresh-store FAILED no writable list")
            throw ReminderRepositoryError.noReminderList
        }
        reminder.calendar = calendar
        if hasTime {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        } else {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day],
                from: dueDate
            )
        }
        do {
            try fresh.save(reminder, commit: true)
            TodoTrace.log("repo.fresh-store saved title=\(title) cal=\(calendar.title)")
            self.store = fresh
        } catch {
            TodoTrace.log("repo.fresh-store FAILED \(String(describing: error))")
            throw ReminderRepositoryError.saveFailed(
                calendarTitle: calendar.title,
                underlying: error.localizedDescription
            )
        }
    }

    func update(
        id: String,
        title: String,
        dueDate: Date?,
        hasTime: Bool,
        notes: String,
        listID: String?
    ) async throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.title = title
        reminder.notes = notes
        if let listID, listID != reminder.calendar?.calendarIdentifier,
           let target = store.calendar(withIdentifier: listID) {
            reminder.calendar = target
        }
        if let dueDate {
            if hasTime {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: dueDate
                )
            } else {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day],
                    from: dueDate
                )
            }
        } else {
            reminder.dueDateComponents = nil
        }
        try store.save(reminder, commit: true)
    }

    func setCompleted(_ id: String, completed: Bool) async throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = completed
        reminder.completionDate = completed ? .now : nil
        try store.save(reminder, commit: true)
    }

    func remove(id: String) async throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        try store.remove(reminder, commit: true)
    }

    private var calendarsAccessible: Bool {
        if #available(macOS 14.0, *) {
            return EKEventStore.authorizationStatus(for: .event) == .fullAccess
        }
        return EKEventStore.authorizationStatus(for: .event) != .denied
    }

    func fetchLists() async throws -> [ReminderListInfo] {
        let defaultID = store.defaultCalendarForNewReminders()?.calendarIdentifier
        return store.calendars(for: .reminder)
            .filter { $0.allowsContentModifications }
            .map {
                ReminderListInfo(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    isDefault: $0.calendarIdentifier == defaultID
                )
            }
    }

    func addList(title: String) async throws -> ReminderListInfo {
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = title
        // 新列表必须有归属账户：优先系统默认列表的账户，其次 iCloud/本地账户。
        let source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV })
            ?? store.sources.first(where: { $0.sourceType == .local })
            ?? store.sources.first
        guard let source else {
            throw ReminderRepositoryError.noReminderList
        }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        TodoTrace.log("repo.addList saved title=\(title) source=\(source.title)")
        return ReminderListInfo(id: calendar.calendarIdentifier, title: title, isDefault: false)
    }

    /// 按 id 找可写的提醒列表；找不到返回 nil（调用方回退默认列表）。
    private func calendar(withID listID: String?) -> EKCalendar? {
        guard let listID else { return nil }
        return store.calendar(withIdentifier: listID).flatMap { calendar -> EKCalendar? in
            calendar.allowsContentModifications ? calendar : nil
        }
    }

    private func allReminders() async throws -> [EKReminder] {
        let predicate = store.predicateForReminders(in: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { fetched in
                continuation.resume(returning: fetched ?? [])
            }
        }
    }

    private static func dueDate(_ reminder: EKReminder) -> Date? {
        reminder.dueDateComponents?.date
    }

    private func todoItem(from reminder: EKReminder) -> TodoItem {
        let components = reminder.dueDateComponents
        return TodoItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            isCompleted: reminder.isCompleted,
            createdAt: reminder.creationDate ?? .now,
            dueDate: components?.date,
            hasTime: components?.hour != nil && components?.minute != nil,
            notes: reminder.notes ?? "",
            listID: reminder.calendar?.calendarIdentifier,
            listTitle: reminder.calendar?.title
        )
    }
}