import Foundation
import Observation
import OSLog

/// 待办数据源：直接读写系统「提醒事项」（EventKit），不做本地落盘/降级。
/// 默认展示「今天」的提醒，可通过选择日期切换；增删改后立即刷新，
/// 系统侧改动通过 `onDidChange` 自动同步。
@MainActor
@Observable
final class TodoStore {
    private(set) var items: [TodoItem] = []
    private(set) var isAuthorized = false
    /// 当前授权状态，用于决定错误行的引导方式（请求权限 vs 前往设置）。
    private(set) var authorizationState: ReminderAuthorizationState = .notDetermined
    /// 最近一次写/读失败的原因，成功操作后清空。nil 表示一切正常。
    private(set) var errorMessage: String?
    /// 最近一次 add 的逐步印迹，用于联调排查（后续可移除）。
    private(set) var lastAddStep = ""
    /// 当前选中的日期（默认今天），展示该日期的待办。
    private(set) var selectedDate: Date
    /// 可写的提醒列表（供新增/编辑时选择目标列表）。
    private(set) var reminderLists: [ReminderListInfo] = []
    /// 系统默认提醒列表 id；无默认时取第一个可写列表。
    private(set) var defaultListID: String?

    private let repository: ReminderRepository
    private let logger = Logger(subsystem: "com.pocketnotch.app", category: "todo")

    init(
        repository: ReminderRepository = EventKitReminderRepository(),
        selectedDate: Date = .now
    ) {
        self.repository = repository
        self.selectedDate = Calendar.current.startOfDay(for: selectedDate)
        repository.onDidChange = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                await self.refresh()
            }
        }
    }

    var pendingCount: Int {
        items.lazy.filter { !$0.isCompleted }.count
    }

    /// 首次启动请求系统权限并加载。已授权时重复调用不会再次弹窗；
    /// 从系统设置改完权限回到 App 后可再次调用以自动恢复。
    func prepare() async {
        let granted = await repository.requestAccess()
        isAuthorized = granted
        authorizationState = await repository.authorizationState()
        if granted {
            errorMessage = nil
            do {
                let lists = try await repository.fetchLists()
                reminderLists = lists
                defaultListID = lists.first(where: { $0.isDefault })?.id ?? lists.first?.id
            } catch {
                logger.error("fetch reminder lists failed: \(error)")
            }
        } else {
            switch authorizationState {
            case .denied, .restricted:
                errorMessage = "请在「系统设置 → 隐私与安全性 → 提醒事项」中允许 PocketNotch，返回后自动恢复。"
                logger.error("reminders access denied/restricted")
            case .notDetermined, .authorized:
                errorMessage = "需要「提醒事项」权限才能同步待办。"
                logger.error("reminders access not granted")
            }
        }
        await refresh()
    }

    /// 切换到指定日期并加载该日期的待办。
    func selectDate(_ date: Date) async {
        selectedDate = Calendar.current.startOfDay(for: date)
        await refresh()
    }

    func add(
        title: String,
        notes: String = "",
        hasTime: Bool = false,
        dueDate: Date? = nil,
        listID: String? = nil
    ) async {
        lastAddStep = "store.add entered"
        TodoTrace.log("store.add ENTERED")
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastAddStep = "store.add ignored blank"
            return
        }
        let dateToUse = dueDate ?? selectedDate
        lastAddStep = "store.add will-save title=\(trimmed) date=\(dateToUse)"
        TodoTrace.log("store.add will-save title=\(trimmed) date=\(dateToUse)")
        do {
            try await repository.add(
                title: trimmed,
                dueDate: dateToUse,
                hasTime: hasTime,
                notes: notes,
                listID: listID
            )
            errorMessage = nil
            lastAddStep = "store.add saved OK"
            TodoTrace.log("store.add saved OK")
        } catch {
            reportError(error, op: "add")
        }
        await refresh()
    }

    func update(
        id: String,
        title: String,
        notes: String? = nil,
        hasTime: Bool? = nil,
        dueDate: Date? = nil,
        listID: String? = nil
    ) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let item = items.first(where: { $0.id == id }) else { return }
        let finalHasTime = hasTime ?? item.hasTime
        var finalDueDate = dueDate ?? item.dueDate
        if !finalHasTime, let existing = finalDueDate {
            finalDueDate = Calendar.current.startOfDay(for: existing)
        }
        do {
            try await repository.update(
                id: id,
                title: trimmed,
                dueDate: finalDueDate,
                hasTime: finalHasTime,
                notes: notes ?? item.notes,
                listID: listID ?? item.listID
            )
            errorMessage = nil
        } catch {
            reportError(error, op: "update")
        }
        await refresh()
    }

    /// 新建提醒列表；成功返回新列表快照（供 composer 直接选中），失败返回 nil。
    @discardableResult
    func addList(title: String) async -> ReminderListInfo? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let created = try await repository.addList(title: trimmed)
            let lists = (try? await repository.fetchLists()) ?? reminderLists
            if !lists.isEmpty {
                reminderLists = lists
                defaultListID = lists.first(where: { $0.isDefault })?.id ?? lists.first?.id
            } else {
                reminderLists.append(created)
                defaultListID = defaultListID ?? created.id
            }
            errorMessage = nil
            return created
        } catch {
            reportError(error, op: "addList")
            return nil
        }
    }

    func toggle(_ id: String) async {
        guard let item = items.first(where: { $0.id == id }), item.isToggleable else { return }
        do {
            try await repository.setCompleted(id, completed: !item.isCompleted)
            errorMessage = nil
        } catch {
            reportError(error, op: "toggle")
        }
        await refresh()
    }

    func remove(_ id: String) async {
        guard items.first(where: { $0.id == id })?.isDeletable == true else { return }
        do {
            try await repository.remove(id: id)
            errorMessage = nil
        } catch {
            reportError(error, op: "remove")
        }
        await refresh()
    }

    private func refresh() async {
        guard isAuthorized else {
            items = []
            return
        }
        var reminders: [TodoItem] = []
        var events: [TodoItem] = []
        do {
            reminders = try await repository.fetchPending(on: selectedDate)
        } catch {
            reportError(error, op: "fetch reminders")
        }
        do {
            events = try await repository.fetchEvents(on: selectedDate)
        } catch {
            reportError(error, op: "fetch events")
        }
        items = (reminders + events).sorted {
            let lhsDone = $0.isCompleted
            let rhsDone = $1.isCompleted
            if lhsDone != rhsDone { return !lhsDone } // 未完成在前
            return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
        }
    }

    private func reportError(_ error: Error, op: String) {
        errorMessage = error.localizedDescription
        lastAddStep = "store.\(op) FAILED \(String(describing: error))"
        TodoTrace.log("store.\(op) FAILED \(String(describing: error))")
    }
}