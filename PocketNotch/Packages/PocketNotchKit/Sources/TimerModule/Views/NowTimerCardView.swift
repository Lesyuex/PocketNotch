import AppKit
import PocketNotchShared
import PocketNotchCore
import SwiftUI

/// 「此刻」页计时器卡：剪贴板卡与系统状态卡之间，支持倒计时与正计时（秒表）。
///
/// 第一行显示当前模式名称（可重命名），第二行为大号等宽时间，
/// 第三行为倒计时状态或秒表最近分段；底部操作区为重置/分段、播放/暂停。
/// 倒计时首次启动时，时间区域直接变为可输入数值，第三行临时变为单位选择；确认后恢复。
struct NowTimerCardView: View {
    let store: TimerStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isEnteringDuration = false
    @State private var durationDraft = ""
    @State private var durationUnit: DurationUnit = .minutes
    @State private var lastDurationValue = 5
    @State private var lastDurationUnit: DurationUnit = .minutes
    @State private var durationFocusRequest = 0
    @State private var isDurationFieldFocused = false
    @State private var hoveredUnit: DurationUnit?
    @State private var customName = ""
    @State private var nameDraft = ""
    @State private var isRenaming = false
    @State private var isNameFieldFocused = false
    @State private var isNameHovered = false
    @State private var isModeHovered = false
    @State private var isTrailingHovered = false
    @State private var isSecondaryHovered = false
    @State private var isPrimaryHovered = false
    @State private var isLapListVisible = false
    @State private var isLapListHovered = false
    @State private var isAddTimePopoverVisible = false

    var body: some View {
        VStack(spacing: 0) {
            timeBlock
            controls
                .padding(.top, Design.controlsTopGap)
        }
        .padding(.top, Design.topPadding)
        .padding(.bottom, Design.bottomPadding)
        .padding(.horizontal, Design.horizontalPadding)
        .frame(
            width: IslandLayoutToken.expandedNowPageTimerCardWidth,
            height: IslandLayoutToken.expandedNowPageCardHeight,
            alignment: .top
        )
        .onChange(of: store.mode) { _, _ in
            cancelDurationEntry()
            isAddTimePopoverVisible = false
            isLapListVisible = false
        }
        .onChange(of: store.runState) { _, _ in
            isModeHovered = false
            isTrailingHovered = false
            isAddTimePopoverVisible = false
            isLapListVisible = false
        }
    }

    // MARK: - 时间

    private var timeBlock: some View {
        VStack(spacing: 0) {
            headerRow

            timeDisplay
                .padding(.top, Design.modeLabelGap)

            detailRow
                .frame(height: Design.detailRowHeight)
                .padding(.top, Design.modeLabelGap)
        }
    }

    /// 第三行：倒计时状态、到点时刻或未设置提示；输入时为单位选择。
    @ViewBuilder
    private var detailRow: some View {
        if isEnteringDuration {
            durationUnitSelector
        } else {
            switch store.mode {
            case .countdown:
                countdownStatusRow
            case .stopwatch:
                stopwatchLapRow
            }
        }
    }

    /// 第一行显示当前模式名称；名称默认即为可编辑的计时器名称。
    private var headerRow: some View {
        Group {
            if isRenaming {
                TimerNameField(
                    text: $nameDraft,
                    isFocused: isNameFieldFocused,
                    onSubmit: commitName,
                    onCancel: cancelName
                )
                .frame(width: Design.nameFieldWidth, height: Design.nameFieldHeight)
            } else {
                Button(action: beginRenaming) {
                    Text(displayName)
                        .font(.system(size: Design.nameSize, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .foregroundStyle(.white.opacity(isNameHovered ? 0.78 : 0.42))
                        .contentTransition(reduceMotion ? .identity : .opacity)
                        .frame(height: Design.nameFieldHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(NowTimerPressStyle(reduceMotion: reduceMotion))
                .onHover { isNameHovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: store.mode)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isNameHovered)
                .help("timer.renameHelp")
                .accessibilityLabel(String(format: L10n.tr("timer.nameAccessibility"), displayName))
            }
        }
    }

    /// 第三行：倒计时状态、到点时刻或未设置提示。
    private var countdownStatusRow: some View {
        HStack(spacing: Design.statusIconGap) {
            if let countdownStatusIcon {
                Image(systemName: countdownStatusIcon)
                    .font(.system(size: Design.statusIconSize, weight: .semibold))
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.14),
                        value: countdownStatusIcon
                    )
            }

            if !countdownStatusText.isEmpty {
                Text(countdownStatusText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(reduceMotion ? .identity : .opacity)
            }
        }
        .font(.system(size: Design.nameSize, weight: .semibold))
        .tracking(Design.modeLabelTracking)
        .foregroundStyle(countdownStatusColor)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: countdownStatusText)
        .accessibilityLabel(countdownStatusAccessibilityLabel)
    }

    private var countdownStatusIcon: String? {
        if store.needsCountdownInput { return "timer" }
        switch store.runState {
        case .finished:
            return "checkmark.circle.fill"
        case .paused:
            return nil
        case .idle, .running:
            return "bell.fill"
        }
    }

    private var countdownStatusText: String {
        if store.needsCountdownInput { return L10n.tr("timer.durationNotSet") }
        switch store.runState {
        case .finished:
            return L10n.tr("timer.timeUp")
        case .paused:
            return L10n.tr("timer.paused")
        case .idle:
            return L10n.tr("timer.readyToStart")
        case .running:
            return countdownEndText
        }
    }

    private var countdownStatusColor: Color {
        if store.runState == .finished { return Design.finishedColor.opacity(0.82) }
        if store.runState == .paused { return .white.opacity(0.56) }
        if store.needsCountdownInput { return .white.opacity(0.36) }
        return .white.opacity(0.42)
    }

    private var countdownStatusAccessibilityLabel: String {
        if store.needsCountdownInput { return L10n.tr("timer.countdownNoDuration") }
        switch store.runState {
        case .finished:
            return L10n.tr("timer.countdownTimeUp")
        case .paused:
            return L10n.tr("timer.countdownPaused")
        case .idle:
            return L10n.tr("timer.countdownReady")
        case .running:
            return String(format: L10n.tr("timer.countdownEndTime"), countdownEndText)
        }
    }

    /// 第三行：秒表最近一次分段与总段数；尚未记录时显示占位。
    private var stopwatchLapRow: some View {
        HStack(alignment: .center, spacing: Design.statusIconGap) {
            Spacer(minLength: 0)

            Image(systemName: "flag.fill")
                .font(.system(size: Design.statusIconSize, weight: .semibold))

            Text(stopwatchLapText)
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(reduceMotion ? .identity : .numericText())

            if !store.laps.isEmpty {
                lapListButton
            }

            Spacer(minLength: 0)
        }
        .font(.system(size: Design.nameSize, weight: .semibold))
        .tracking(Design.modeLabelTracking)
        .foregroundStyle(.white.opacity(0.42))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: stopwatchLapText)
        .accessibilityLabel(stopwatchLapAccessibilityLabel)
    }

    private var lapListButton: some View {
        Button {
            isLapListVisible.toggle()
        } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 16, height: 16)
                .background(
                    Circle()
                        .fill(
                            .white.opacity(
                                isLapListHovered ? Design.secondaryHoverOpacity : 0
                            )
                        )
                        .frame(width: 14, height: 14)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: Design.hoverDuration),
                            value: isLapListHovered
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(NowTimerPressStyle(reduceMotion: reduceMotion))
        .onHover { isLapListHovered = $0 }
        .islandPopover(isPresented: $isLapListVisible, arrowEdge: .top) {
            lapListPopoverContent
        }
        .help("timer.viewAllLaps")
        .accessibilityLabel("timer.viewAllLaps")
    }

    private var lapListPopoverContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(store.laps.enumerated()), id: \.offset) { index, lap in
                    TimerPopoverRow(
                        title: String(format: L10n.tr("timer.segmentFormat"), index + 1),
                        value: Self.clock(seconds: max(Int(lap), 0))
                    ) {}
                }
            }
        }
        .frame(maxHeight: 160)
        .padding(10)
        .frame(width: 132)
    }

    private var stopwatchLapText: String {
        guard let latest = store.laps.last else { return L10n.tr("timer.noLaps") }
        return Self.clock(seconds: max(Int(latest), 0))
    }

    private var stopwatchLapAccessibilityLabel: String {
        guard let latest = store.laps.last else { return L10n.tr("timer.stopwatchNoLaps") }
        let duration = Self.clock(seconds: max(Int(latest), 0))
        return String(format: L10n.tr("timer.stopwatchLapsSummary"), store.laps.count, duration)
    }

    private var modeTitle: String {
        store.mode == .countdown ? L10n.tr("timer.countdownModeTitle") : L10n.tr("timer.stopwatchModeTitle")
    }

    /// 倒计时的预计到点时刻。
    private var countdownEndText: String {
        let end = Date().addingTimeInterval(max(store.remaining, 0))
        return end.formatted(date: .omitted, time: .shortened)
    }

    private var displayName: String {
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? modeTitle : trimmed
    }

    private func beginRenaming() {
        if isEnteringDuration { cancelDurationEntry() }
        nameDraft = displayName
        isRenaming = true
        isNameFieldFocused = false
        activateForInput()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            if isRenaming { isNameFieldFocused = true }
        }
    }

    private func commitName() {
        customName = String(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12))
        isRenaming = false
        isNameFieldFocused = false
    }

    private func cancelName() {
        isRenaming = false
        isNameFieldFocused = false
        nameDraft = ""
    }

    /// 菜单栏非激活面板：普通 activate 拿不到键盘，用 NSRunningApplication 强激活。
    private func activateForInput() {
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        if let window = NSApp.windows.first(where: { $0.canBecomeKey }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @ViewBuilder
    private var timeDisplay: some View {
        if isEnteringDuration {
            durationInput
        } else {
            timeText
        }
    }

    private var durationInput: some View {
        TimerDurationField(
            text: $durationDraft,
            accessibilityLabel: L10n.tr("timer.durationValue"),
            isFocused: isDurationFieldFocused,
            focusRequest: durationFocusRequest,
            onFocus: { isDurationFieldFocused = true },
            onBlur: { isDurationFieldFocused = false },
            onSubmit: commitDurationAndStart,
            onCancel: cancelDurationEntry
        )
        .frame(width: Design.durationFieldWidth, height: Design.timeHeight)
    }

    private var durationUnitSelector: some View {
        HStack(spacing: Design.durationUnitSpacing) {
            ForEach(DurationUnit.allCases, id: \.self) { unit in
                let isSelected = unit == durationUnit
                Button {
                    durationUnit = unit
                    refocusDurationField()
                } label: {
                    Text(unit.label)
                        .font(.system(size: Design.durationUnitSize, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(
                            .white.opacity(
                                isSelected
                                    ? 0.86
                                    : (hoveredUnit == unit ? 0.62 : 0.36)
                            )
                        )
                        .padding(.horizontal, Design.durationUnitHorizontalPadding)
                        .frame(height: Design.durationUnitHeight)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.white.opacity(isSelected ? 0.12 : 0))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(NowTimerPressStyle(reduceMotion: reduceMotion))
                .onHover { isHovering in
                    if isHovering {
                        hoveredUnit = unit
                    } else if hoveredUnit == unit {
                        hoveredUnit = nil
                    }
                }
                .help(String(format: L10n.tr("timer.useUnitHelp"), unit.helpLabel))
                .accessibilityLabel(String(format: L10n.tr("timer.unitAccessibility"), unit.helpLabel))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("timer.timeUnit")
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: durationUnit)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredUnit)
    }

    private var timeText: some View {
        Text(displayText)
            .font(.system(size: Design.timeSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .tracking(Design.timeTracking)
            .foregroundStyle(timeColor)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .contentTransition(
                reduceMotion
                    ? .identity
                    : .numericText(countsDown: store.mode == .countdown)
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: store.runState)
            .frame(height: Design.timeHeight)
            .accessibilityLabel(timeAccessibilityLabel)
    }

    private var timeColor: Color {
        if store.runState == .finished { return Design.finishedColor }
        if store.needsCountdownInput { return .white.opacity(0.30) }
        if store.runState == .paused { return .white.opacity(0.78) }
        return .white.opacity(0.95)
    }

    private var timeAccessibilityLabel: String {
        switch store.mode {
        case .countdown:
            if store.needsCountdownInput { return L10n.tr("timer.countdownNoDuration") }
            switch store.runState {
            case .finished:
                return L10n.tr("timer.countdownFinished")
            case .paused:
                return String(format: L10n.tr("timer.countdownPausedRemaining"), displayText)
            case .idle:
                return String(format: L10n.tr("timer.countdownDurationSet"), displayText)
            case .running:
                return String(format: L10n.tr("timer.countdownRemaining"), displayText)
            }
        case .stopwatch:
            switch store.runState {
            case .idle:
                return String(format: L10n.tr("timer.stopwatchLabel"), displayText)
            case .running:
                return String(format: L10n.tr("timer.stopwatchRunning"), displayText)
            case .paused:
                return String(format: L10n.tr("timer.stopwatchPausedElapsed"), displayText)
            case .finished:
                return String(format: L10n.tr("timer.stopwatchLabel"), displayText)
            }
        }
    }

    /// 倒计时显示剩余（向上取整，避免一开始就跳成 04:59），正计时显示已累计（向下取整）。
    private var displayText: String {
        switch store.mode {
        case .countdown:
            return Self.clock(seconds: max(Int(store.remaining.rounded(.up)), 0))
        case .stopwatch:
            return Self.clock(seconds: max(Int(store.elapsed), 0))
        }
    }

    static func clock(seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    // MARK: - 操作区

    private var controls: some View {
        HStack(spacing: Design.controlSpacing) {
            secondaryControl

            primaryButton

            trailingControl
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch (store.mode, store.runState) {
        case (.countdown, .running):
            addTimeButton
        case (.stopwatch, .running):
            lapButton
        default:
            modeSwitchButton
        }
    }

    private var addTimeButton: some View {
        Button {
            isAddTimePopoverVisible.toggle()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: Design.iconGlyphSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: Design.controlSize, height: Design.controlSize)
                .background(
                    Circle()
                        .fill(
                            .white.opacity(
                                isTrailingHovered || isAddTimePopoverVisible
                                    ? Design.secondaryHoverOpacity
                                    : 0
                            )
                        )
                        .frame(
                            width: Design.controlBackgroundSize,
                            height: Design.controlBackgroundSize
                        )
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: Design.hoverDuration),
                            value: isTrailingHovered
                        )
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: Design.hoverDuration),
                            value: isAddTimePopoverVisible
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(NowTimerPressStyle(reduceMotion: reduceMotion))
        .onHover { isTrailingHovered = $0 }
        .islandPopover(isPresented: $isAddTimePopoverVisible, arrowEdge: .top) {
            addTimePopoverContent
        }
        .help("timer.addTime")
        .accessibilityLabel("timer.addTime")
        .accessibilityHint("timer.addTimeHint")
    }

    private var addTimePopoverContent: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Self.addTimeOptions) { option in
                TimerPopoverRow(title: option.title) {
                    extendCountdown(by: option.seconds)
                    isAddTimePopoverVisible = false
                }
            }
        }
        .padding(10)
        .frame(width: 112)
    }

    private static let addTimeOptions: [AddTimeOption] = [
        AddTimeOption(seconds: 30, title: L10n.tr("timer.add30Seconds")),
        AddTimeOption(seconds: 60, title: L10n.tr("timer.add1Minute")),
        AddTimeOption(seconds: 3 * 60, title: L10n.tr("timer.add3Minutes")),
        AddTimeOption(seconds: 5 * 60, title: L10n.tr("timer.add5Minutes")),
        AddTimeOption(seconds: 10 * 60, title: L10n.tr("timer.add10Minutes")),
        AddTimeOption(seconds: 15 * 60, title: L10n.tr("timer.add15Minutes")),
        AddTimeOption(seconds: 30 * 60, title: L10n.tr("timer.add30Minutes")),
        AddTimeOption(seconds: 60 * 60, title: L10n.tr("timer.add1Hour")),
    ]

    private var lapButton: some View {
        Button(action: recordLap) {
            Image(systemName: "flag.fill")
                .font(.system(size: Design.iconGlyphSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: Design.controlSize, height: Design.controlSize)
                .background(
                    Circle()
                        .fill(
                            .white.opacity(
                                isTrailingHovered ? Design.secondaryHoverOpacity : 0
                            )
                        )
                        .frame(
                            width: Design.controlBackgroundSize,
                            height: Design.controlBackgroundSize
                        )
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: Design.hoverDuration),
                            value: isTrailingHovered
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(NowTimerPressStyle(reduceMotion: reduceMotion))
        .onHover { isTrailingHovered = $0 }
        .help("timer.recordLap")
        .accessibilityLabel("timer.recordLap")
    }


    @ViewBuilder
    private var secondaryControl: some View {
        if isEnteringDuration {
            iconButton(
                symbol: "xmark",
                help: L10n.tr("timer.cancelInput"),
                action: cancelDurationEntry
            )
        } else {
            iconButton(
                symbol: "arrow.counterclockwise",
                help: L10n.tr("timer.reset"),
                isEnabled: canReset,
                action: resetAction
            )
        }
    }

    private var primaryButton: some View {
        Button(action: togglePrimary) {
            Image(systemName: primarySymbol)
                .font(.system(size: Design.primaryGlyphSize, weight: .semibold))
                .foregroundStyle(.white.opacity(isPrimaryEnabled ? 1 : 0.32))
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.14),
                    value: primarySymbol
                )
                .frame(width: Design.controlSize, height: Design.controlSize)
                .background(
                    Circle()
                        .fill(
                            .white.opacity(
                                isPrimaryEnabled && isPrimaryHovered
                                    ? Design.secondaryHoverOpacity
                                    : 0
                            )
                        )
                        .frame(
                            width: Design.controlBackgroundSize,
                            height: Design.controlBackgroundSize
                        )
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: Design.hoverDuration),
                            value: isPrimaryHovered
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(NowTimerPressStyle(reduceMotion: reduceMotion))
        .disabled(!isPrimaryEnabled)
        .onHover { isHovering in
            isPrimaryHovered = isPrimaryEnabled && isHovering
        }
        .onChange(of: isPrimaryEnabled) { _, isEnabled in
            if !isEnabled { isPrimaryHovered = false }
        }
        .help(primaryHelp)
        .accessibilityLabel(primaryHelp)
    }

    private var modeSwitchSymbol: String {
        store.mode == .countdown ? "stopwatch" : "hourglass"
    }

    private var modeSwitchButton: some View {
        Button(action: switchMode) {
            Image(systemName: modeSwitchSymbol)
                .font(.system(size: Design.iconGlyphSize, weight: .semibold))
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.14),
                    value: modeSwitchSymbol
                )
                .foregroundStyle(.white.opacity(store.isRunning ? 0.28 : 0.92))
                .frame(width: Design.controlSize, height: Design.controlSize)
                .background(
                    Circle()
                        .fill(
                            .white.opacity(
                                !store.isRunning && isModeHovered
                                    ? Design.secondaryHoverOpacity
                                    : 0
                            )
                        )
                        .frame(
                            width: Design.controlBackgroundSize,
                            height: Design.controlBackgroundSize
                        )
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: Design.hoverDuration),
                            value: isModeHovered
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(NowTimerPressStyle(reduceMotion: reduceMotion))
        .disabled(store.isRunning)
        .onHover { isHovering in
            isModeHovered = !store.isRunning && isHovering
        }
        .help(store.mode == .countdown ? "timer.switchToStopwatch" : "timer.switchToCountdown")
        .accessibilityLabel(store.mode == .countdown ? "timer.switchToStopwatch" : "timer.switchToCountdown")
    }

    private func iconButton(
        symbol: String,
        help: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Design.iconGlyphSize, weight: .semibold))
                .foregroundStyle(.white.opacity(isEnabled ? 0.92 : 0.28))
                .frame(width: Design.controlSize, height: Design.controlSize)
                .background(
                    Circle()
                        .fill(
                            .white.opacity(
                                isEnabled && isSecondaryHovered
                                    ? Design.secondaryHoverOpacity
                                    : 0
                            )
                        )
                        .frame(
                            width: Design.controlBackgroundSize,
                            height: Design.controlBackgroundSize
                        )
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: Design.hoverDuration),
                            value: isSecondaryHovered
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(NowTimerPressStyle(reduceMotion: reduceMotion))
        .disabled(!isEnabled)
        .onHover { isHovering in
            isSecondaryHovered = isEnabled && isHovering
        }
        .help(help)
        .accessibilityLabel(help)
    }

    private var isPrimaryEnabled: Bool {
        guard isEnteringDuration else { return true }
        return (Int(durationDraft) ?? 0) > 0
    }

    private var canReset: Bool {
        switch store.runState {
        case .idle:
            return store.mode == .stopwatch ? store.elapsed > 0 : store.countdownDuration > 0
        case .running, .paused, .finished:
            return true
        }
    }

    private var primarySymbol: String {
        switch store.runState {
        case .running: "pause.fill"
        case .finished: "arrow.clockwise"
        case .idle, .paused: "play.fill"
        }
    }

    private var primaryHelp: String {
        if isEnteringDuration {
            return isPrimaryEnabled ? L10n.tr("timer.startTimer") : L10n.tr("timer.enterPositiveDuration")
        }
        if store.needsCountdownInput { return L10n.tr("timer.setDurationAndStart") }
        switch store.runState {
        case .running: return L10n.tr("timer.pause")
        case .finished: return L10n.tr("timer.restart")
        case .idle, .paused: return L10n.tr("timer.start")
        }
    }

    private func togglePrimary() {
        if isRenaming { commitName() }
        if isEnteringDuration {
            commitDurationAndStart()
            return
        }
        if store.needsCountdownInput {
            beginDurationEntry()
            return
        }
        store.toggle()
    }

    private func beginDurationEntry() {
        if isRenaming { commitName() }
        durationDraft = String(lastDurationValue)
        durationUnit = lastDurationUnit
        hoveredUnit = nil
        isEnteringDuration = true
        isDurationFieldFocused = false
        activateForInput()
        refocusDurationField()
    }

    private func refocusDurationField() {
        durationFocusRequest &+= 1
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            if isEnteringDuration { isDurationFieldFocused = true }
        }
    }

    private func commitDurationAndStart() {
        guard let value = Int(durationDraft), value > 0 else { return }
        let seconds = min(
            TimeInterval(value) * durationUnit.multiplier,
            TimerStore.countdownMaximum
        )
        lastDurationValue = value
        lastDurationUnit = durationUnit
        isEnteringDuration = false
        isDurationFieldFocused = false
        hoveredUnit = nil
        store.setCountdownDuration(seconds)
        store.start()
    }

    private func cancelDurationEntry() {
        isEnteringDuration = false
        isDurationFieldFocused = false
        durationDraft = ""
        hoveredUnit = nil
    }

    private func resetAction() {
        if isRenaming { commitName() }
        cancelDurationEntry()
        store.reset()
    }

    private func recordLap() {
        if isRenaming { commitName() }
        store.recordLap()
    }

    private func extendCountdown(by delta: TimeInterval) {
        if isRenaming { commitName() }
        store.extendCountdown(by: delta)
    }

    private func switchMode() {
        cancelDurationEntry()
        withAnimation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.86)) {
            let next: TimerStore.Mode = store.mode == .countdown ? .stopwatch : .countdown
            store.setMode(next)
        }
    }

    // MARK: - 设计参数

    private enum DurationUnit: String, CaseIterable {
        case seconds
        case minutes
        case hours

        var label: String {
            switch self {
            case .seconds: L10n.tr("timer.unitSecond")
            case .minutes: L10n.tr("timer.unitMinute")
            case .hours: L10n.tr("timer.unitHour")
            }
        }

        var helpLabel: String {
            switch self {
            case .seconds: L10n.tr("timer.unitSecondFull")
            case .minutes: L10n.tr("timer.unitMinuteFull")
            case .hours: L10n.tr("timer.unitHourFull")
            }
        }

        var multiplier: TimeInterval {
            switch self {
            case .seconds: 1
            case .minutes: 60
            case .hours: 3600
            }
        }
    }

    private enum Design {
        static let horizontalPadding: CGFloat = 8
        static let topPadding: CGFloat = 8
        static let bottomPadding: CGFloat = 4
        static let controlsTopGap: CGFloat = 2
        static let timeSize: CGFloat = 32
        static let timeTracking: CGFloat = 0.5
        static let timeHeight: CGFloat = 36
        static let modeLabelTracking: CGFloat = 1.2
        static let modeLabelGap: CGFloat = 3
        static let detailRowHeight: CGFloat = 18
        static let statusIconSize: CGFloat = 8
        static let statusIconGap: CGFloat = 3
        static let nameSize: CGFloat = 10
        static let nameFieldWidth: CGFloat = 112
        static let nameFieldHeight: CGFloat = 18
        static let durationFieldWidth: CGFloat = 110
        static let durationUnitSpacing: CGFloat = 2
        static let durationUnitHorizontalPadding: CGFloat = 5
        static let durationUnitHeight: CGFloat = 16
        static let durationUnitSize: CGFloat = 9

        static let controlSize: CGFloat = 44
        static let controlBackgroundSize: CGFloat = 34
        static let secondaryHoverOpacity: Double = 0.08
        static let hoverDuration: TimeInterval = 0.14
        static let controlSpacing: CGFloat = 0
        static let primaryGlyphSize: CGFloat = 16
        static let iconGlyphSize: CGFloat = 15
        static let finishedColor = Color(red: 1.0, green: 0.66, blue: 0.30).opacity(0.95)
    }
}

private func styleTimerFieldEditor(_ editor: NSTextView?) {
    guard let editor else { return }
    editor.insertionPointColor = NSColor.white.withAlphaComponent(0.9)
    editor.selectedTextAttributes = [
        .backgroundColor: NSColor.white.withAlphaComponent(0.16),
        .foregroundColor: NSColor.white,
    ]
}

private struct TimerDurationField: NSViewRepresentable {
    @Binding var text: String
    let accessibilityLabel: String
    let isFocused: Bool
    let focusRequest: Int
    let onFocus: () -> Void
    let onBlur: () -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TimerDurationField
        var lastFocusRequest = 0

        init(_ parent: TimerDurationField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.onFocus()
            styleTimerFieldEditor((obj.object as? NSTextField)?.currentEditor() as? NSTextView)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.onBlur()
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let filtered = String(
                field.stringValue
                    .filter { $0.isASCII && $0.isNumber }
                    .prefix(4)
            )
            if field.stringValue != filtered {
                field.stringValue = filtered
            }
            parent.text = filtered
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
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

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.font = Self.font
        field.textColor = .white.withAlphaComponent(0.95)
        field.delegate = context.coordinator
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.toolTip = L10n.tr("timer.durationToolTip")
        field.setAccessibilityLabel(accessibilityLabel)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        nsView.setAccessibilityLabel(accessibilityLabel)
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        let requestChanged = context.coordinator.lastFocusRequest != focusRequest
        if requestChanged {
            context.coordinator.lastFocusRequest = focusRequest
        }
        if isFocused, (nsView.window?.firstResponder !== nsView.currentEditor() || requestChanged) {
            DispatchQueue.main.async {
                guard let window = nsView.window else { return }
                if window.makeFirstResponder(nsView) {
                    let editor = nsView.currentEditor() as? NSTextView
                    editor?.selectAll(nil)
                    styleTimerFieldEditor(editor)
                }
            }
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSTextField,
        context: Context
    ) -> CGSize? {
        CGSize(width: 110, height: 36)
    }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        if nsView.window?.firstResponder === nsView.currentEditor() {
            nsView.window?.makeFirstResponder(nil)
        }
    }

    private static var font: NSFont {
        let base = NSFont.systemFont(ofSize: 30, weight: .semibold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else {
            return base
        }
        return NSFont(descriptor: descriptor, size: 30) ?? base
    }
}

private struct TimerNameField: NSViewRepresentable {
    @Binding var text: String
    let isFocused: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TimerNameField

        init(_ parent: TimerNameField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            styleTimerFieldEditor((obj.object as? NSTextField)?.currentEditor() as? NSTextView)
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
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

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.font = .systemFont(ofSize: 10, weight: .medium)
        field.textColor = .white.withAlphaComponent(0.9)
        field.placeholderAttributedString = Self.placeholder
        field.delegate = context.coordinator
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.toolTip = L10n.tr("timer.nameToolTip")
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if isFocused, nsView.window?.firstResponder !== nsView.currentEditor() {
            DispatchQueue.main.async {
                guard let window = nsView.window else { return }
                if window.makeFirstResponder(nsView) {
                    let editor = nsView.currentEditor() as? NSTextView
                    editor?.selectAll(nil)
                    styleTimerFieldEditor(editor)
                }
            }
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSTextField,
        context: Context
    ) -> CGSize? {
        CGSize(width: 112, height: 18)
    }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        if nsView.window?.firstResponder === nsView.currentEditor() {
            nsView.window?.makeFirstResponder(nil)
        }
    }

    private static var placeholder: NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return NSAttributedString(
            string: L10n.tr("timer.namePlaceholder"),
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.35),
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .paragraphStyle: style,
            ]
        )
    }
}

private struct AddTimeOption: Identifiable {
    let seconds: TimeInterval
    let title: String

    var id: TimeInterval { seconds }
}

private struct TimerPopoverRow: View {
    let title: String
    var value: String?
    let action: () -> Void

    var body: some View {
        IslandPopoverCell(density: .compact, action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .lineLimit(1)

                if let value {
                    Spacer(minLength: 8)

                    Text(value)
                        .monospacedDigit()
                }
            }
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.80))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct NowTimerPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.68 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
