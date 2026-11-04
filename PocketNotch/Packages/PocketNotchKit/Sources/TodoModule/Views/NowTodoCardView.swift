import AppKit
import PocketNotchShared
import PocketNotchCore
import OSLog
import SwiftUI

/// 「此刻」页居中的待办卡片：顶部滚动日期条 + 当前日期的待办列表，
/// 支持添加 / 勾选完成 / 悬停删除，数据直接读写系统「提醒事项」。
struct NowTodoCardView: View {
    @Bindable var store: TodoStore

    @State private var isAdding = false
    @State private var editingItemID: String?

    private let calendar = Calendar.current
    private static let inputLogger = Logger(subsystem: "com.pocketnotch.app", category: "todo-input")
    private let inputLogger = NowTodoCardView.inputLogger

    /// 编辑对象：nil 表示不在编辑；被外部同步删除时自动退出编辑。
    private var editingItem: TodoItem? {
        guard let editingItemID else { return nil }
        return store.items.first { $0.id == editingItemID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            dateStrip

            if let errorMessage = store.errorMessage {
                errorRow(errorMessage)
            }

            if isAdding {
                TodoComposerView(
                    mode: .add,
                    selectedDate: store.selectedDate,
                    lists: store.reminderLists,
                    onCommit: composerCommit,
                    onCreateList: { title in await store.addList(title: title) },
                    onCancel: { endCompose() }
                )
                .transition(.opacity.combined(with: .scale(0.97, anchor: .top)))
            } else if let editingItem {
                TodoComposerView(
                    mode: .edit(editingItem),
                    selectedDate: store.selectedDate,
                    lists: store.reminderLists,
                    onCommit: composerCommit,
                    onCreateList: { title in await store.addList(title: title) },
                    onCancel: { endCompose() }
                )
                .transition(.opacity.combined(with: .scale(0.97, anchor: .top)))
                .id(editingItem.id)
            } else if store.items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .animation(.easeOut(duration: 0.18), value: isAdding)
        .animation(.easeOut(duration: 0.18), value: editingItemID)
        .padding(.top, 10)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .frame(width: TodoCardDesign.cardWidth, height: TodoCardDesign.cardHeight, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contextMenu {
            Button {
                beginAdding()
            } label: {
                Label(isAdding ? "todo.cancelAdd" : "todo.add", systemImage: isAdding ? "xmark" : "plus")
            }
        }
        .onAppear {
            Task { await store.prepare() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // 用户去系统设置改完权限再回来时自动恢复。
            Task { await store.prepare() }
        }
    }

    private func beginAdding() {
        guard !isAdding else { return }
        inputLogger.info("begin add")
        activateForInput()
        editingItemID = nil
        isAdding = true
    }

    private func endCompose() {
        isAdding = false
        editingItemID = nil
    }

    private func composerCommit(
        _ title: String,
        _ notes: String,
        _ listID: String?,
        _ hasTime: Bool,
        _ time: Date
    ) {
        let calendar = Calendar.current
        if isAdding {
            Task {
                await store.add(
                    title: title,
                    notes: notes,
                    hasTime: hasTime,
                    dueDate: hasTime ? time : nil,
                    listID: listID
                )
            }
        } else if let editingItem {
            Task {
                await store.update(
                    id: editingItem.id,
                    title: title,
                    notes: notes,
                    hasTime: hasTime,
                    dueDate: hasTime ? time : calendar.startOfDay(for: time),
                    listID: listID
                )
            }
        }
        endCompose()
    }

    private func activateForInput() {
        // 菜单栏非激活面板：普通 activate 拿不到键盘，用 NSRunningApplication 强激活。
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        if let window = NSApp.windows.first(where: { $0.canBecomeKey }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - 日期条

    private var dateStrip: some View {
        // 日期条不做任何"出现在首屏后自动定位"：今天按设计排在第 0 格且左缘
        // 就是内容区起点，offset 0 天然显示今天。onChange 在 @Observable 上可能
        // 于首次渲染后多发一次，viewAligned 也会在布局回落时吸附滚动，二者都会
        // 让日期条在展开动画结束后自顾自地滚一格。改为只在用户点日期时显式滚动。
        ScrollViewReader { proxy in
            HStack(spacing: 4) {
                Text(monthLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .monospacedDigit()
                    .frame(width: 30, height: TodoCardDesign.dateStripHeight - 4, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.white.opacity(0.06))
                    )
                    .onTapGesture {
                        scrollTo(day: Calendar.current.startOfDay(for: .now), via: proxy)
                        Task { await store.selectDate(.now) }
                    }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(displayDays, id: \.self) { day in
                            Button {
                                scrollTo(day: day, via: proxy)
                                Task { await store.selectDate(day) }
                            } label: {
                                DateStripCell(
                                    date: day,
                                    isSelected: calendar.isDate(day, inSameDayAs: store.selectedDate),
                                    isToday: calendar.isDateInToday(day)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    // 今天这格是白色胶囊，贴左缘会和月份格挤在一起；
                    // 留 3pt 间距。此偏移是静态的（首屏不再自动定位/吸附），不会位移。
                    .padding(.horizontal, 3)
                }
            }
        }
        .frame(height: TodoCardDesign.dateStripHeight)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.05))
        )
        .padding(.horizontal, 3)
    }

    /// 用户点选日期后把该格滚到左缘；仅此一处会驱动滚动，首屏绝不自动定位。
    private func scrollTo(day: Date, via proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(day, anchor: .leading)
        }
    }

    private var monthLabel: String {
        String(format: L10n.tr("todo.monthFormat"), calendar.component(.month, from: store.selectedDate))
    }

    private var displayDays: [Date] {
        let today = calendar.startOfDay(for: .now)
        var days: [Date] = []
        // 「今天」放到最前：打开即停在第 0 格，不依赖滚动定位，杜绝首屏跑偏。
        var cursor = today
        for _ in 0..<TodoCardDesign.daysForward {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        days.append(cursor)
        // 过去的天放在最后（需向右滚动较远才能到，非主场景）。
        cursor = today
        for _ in 0..<TodoCardDesign.daysBack {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            days.append(previous)
            cursor = previous
        }
        return days
    }

    @ViewBuilder
    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 6) {
            Text(message)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.red.opacity(0.80))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            accessActionButton
        }
    }

    /// 未定状态可再次请求（会弹系统授权框）；已拒绝/受限只能引导去系统设置。
    @ViewBuilder
    private var accessActionButton: some View {
        switch store.authorizationState {
        case .notDetermined:
            Button {
                Task { await store.prepare() }
            } label: {
                Text("todo.requestPermission")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.90))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.white.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
            .help("todo.requestPermissionHelp")
        case .denied, .restricted:
            Button {
                openRemindersSettings()
            } label: {
                Text("todo.goToSettings")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.90))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.white.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
            .help("todo.goToSettingsHelp")
        case .authorized:
            EmptyView()
        }
    }

    private func openRemindersSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// 从标题里提取时间片段：支持「9:30」「9：30」「9点30」「9点半」「9点」。
    /// 返回去掉时间片段后的干净标题；识别不到返回 nil。
    static func parseInlineTime(in raw: String) -> (hour: Int, minute: Int, remainingTitle: String)? {
        guard !raw.isEmpty else { return nil }

        // 9:30 / 09:30 / 9：30
        let colon = try? NSRegularExpression(pattern: #"(\d{1,2})\s*[:：]\s*(\d{2})"#)
        if let match = colon?.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let full = Range(match.range(at: 0), in: raw),
           let hourR = Range(match.range(at: 1), in: raw),
           let minuteR = Range(match.range(at: 2), in: raw),
           let hour = Int(raw[hourR]), let minute = Int(raw[minuteR]),
           (0...23).contains(hour), (0...59).contains(minute) {
            let remaining = (raw[..<full.lowerBound] + raw[full.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            return (hour, minute, remaining.isEmpty ? raw : remaining)
        }

        // 9点30 / 9点半 / 9点
        let dian = try? NSRegularExpression(pattern: #"(\d{1,2})\s*[点时]\s*(半|\d{1,2})?"#)
        if let match = dian?.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let full = Range(match.range(at: 0), in: raw),
           let hourR = Range(match.range(at: 1), in: raw),
           let hour = Int(raw[hourR]),
           (0...23).contains(hour) {
            var minute = 0
            if match.range(at: 2).location != NSNotFound,
               let minR = Range(match.range(at: 2), in: raw) {
                let token = String(raw[minR])
                if token == "半" {
                    minute = 30
                } else if let value = Int(token), (0...59).contains(value) {
                    minute = value
                }
            }
            let remaining = (raw[..<full.lowerBound] + raw[full.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            return (hour, minute, remaining.isEmpty ? raw : remaining)
        }

        return nil
    }

    /// 时间输入 mask：只接受数字，按位填入 HH:MM 模板，冒号为固定分隔符。
    /// 0 位 → ""（显示 placeholder）；1 位 → "H"；2 位 → "HH:"；3 位 → "HH:M"；4 位 → "HH:MM"。
    static func formatTimeMask(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(4))
        switch digits.count {
        case 0:
            return ""
        case 1:
            return digits
        case 2:
            return digits + ":"
        case 3:
            return String(digits.prefix(2)) + ":" + String(digits.suffix(1))
        default:
            return String(digits.prefix(2)) + ":" + String(digits.suffix(2))
        }
    }

    // MARK: - 列表

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(store.items) { item in
                    TodoRowView(
                        item: item,
                        onToggle: { Task { await store.toggle(item.id) } },
                        onDelete: { Task { await store.remove(item.id) } },
                        onEdit: {
                            activateForInput()
                            isAdding = false
                            editingItemID = item.id
                        }
                    )
                }
            }
            .padding(.vertical, 1)
            .animation(.easeOut(duration: 0.15), value: store.items)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var emptyState: some View {
        Button {
            beginAdding()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: "checklist")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.28))

                Text("todo.empty")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.34))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 待办卡片的设计尺寸与样式参数。
private enum TodoCardDesign {
    static let cardWidth: CGFloat = 180
    static let cardHeight: CGFloat = IslandLayoutToken.expandedNowPageCardHeight
    static let dateStripHeight: CGFloat = 30
    static let daysBack = 30
    static let daysForward = 365
}

/// 单个日期格：周几 + 日号。今天用白色胶囊+深色文字高亮，选中/普通态逐级减弱。
private struct DateStripCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool

    var body: some View {
        VStack(spacing: 1) {
            Text(topLabel)
                .font(.system(size: 8, weight: isToday ? .semibold : .medium))
                .foregroundStyle(topForeground)
            Text(dayText)
                .font(.system(size: 11, weight: isToday ? .bold : .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(dayForeground)
        }
        .frame(width: 26, height: TodoCardDesign.dateStripHeight - 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(fillColor)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var topLabel: String {
        date.formatted(.dateTime.weekday(.narrow))
    }

    private var dayText: String {
        String(Calendar.current.component(.day, from: date))
    }

    private var fillColor: Color {
        if isToday { return .white.opacity(0.94) }
        if isSelected { return .white.opacity(0.16) }
        return .clear
    }

    private var topForeground: Color {
        if isToday { return .black.opacity(0.55) }
        if isSelected { return .white.opacity(0.90) }
        return .white.opacity(0.45)
    }

    private var dayForeground: Color {
        if isToday { return .black.opacity(0.88) }
        if isSelected { return .white.opacity(0.95) }
        return .white.opacity(0.55)
    }
}

/// 单条待办行：勾选切换、时间前缀、悬停浮现背景与删除按钮。
private struct TodoRowView: View {
    let item: TodoItem
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            leadingControl

            Text(item.title)
                .font(.system(size: 11, weight: item.isCompleted ? .regular : .medium))
                .foregroundStyle(.white.opacity(item.isCompleted ? 0.42 : 0.88))
                .strikethrough(item.isCompleted, color: .white.opacity(0.35))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            if let time = item.timeText {
                Text(time)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(alignment: .trailing)
            }

            if isHovering && item.isDeletable {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.red.opacity(0.85))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableIconStyle())
                .transition(.opacity)
                .accessibilityLabel("todo.delete")
                .help("todo.delete")
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .frame(minHeight: 22)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(isHovering ? 0.05 : 0))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.18), value: item.isCompleted)
        .transition(.opacity.combined(with: .offset(y: -3)))
        .onTapGesture(count: 2) {
            if item.isToggleable && !item.isCompleted {
                onEdit()
            }
        }
    }

    /// 提醒显示勾选圈；日程用蓝色日历图标（只读，不可完成）。
    @ViewBuilder
    private var leadingControl: some View {
        if item.isToggleable {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        item.isCompleted ? Color.green.opacity(0.85) : Color.white.opacity(0.45)
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .frame(width: 16, height: 16)
            .accessibilityLabel(item.isCompleted ? "todo.markIncomplete" : "todo.markComplete")
            .help(item.isCompleted ? "todo.markIncomplete" : "todo.markComplete")
        } else {
            Image(systemName: "calendar")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.blue.opacity(0.85))
                .frame(width: 16, height: 16)
        }
    }
}

/// 浮在卡片背景上的弹窗式输入面板：标题 / 备注 / 所属列表 / 时间四行。
/// 标题 Enter 智能推进（后行全空则直接提交）；时间与列表都是 chip，
/// 点击在按钮下方弹出纵向选项列表，时间文本本身也是可直接输入的框。
private struct TodoComposerView: View {
    enum Mode {
        case add
        case edit(TodoItem)
    }

    private enum Popup {
        case time, list, date
    }

    let mode: Mode
    let selectedDate: Date
    /// 可写的提醒列表（添加时选目标 / 编辑时可改归属）。
    let lists: [ReminderListInfo]
    let onCommit: (_ title: String, _ notes: String, _ listID: String?, _ hasTime: Bool, _ time: Date) -> Void
    /// 新建提醒列表；成功返回新列表快照，失败返回 nil。
    let onCreateList: (_ title: String) async -> ReminderListInfo?
    let onCancel: () -> Void

    @State private var title = ""
    @State private var notesDraft = ""
    @State private var listID: String?
    @State private var hasTime = false
    @State private var time = Date()
    @State private var activePopup: Popup?
    @State private var timeDraft = ""
    @State private var timeInputError: String?
    @State private var customDate: Date?
    @State private var isCreatingList = false
    @State private var newListDraft = ""
    @State private var focusedField: Field?
    @State private var enterMonitor: Any?

    private enum Field {
        case title, notes, time, newList
    }

    private let calendar = Calendar.current
    private static let commonTimes: [(hour: Int, minute: Int)] = [
        (9, 0), (12, 0), (14, 0), (18, 0), (21, 0),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            timeRow
            listField
            titleField
            notesField
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .animation(.easeOut(duration: 0.15), value: activePopup)
        .onChange(of: focusedField) { _, newValue in
            // 焦点离开时间输入时，把草稿还原成当前显示值，避免残留半截输入。
            guard newValue != .time else { return }
            timeDraft = hasTime ? timeText : ""
        }
        .onChange(of: activePopup) { _, newValue in
            if newValue != nil, enterMonitor == nil {
                enterMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.keyCode == 36 {
                        activePopup = nil
                        return nil
                    }
                    return event
                }
            } else if newValue == nil, let monitor = enterMonitor {
                NSEvent.removeMonitor(monitor)
                enterMonitor = nil
            }
        }
        .onAppear(perform: initialize)
        .onDisappear {
            activePopup = nil
            if let monitor = enterMonitor {
                NSEvent.removeMonitor(monitor)
                enterMonitor = nil
            }
        }
    }

    private var selectedListTitle: String {
        if let listID, let list = lists.first(where: { $0.id == listID }) {
            return list.title
        }
        return lists.first(where: { $0.isDefault })?.title
            ?? lists.first?.title
            ?? L10n.tr("todo.defaultList")
    }

    private var editingItem: TodoItem? {
        if case .edit(let item) = mode { return item }
        return nil
    }

    /// 日期基准：编辑沿用原待办所在日；新增用当前选中日。
    private var dayBase: Date {
        if let custom = customDate {
            return calendar.startOfDay(for: custom)
        }
        if let existing = editingItem?.dueDate {
            return calendar.startOfDay(for: existing)
        }
        return calendar.startOfDay(for: selectedDate)
    }

    private var timeText: String {
        let h = calendar.component(.hour, from: time)
        let m = calendar.component(.minute, from: time)
        return NowTodoCardView.formatTimeMask(String(format: "%02d%02d", h, m))
    }

    private func isSelectedTime(hour: Int, minute: Int) -> Bool {
        guard hasTime else { return false }
        return calendar.component(.hour, from: time) == hour
            && calendar.component(.minute, from: time) == minute
    }

    // MARK: - 四行字段

    private var titleField: some View {
        HStack(spacing: 6) {
            Image(systemName: editingItem == nil ? "checkmark.circle" : "checkmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(title.isEmpty ? 0.30 : 0.65))
                .frame(width: 14)

            TodoTextField(
                text: $title,
                placeholder: editingItem == nil ? L10n.tr("todo.newPlaceholder") : L10n.tr("todo.editPlaceholder"),
                isFocused: focusedField == .title,
                onSubmit: { commitFromTitle() },
                onCancel: onCancel
            )
            .padding(.leading, 6)
            .frame(minWidth: 60, maxWidth: .infinity, alignment: .leading)
        }
    }

    private var notesField: some View {
        HStack(spacing: 6) {
            Image(systemName: "note.text")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(notesDraft.isEmpty ? 0.30 : 0.65))
                .frame(width: 14)

            TodoTextField(
                text: $notesDraft,
                placeholder: L10n.tr("todo.notesPlaceholder"),
                isFocused: focusedField == .notes,
                onSubmit: { commitFromNotes() },
                onCancel: onCancel
            )
            .padding(.leading, 6)
            .frame(minWidth: 60, maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 所属列表 chip：点击在下方弹出可写列表，纵向选择。
    private var listField: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(listID != nil ? 0.65 : 0.30))
                .frame(width: 14)

            Button {
                if activePopup == .list {
                    activePopup = nil
                    focusedField = .title
                } else {
                    activePopup = .list
                    isCreatingList = false
                    newListDraft = ""
                }
            } label: {
                HStack(spacing: 3) {
                    Text(selectedListTitle)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.70))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.40))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(
                    Capsule().fill(.white.opacity(activePopup == .list ? 0.12 : 0.06))
                )
                .animation(.easeOut(duration: 0.15), value: activePopup == .list)
                .contentShape(Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .buttonStyle(.plain)
            .disabled(lists.isEmpty)
            .help("todo.listHelp")
            .islandPopover(
                isPresented: Binding(
                    get: { activePopup == .list },
                    set: { presented in
                        if presented {
                            isCreatingList = false
                            newListDraft = ""
                            activePopup = .list
                        } else if activePopup == .list {
                            activePopup = nil
                        }
                    }
                ),
                arrowEdge: .top
            ) {
                listPopup

            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

    }

    /// 时间独占最后一行：chip 靠左，弹窗悬浮在其下方。
    private var timeRow: some View {
        HStack(spacing: 6) {
            timeControl
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 时间控件（第一行末尾）

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f
    }()

    private var todayDateText: String {
        Self.dateFormatter.string(from: dayBase)
    }

    /// 时间文本本身是输入框，直接敲数字回车生效；常用时间弹窗由后方三角图标触发。
    private var timeControl: some View {
        HStack(spacing: 6) {
            // 时钟只作状态指示：点输入框仅获焦编辑，不弹常用时间。
            Image(systemName: hasTime ? "clock.fill" : "clock")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(hasTime ? 0.65 : 0.30))
                .frame(width: 14)

            HStack(spacing: 6) {
                Button {
                    activePopup = (activePopup == .date) ? nil : .date
                } label: {
                    Text(todayDateText)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.50))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .islandPopover(
                    isPresented: Binding(
                        get: { activePopup == .date },
                        set: { presented in
                            if presented {
                                activePopup = .date
                            } else if activePopup == .date {
                                activePopup = nil
                            }
                        }
                    ),
                    arrowEdge: .top
                ) {
                    TodoCalendarPicker(
                        selection: customDate ?? dayBase,
                        minDate: calendar.startOfDay(for: Date())
                    ) { date in
                        customDate = date
                        activePopup = nil
                    }

                }

                Button {
                    activePopup = (activePopup == .time) ? nil : .time
                } label: {
                    Text(hasTime ? timeText : "--:--")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(hasTime ? 0.92 : 0.50))
                        .lineLimit(1)
                        .frame(width: 32, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .islandPopover(
                    isPresented: Binding(
                        get: { activePopup == .time },
                        set: { presented in
                            if presented {
                                timeDraft = hasTime ? timeText : ""
                                activePopup = .time
                            } else if activePopup == .time {
                                activePopup = nil
                            }
                        }
                    ),
                    arrowEdge: .top
                ) {
                    timePopup

                }


                Button {
                    guard hasTime else { return }
                    hasTime = false
                    activePopup = nil
                    timeDraft = ""
                    focusedField = .title
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(hasTime ? 0.40 : 0.20))
                }
                .buttonStyle(PressableIconStyle())
                .disabled(!hasTime)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(
                Capsule().fill(.white.opacity(hasTime ? 0.12 : 0.06))
            )

            .overlay(alignment: .topLeading) {
                if let msg = timeInputError {
                    Text(msg)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.red.opacity(0.90))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .offset(x: 0, y: 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timePopup: some View {
        VStack(alignment: .leading, spacing: 1) {
            TodoTextField(
                text: $timeDraft,
                placeholder: "--:--",
                isFocused: focusedField == .time,
                onSubmit: {
                    if commitTimeDraft() {
                        timeInputError = nil
                        commit()
                    } else {
                        timeInputError = "时间格式不正确"
                    }
                },
                onCancel: {
                    timeDraft = hasTime ? timeText : ""
                    focusedField = .title
                },
                onFocusChange: { focused in
                    if focused {
                        timeDraft = hasTime ? timeText : ""
                        timeInputError = nil
                    }
                },
                inputFormatter: { NowTodoCardView.formatTimeMask($0) }
            )
            .padding(.horizontal, 5)
            .frame(height: 20)

            IslandPopoverDivider()

            ForEach(Array(Self.commonTimes.enumerated()), id: \.offset) { _, preset in
                TimeOptionRow(
                    label: String(format: "%02d:%02d", preset.hour, preset.minute),
                    isSelected: isSelectedTime(hour: preset.hour, minute: preset.minute)
                ) {
                    setTime(hour: preset.hour, minute: preset.minute)
                }
            }
        }
        .padding(10)
        .frame(width: 104)

    }


    private var listPopup: some View {
        VStack(alignment: .leading, spacing: 1) {
                if isCreatingList {
                    TodoTextField(
                        text: $newListDraft,
                        placeholder: L10n.tr("todo.newListNamePlaceholder"),
                        isFocused: focusedField == .newList,
                        onSubmit: { createList() },
                        onCancel: {
                            isCreatingList = false
                            newListDraft = ""
                        }
                    )
                    .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                    .padding(.horizontal, 2)
                } else {
                    TimeOptionRow(label: L10n.tr("todo.newListEllipsis")) {
                        isCreatingList = true
                        newListDraft = ""
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 60_000_000)
                            focusedField = .newList
                        }
                    }
                }

                IslandPopoverDivider()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(lists, id: \.id) { list in
                            TimeOptionRow(
                                label: list.title,
                                isSelected: list.id == listID
                            ) {
                                listID = list.id
                                activePopup = nil
                                focusedField = .title
                            }
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        .padding(10)
        .frame(width: 136)

    }

    // MARK: - 提交逻辑

    private func initialize() {
        switch mode {
        case .add:
            title = ""
            notesDraft = ""
            listID = lists.first(where: { $0.isDefault })?.id ?? lists.first?.id
            hasTime = false
            time = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        case .edit(let item):
            title = item.title
            notesDraft = item.notes
            listID = item.listID
            hasTime = item.hasTime
            time = item.dueDate
                ?? calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate)
                ?? selectedDate
        }
        activePopup = nil
        timeDraft = hasTime ? timeText : ""
        // 等面板激活/成键后再聚焦，否则首次输入会被转给其他 App。
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            focusedField = .title
        }
    }

    private func setTime(hour: Int, minute: Int) {
        time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayBase) ?? time
        hasTime = true
        activePopup = nil
        timeDraft = timeText
        focusedField = .title
    }

    private func createList() {
        let name = newListDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task { @MainActor in
            if let created = await onCreateList(name) {
                listID = created.id
                activePopup = nil
                focusedField = .title
            }
            isCreatingList = false
            newListDraft = ""
        }
    }

    @discardableResult
    private func commitTimeDraft() -> Bool {
        if let parsed = NowTodoCardView.parseInlineTime(in: timeDraft) {
            setTime(hour: parsed.hour, minute: parsed.minute)
            return true
        }
        // mask 输入回车：纯数字按位补全（1-2 位=小时:00，3-4 位=HH:MM）。
        let digits = timeDraft.filter(\.isNumber)
        switch digits.count {
        case 0:
            return true
        case 1, 2:
            if let h = Int(digits), (0...23).contains(h) {
                setTime(hour: h, minute: 0); return true
            }
        case 3, 4:
            let h = Int(digits.prefix(2)) ?? -1
            let m = Int(digits.dropFirst(2)) ?? -1
            if (0...23).contains(h), (0...59).contains(m) {
                setTime(hour: h, minute: m); return true
            }
        default:
            break
        }
        return false
    }

    private func commitFromTitle() {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        if notesDraft.isEmpty && activePopup == nil {
            commit()
        } else {
            focusedField = .notes
        }
    }

    private func commitFromNotes() {
        commit()
    }

    private func commit() {
        var finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalTitle.isEmpty else { return }

        var finalHasTime = hasTime
        var finalTime = time

        // 标题里带时间（如「开会 9:30」「21点交周报」）则直接识别，少一步操作。
        if let parsed = NowTodoCardView.parseInlineTime(in: finalTitle) {
            finalTitle = parsed.remainingTitle
            finalHasTime = true
            finalTime = calendar.date(
                bySettingHour: parsed.hour, minute: parsed.minute, second: 0, of: dayBase
            ) ?? finalTime
        }

        let due: Date
        if finalHasTime {
            due = calendar.date(
                bySettingHour: calendar.component(.hour, from: finalTime),
                minute: calendar.component(.minute, from: finalTime),
                second: 0,
                of: dayBase
            ) ?? finalTime
        } else {
            due = calendar.startOfDay(for: dayBase)
        }

        onCommit(
            finalTitle,
            notesDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            listID,
            finalHasTime,
            due
        )

        // 新增模式提交后清空续录（旧 addRow 的连续录入体验）；
        // 编辑模式由父级关闭 composer。
        if case .add = mode {
            title = ""
            notesDraft = ""
            listID = lists.first(where: { $0.isDefault })?.id ?? lists.first?.id
            hasTime = false
            time = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? selectedDate
            activePopup = nil
            timeDraft = ""
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000)
                focusedField = .title
            }
        }
    }
}

/// 自绘的深色日历：不铺任何底色，完全透出 popover 材质，避免系统
/// graphical DatePicker 自带浅色面板导致年月区、边框、箭头颜色不一致。
private struct TodoCalendarPicker: View {
    let selection: Date
    let minDate: Date
    let onSelect: (Date) -> Void

    @State private var visibleMonth: Date

    private let calendar: Calendar = {
        var cal = Calendar.current
        cal.locale = Locale(identifier: "zh_CN")
        return cal
    }()

    init(selection: Date, minDate: Date, onSelect: @escaping (Date) -> Void) {
        self.selection = selection
        self.minDate = minDate
        self.onSelect = onSelect
        var cal = Calendar.current
        cal.locale = Locale(identifier: "zh_CN")
        let comps = cal.dateComponents([.year, .month], from: selection)
        _visibleMonth = State(initialValue: cal.date(from: comps) ?? selection)
    }

    var body: some View {
        VStack(spacing: 6) {
            headerRow
            weekdayRow
            monthGrid
        }
        .padding(10)
        .frame(width: 216)
    }

    private var headerRow: some View {
        HStack(spacing: 4) {
            navButton("chevron.left", enabled: canGoPrevious) { shiftMonth(-1) }

            Spacer(minLength: 0)

            Text(monthTitle)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))

            Spacer(minLength: 0)

            navButton("chevron.right", enabled: true) { shiftMonth(1) }
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 2) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7),
            spacing: 2
        ) {
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    TodoCalendarDayCell(
                        date: day,
                        isSelected: calendar.isDate(day, inSameDayAs: selection),
                        isToday: calendar.isDateInToday(day),
                        isEnabled: calendar.compare(day, to: minDate, toGranularity: .day) != .orderedAscending,
                        onSelect: onSelect
                    )
                } else {
                    Color.clear.frame(height: 26)
                }
            }
        }
    }

    private func navButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 0.55 : 0.18))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var monthDays: [Date?] {
        guard
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonth)),
            let range = calendar.range(of: .day, in: .month, for: monthStart)
        else { return [] }

        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var days = Array<Date?>(repeating: nil, count: leading)
        for day in range {
            days.append(calendar.date(byAdding: .day, value: day - 1, to: monthStart))
        }
        return days
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(first + $0) % 7] }
    }

    private var monthTitle: String {
        let comps = calendar.dateComponents([.year, .month], from: visibleMonth)
        return String(format: L10n.tr("todo.calendarTitleFormat"), comps.year ?? 0, comps.month ?? 0)
    }

    private var canGoPrevious: Bool {
        guard let previous = calendar.date(byAdding: .month, value: -1, to: visibleMonth) else { return false }
        return calendar.compare(previous, to: minDate, toGranularity: .month) != .orderedAscending
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: visibleMonth) else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            visibleMonth = next
        }
    }
}

private struct TodoCalendarDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isEnabled: Bool
    let onSelect: (Date) -> Void

    private let calendar = Calendar.current

    var body: some View {
        IslandPopoverCell(
            density: .compact,
            selectionStyle: .prominent,
            isSelected: isSelected,
            isHighlighted: isToday,
            isEnabled: isEnabled,
            alignment: .center
        ) {
            onSelect(date)
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 10.5, weight: isSelected ? .bold : .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(foreground)
        }
    }

    private var foreground: Color {
        if isSelected { return .black.opacity(0.88) }
        if !isEnabled { return .white.opacity(0.20) }
        return .white.opacity(0.80)
    }
}

/// 时间弹窗里的纵向选项行：与日历格同一套悬停 / 选中样式。
private struct TimeOptionRow: View {
    let label: String
    var isSelected = false
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        IslandPopoverCell(
            density: .compact,
            selectionStyle: .prominent,
            isSelected: isSelected,
            action: action
        ) {
            Text(label)
                .font(.system(size: 10.5, weight: isSelected ? .bold : .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(foreground)
                .lineLimit(1)
        }
    }

    private var foreground: Color {
        if isDestructive { return .red.opacity(0.85) }
        if isSelected { return .black.opacity(0.88) }
        return .white.opacity(0.80)
    }
}

/// 图标按钮按压反馈：按下轻微缩放，easeOut 快速响应。
private struct PressableIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 给 NSTextField 一个宽度下限，避免 SwiftUI 把它压到「空文本」理想宽度
/// （~14pt）引发 AppKit 最小/最大约束告警。
private final class TodoInputField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?
    var onTapWhenFocused: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            // AppKit 默认 becomeFirstResponder 会 selectText: 全选已有内容，
            // 在"选完时间/列表回填后焦点切回标题框"这类重新聚焦路径上会意外全选，
            // 用户接着按键会把已有标题整段替换掉。检测到全选且字段非空时，
            // 把光标定位到末尾保持插入态；用户主动 Cmd+A 全选不受影响（那是用户意图）。
            if let editor = currentEditor(),
               stringValue.count > 0,
               editor.selectedRange.location == 0,
               editor.selectedRange.length == stringValue.count {
                editor.selectedRange = NSRange(location: stringValue.count, length: 0)
            }
            onFocusChange?(true)
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onFocusChange?(false) }
        return ok
    }

    override func mouseDown(with event: NSEvent) {
        let wasFocused = window?.firstResponder === currentEditor()
        super.mouseDown(with: event)
        if wasFocused {
            onTapWhenFocused?()
        } else {
            onFocusChange?(true)
        }
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width = max(size.width, 90)
        return size
    }
}

/// 添加待办的原生输入框：直接走 AppKit NSTextField，
/// 规避 SwiftUI TextField 在菜单栏非激活面板里的约束断言与焦点问题。
private struct TodoTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isFocused: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void
    var onFocusChange: ((Bool) -> Void)?
    var onTapWhenFocused: (() -> Void)?
    /// 可选输入格式化器：每次输入都把原始字符串转成模板化显示串（如时间 mask）。
    var inputFormatter: ((String) -> String)?

    private static let logger = Logger(subsystem: "com.pocketnotch.app", category: "todo-input")

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TodoTextField
        /// 只在 isFocused 从 false 变 true 时申请一次焦点；
        /// 否则 SwiftUI 每次重渲染都会抢焦点，引发多字段间的焦点战。
        var didRequestFocus = false

        init(_ parent: TodoTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            if let formatter = parent.inputFormatter {
                let raw = field.stringValue
                // 删除冒号场景：旧 "12:" → AppKit 删成 "12" → formatTimeMask 又补成 "12:"，
                // 冒号删不掉卡住用户。检测到「删除且冒号被删掉」时跳过格式化，
                // 保留用户删除结果，让删除能连续进行；下次输入数字时再补冒号。
                if raw.count < parent.text.count,
                   parent.text.contains(":"), !raw.contains(":") {
                    parent.text = raw
                    return
                }
                let formatted = formatter(raw)
                if raw != formatted {
                    field.stringValue = formatted
                    if let editor = field.currentEditor() {
                        editor.selectedRange = NSRange(location: formatted.count, length: 0)
                    }
                }
                parent.text = formatted
            } else {
                parent.text = field.stringValue
            }
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                TodoTrace.log("delegate.insertNewline calling onSubmit")
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> TodoInputField {
        let field = TodoInputField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 11)
        field.textColor = .white.withAlphaComponent(0.92)
        field.delegate = context.coordinator
        // 解锁 cell：不随空文本把整体宽度压到 ~14pt（触发 AppKit 约束告警）。
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.onFocusChange = { [weak coordinator = context.coordinator] focused in
            coordinator?.parent.onFocusChange?(focused)
        }
        field.onTapWhenFocused = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onTapWhenFocused?()
        }
        return field
    }

    func updateNSView(_ nsView: TodoInputField, context: Context) {
        context.coordinator.parent = self
        nsView.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.35),
                .font: NSFont.systemFont(ofSize: 11),
            ]
        )
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if isFocused {
            if !context.coordinator.didRequestFocus {
                context.coordinator.didRequestFocus = true
                DispatchQueue.main.async {
                    let ok = nsView.window?.makeFirstResponder(nsView) == true
                    TodoTextField.logger.info(
                        "focus attempted ok=\(ok) window=\(nsView.window != nil) key=\(nsView.window?.isKeyWindow == true)"
                    )
                    // AppKit makeFirstResponder 默认 selectText: 会全选已有文字，
                    // 重新聚焦（如选完时间回填后）会把待办标题整段选中，违背用户预期。
                    // 改为光标定位到末尾，保持插入态。
                    if ok, let editor = nsView.currentEditor() {
                        let end = nsView.stringValue.count
                        editor.selectedRange = NSRange(location: end, length: 0)
                    }
                    // 面板尚未成键时申请会失败，允许下一次更新重试。
                    if !ok {
                        context.coordinator.didRequestFocus = false
                    }
                }
            }
        } else {
            context.coordinator.didRequestFocus = false
        }
    }

    // 宽度只跟随布局 proposal，不跟随 intrinsicContentSize（它随输入文字变宽，
    // 会引发逐字符的宽度抖动与文字截断）。
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: TodoInputField,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: max(proposal.width ?? 120, 20),
            height: nsView.intrinsicContentSize.height
        )
    }
}