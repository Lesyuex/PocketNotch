import XCTest
@testable import TodoModule

@MainActor
final class TodoStoreTests: XCTestCase {
    private final class FakeRepository: ReminderRepository {
        var reminders: [TodoItem] = []
        var events: [TodoItem] = []
        var lists: [ReminderListInfo] = [
            ReminderListInfo(id: "list-default", title: "默认", isDefault: true),
            ReminderListInfo(id: "list-work", title: "工作", isDefault: false),
        ]
        var granted = true
        var onDidChange: (() -> Void)?

        func requestAccess() async -> Bool { granted }

        func authorizationState() async -> ReminderAuthorizationState {
            granted ? .authorized : .denied
        }

        func fetchPending(on date: Date) async throws -> [TodoItem] {
            let calendar = Calendar.current
            return reminders.filter {
                guard let due = $0.dueDate else { return calendar.isDateInToday(date) }
                return calendar.isDate(due, inSameDayAs: date)
            }
        }

        func fetchEvents(on date: Date) async throws -> [TodoItem] {
            let calendar = Calendar.current
            return events.filter { calendar.isDate($0.dueDate ?? .now, inSameDayAs: date) }
        }

        func fetchLists() async throws -> [ReminderListInfo] {
            lists
        }

        func addList(title: String) async throws -> ReminderListInfo {
            let created = ReminderListInfo(id: "list-\(title)", title: title, isDefault: false)
            lists.append(created)
            return created
        }

        func add(
            title: String,
            dueDate: Date,
            hasTime: Bool,
            notes: String,
            listID: String?
        ) async throws {
            let lists = try await fetchLists()
            let listTitle = listID.flatMap { id in
                lists.first(where: { $0.id == id })?.title
            } ?? "默认"
            reminders.insert(
                TodoItem(
                    id: UUID().uuidString,
                    title: title,
                    createdAt: .now,
                    dueDate: dueDate,
                    hasTime: hasTime,
                    notes: notes,
                    listID: listID,
                    listTitle: listTitle
                ),
                at: 0
            )
        }

        func update(
            id: String,
            title: String,
            dueDate: Date?,
            hasTime: Bool,
            notes: String,
            listID: String?
        ) async throws {
            guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
            reminders[index] = TodoItem(
                id: id,
                title: title,
                isCompleted: reminders[index].isCompleted,
                createdAt: reminders[index].createdAt,
                dueDate: dueDate ?? reminders[index].dueDate,
                hasTime: hasTime,
                notes: notes,
                listID: listID ?? reminders[index].listID,
                listTitle: reminders[index].listTitle,
                kind: reminders[index].kind
            )
        }

        func setCompleted(_ id: String, completed: Bool) async throws {
            guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
            reminders[index].isCompleted = completed
        }

        func remove(id: String) async throws {
            reminders.removeAll { $0.id == id }
        }
    }

    private let calendar = Calendar.current

    private func makeStore() async -> (TodoStore, FakeRepository) {
        let repository = FakeRepository()
        let store = TodoStore(repository: repository)
        await store.prepare()
        return (store, repository)
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now))!
    }

    func testTodayShowsAllStatesTodaysAndUndatedReminders() async {
        let (store, repository) = await makeStore()
        repository.reminders = [
            TodoItem(id: "today", title: "今天的提醒", dueDate: day(0)),
            TodoItem(id: "undated", title: "无日期的提醒"),
            TodoItem(id: "tomorrow", title: "明天的提醒", dueDate: day(1)),
            TodoItem(id: "done-today", title: "已完成", isCompleted: true, dueDate: day(0)),
        ]
        await store.prepare()

        let titles = Set(store.items.map(\.title))
        // 已完成的也要显示。
        XCTAssertEqual(titles, ["今天的提醒", "无日期的提醒", "已完成"])
        XCTAssertEqual(store.pendingCount, 2)
    }

    func testCompletedSortsLast() async {
        let (store, repository) = await makeStore()
        repository.reminders = [
            TodoItem(id: "done", title: "已完成", isCompleted: true, dueDate: day(0)),
            TodoItem(id: "a", title: "上午", dueDate: day(0).addingTimeInterval(9 * 3600)),
            TodoItem(id: "b", title: "下午", dueDate: day(0).addingTimeInterval(14 * 3600)),
            TodoItem(id: "nodate", title: "无日期"),
        ]
        await store.prepare()

        XCTAssertEqual(store.items.map(\.title), ["上午", "下午", "无日期", "已完成"])
    }

    func testSelectDateSwitchesToThatDaysReminders() async {
        let (store, repository) = await makeStore()
        repository.reminders = [
            TodoItem(id: "today", title: "今天", dueDate: day(0)),
            TodoItem(id: "tomorrow", title: "明天", dueDate: day(1)),
            TodoItem(id: "undated", title: "无日期"),
        ]
        await store.prepare()

        await store.selectDate(day(1))

        XCTAssertEqual(store.items.map(\.title), ["明天"])
    }

    func testMergeEventsAndRemindersOnSameDay() async {
        let (store, repository) = await makeStore()
        repository.reminders = [
            TodoItem(id: "r", title: "提醒：写周报", dueDate: day(0).addingTimeInterval(9 * 3600)),
        ]
        repository.events = [
            TodoItem(
                id: "e1",
                title: "日程：站会",
                dueDate: day(0).addingTimeInterval(10 * 3600),
                hasTime: true,
                kind: .calendarEvent
            ),
            TodoItem(
                id: "e2",
                title: "日程：全天事项",
                dueDate: day(0),
                kind: .calendarEvent
            ),
            TodoItem(
                id: "e3",
                title: "日程：明天",
                dueDate: day(1),
                kind: .calendarEvent
            ),
        ]
        await store.prepare()

        XCTAssertEqual(store.items.count, 3)
        XCTAssertEqual(store.items.map(\.title), ["日程：全天事项", "提醒：写周报", "日程：站会"])
    }

    func testEventsAreReadOnly() {
        let event = TodoItem(id: "e", title: "日程", kind: .calendarEvent)
        XCTAssertFalse(event.isToggleable)
        XCTAssertFalse(event.isDeletable)

        let reminder = TodoItem(id: "r", title: "提醒")
        XCTAssertTrue(reminder.isToggleable)
        XCTAssertTrue(reminder.isDeletable)
    }

    func testTimeTextOnlyWhenHasTime() {
        let timed = TodoItem(id: "a", title: "t", dueDate: day(0).addingTimeInterval(10 * 3600), hasTime: true)
        XCTAssertNotNil(timed.timeText)

        let allDay = TodoItem(id: "b", title: "t", dueDate: day(0))
        XCTAssertNil(allDay.timeText)
    }

    func testAddSticksToSelectedDate() async {
        let (store, _) = await makeStore()
        await store.selectDate(day(3))

        await store.add(title: "  写周报  ")

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.title, "写周报")
        XCTAssertTrue(calendar.isDate(store.items[0].dueDate ?? .distantPast, inSameDayAs: day(3)))
    }

    func testAddIgnoresBlankTitle() async {
        let (store, _) = await makeStore()

        await store.add(title: "   ")
        await store.add(title: "\n\t")

        XCTAssertTrue(store.items.isEmpty)
    }

    func testToggleCompletesAndKeepsInList() async {
        let (store, repository) = await makeStore()
        repository.reminders = [TodoItem(id: "a", title: "写周报", dueDate: day(0))]
        await store.prepare()

        await store.toggle("a")

        XCTAssertEqual(repository.reminders.first?.isCompleted, true)
        XCTAssertEqual(store.items.first?.isCompleted, true)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.pendingCount, 0)

        await store.toggle("a")

        XCTAssertEqual(store.items.first?.isCompleted, false)
        XCTAssertEqual(store.pendingCount, 1)
    }

    func testRemove() async {
        let (store, repository) = await makeStore()
        repository.reminders = [TodoItem(id: "a", title: "写周报", dueDate: day(0))]
        await store.prepare()

        await store.remove("a")

        XCTAssertTrue(repository.reminders.isEmpty)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testDeniedAccessShowsEmptyWithoutFallback() async {
        let repository = FakeRepository()
        repository.granted = false
        let store = TodoStore(repository: repository)

        await store.prepare()

        XCTAssertFalse(store.isAuthorized)
        XCTAssertTrue(store.items.isEmpty)
    }
}