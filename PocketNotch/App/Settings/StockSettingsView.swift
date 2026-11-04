import AppKit
import Combine
import Foundation
import PocketNotchCore
import StockModule
import SwiftUI

struct StockPrioritySettingsSection: View {
    private enum Layout {
        static let timeFieldWidth: CGFloat = 112
    }

    @ObservedObject var settings: StockSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hoveredRangeID: UUID?
    @State private var hoveredAddButton = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if settings.priorityTimeRanges.isEmpty {
                emptyState
                    .padding(.bottom, 16)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(settings.priorityTimeRanges) { range in
                        priorityTimeRangeRow(range)
                    }
                }
                .padding(.bottom, 16)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.18),
                    value: settings.priorityTimeRanges
                )
            }
        }
        .onHover { hovering in
            if !hovering {
                hoveredRangeID = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("settings.stocks.priorityTimeRange")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                settings.addPriorityTimeRange()
                hoveredRangeID = nil
            } label: {
                Label("settings.stocks.addTimeRange", systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hoveredAddButton ? Color.primary : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule()
                            .fill(
                                hoveredAddButton
                                    ? Color.primary.opacity(0.14)
                                    : Color.primary.opacity(0.08)
                            )
                    }
            }
            .buttonStyle(AddTimeRangeButtonStyle(reduceMotion: reduceMotion))
            .onHover { hoveredAddButton = $0 }
            .help(NSLocalizedString("settings.stocks.addTimeRange.help", comment: ""))
        }
        .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text("settings.stocks.noPriorityTimeRange")
                .settingsNoteStyle(fixedSize: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func priorityTimeRangeRow(_ range: StockPriorityTimeRange) -> some View {
        let isHovered = hoveredRangeID == range.id

        return HStack(alignment: .center, spacing: 8) {
            timeField(caption: NSLocalizedString("settings.stocks.start", comment: ""), rangeID: range.id, isStart: true)

            Text("settings.stocks.to")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)

            timeField(caption: NSLocalizedString("settings.stocks.end", comment: ""), rangeID: range.id, isStart: false)

            Spacer(minLength: 4)

            Button(role: .destructive) {
                settings.removePriorityTimeRange(id: range.id)
            } label: {
                Image(systemName: isHovered ? "minus.circle.fill" : "minus.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background {
                        Circle()
                            .fill(Color.primary.opacity(isHovered ? 0.10 : 0))
                    }
            }
            .buttonStyle(.borderless)
            .frame(width: 44, height: 44, alignment: .center)
            .contentShape(Rectangle())
            .help(NSLocalizedString("settings.stocks.deleteTimeRange.help", comment: ""))
            .accessibilityLabel(NSLocalizedString("settings.stocks.deleteTimeRange.help", comment: ""))
        }
        .padding(.leading, 8)
        .frame(minHeight: AppearanceRowLayout.moduleRowHeight)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isHovered ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06),
                    lineWidth: 1
                )
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: isHovered
        )
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                hoveredRangeID = hovering ? range.id : nil
            }
        }
        .transition(.opacity)
    }

    private func timeField(caption: String, rangeID: UUID, isStart: Bool) -> some View {
        DatePicker(
            caption,
            selection: timeBinding(for: rangeID, isStart: isStart),
            displayedComponents: .hourAndMinute
        )
        .datePickerStyle(.stepperField)
        .labelsHidden()
        .font(.system(size: 12, weight: .medium))
        .accessibilityLabel(caption)
    }

    private struct AddTimeRangeButtonStyle: ButtonStyle {
        let reduceMotion: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .opacity(configuration.isPressed ? 0.9 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    private func timeBinding(for id: UUID, isStart: Bool) -> Binding<Date> {
        Binding(
            get: {
                guard let range = settings.priorityTimeRanges.first(where: { $0.id == id }) else {
                    return Date()
                }
                return date(for: isStart ? range.startMinute : range.endMinute)
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                guard let hour = components.hour, let minute = components.minute else { return }
                let minuteOfDay = hour * 60 + minute
                if isStart {
                    settings.updatePriorityTimeRange(id: id, startMinute: minuteOfDay)
                } else {
                    settings.updatePriorityTimeRange(id: id, endMinute: minuteOfDay)
                }
            }
        )
    }

    private func date(for minuteOfDay: Int) -> Date {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .minute, value: minuteOfDay, to: startOfDay) ?? startOfDay
    }
}

struct StockSettingsView: View {
    @ObservedObject var settings: StockSettings
    var isEmbedded = false
    var appearanceSettings: IslandAppearanceSettings?
    var registry: ModuleRegistry?
    var wallpaperImage: NSImage?

    private enum StockPreviewLayout {
        static let previewSize = CGSize(width: 270, height: 164)
    }

    var body: some View {
        Group {
            if isEmbedded {
                cards
            } else {
                ScrollView {
                    cards
                        .frame(maxWidth: 620, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 28)
                }
                .settingsDetailScrolling()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: SettingsHeaderLayout.cardSpacing) {
            if !isEmbedded {
                SettingsCard {
                    realtimeStockCard
                }
            }

            SettingsCard {
                stockPreviewCard
            }

            if !isEmbedded {
                SettingsCard {
                    priorityCard
                }
            }
        }
    }

    private var realtimeStockCard: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("settings.stocks.realtimeStock")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                stockStatusBadge
            }

            Spacer(minLength: 8)

            Toggle("settings.stocks.showStockMonitoring", isOn: $settings.isPersistent)
                .labelsHidden()
                .toggleStyle(SettingsCompactSwitchToggleStyle())
                .frame(width: 44, height: 44)
                .accessibilityHint("settings.stocks.showStockMonitoring.description")
        }
        .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)
    }

    var stockPreviewCard: some View {
        Group {
            if let appearanceSettings, let registry {
                HStack(alignment: .top, spacing: 0) {
                    Text("settings.stocks.stockDynamic")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    CompactContentPreview(
                        feature: .stocks,
                        registry: registry,
                        wallpaperImage: wallpaperImage,
                        previewHeight: StockPreviewLayout.previewSize.height,
                        previewIslandSize: AppearancePreviewLayout.stockPreviewIslandSize
                    )
                    .frame(
                        width: StockPreviewLayout.previewSize.width,
                        height: StockPreviewLayout.previewSize.height
                    )
                }
                .frame(height: StockPreviewLayout.previewSize.height)
                .padding(.vertical, AppearanceCardLayout.contentInset)
            }
        }
    }

    private var priorityCard: some View {
        StockPrioritySettingsSection(settings: settings)
    }

    private var stockStatusBadge: some View {
        Text(settings.isPersistent ? NSLocalizedString("settings.common.enabled", comment: "") : NSLocalizedString("settings.common.closed", comment: ""))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(settings.isPersistent ? Color.accentColor : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(
                        settings.isPersistent
                            ? Color.accentColor.opacity(0.12)
                            : Color.secondary.opacity(0.10)
                    )
            }
            .animation(.easeOut(duration: 0.16), value: settings.isPersistent)
    }

    var watchlistControls: some View {
        StockWatchlistSection(settings: settings)
    }
}

struct StockWatchlistSection: View {
    @ObservedObject var settings: StockSettings

    private let names = [
        "600519": "贵州茅台",
        "002036": "联创电子",
        "688256": "寒武纪-U",
        "000001": "平安银行",
        "000333": "美的集团",
        "000858": "五粮液",
        "300750": "宁德时代",
        "300059": "东方财富",
        "600036": "招商银行",
        "601318": "中国平安",
        "600900": "长江电力",
        "601899": "紫金矿业",
        "688981": "中芯国际"
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredRowIndex: Int?
    @State private var hoveredActionKey: String?
    @State private var isReordering = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppearanceRowLayout.titleDescriptionSpacing) {
            watchlistHeader

            VStack(spacing: 0) {
                ForEach(Array(settings.orderedIDs.enumerated()), id: \.element) { index, id in
                    watchlistRow(index: index, id: id)
                    if index < settings.orderedIDs.count - 1 {
                        AppearanceRowDivider()
                    }
                }
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.18),
                value: settings.orderedIDs
            )
        }
        .padding(.vertical, AppearanceCardLayout.contentInset)
    }

    private var watchlistHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("settings.stocks.watchlistAndOrder")
                    .font(.system(size: 12, weight: .semibold))
                Text("settings.stocks.watchlistAndOrder.description")
                    .settingsNoteStyle(fixedSize: false)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            SettingsAddCapsuleButton(
                title: NSLocalizedString("settings.stocks.add", comment: ""),
                isDisabled: settings.orderedIDs.count == StockSettings.defaultOrder.count,
                help: NSLocalizedString("settings.stocks.add.help", comment: "")
            ) {
                settings.addNextDefault()
            }

            SettingsSortModeButton(isActive: $isReordering)
        }
    }

    @ViewBuilder
    private func watchlistRow(index: Int, id: String) -> some View {
        let isRowHovered = hoveredRowIndex == index
        let isFirst = index == 0
        let isLast = index == settings.orderedIDs.count - 1

        let row = HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(isRowHovered ? Color.primary : Color.secondary)
                .frame(width: 18, height: 18)
                .background {
                    Circle()
                        .fill(Color.primary.opacity(isRowHovered ? 0.10 : 0.06))
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(names[id] ?? id)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(id)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isReordering {
                HStack(spacing: 0) {
                    if isFirst {
                        Color.clear
                            .frame(width: 44, height: 44)
                    } else {
                        SettingsMoveArrowButton(
                            systemImage: "chevron.up",
                            help: NSLocalizedString("settings.common.moveUp", comment: ""),
                            xOffset: 7
                        ) {
                            settings.moveUp(id: id)
                        }
                    }

                    if isLast {
                        Color.clear
                            .frame(width: 44, height: 44)
                    } else {
                        SettingsMoveArrowButton(
                            systemImage: "chevron.down",
                            help: NSLocalizedString("settings.common.moveDown", comment: ""),
                            xOffset: -7
                        ) {
                            settings.moveDown(id: id)
                        }
                    }
                }
            } else {
                rowActionButton(
                    actionKey: "\(id)-remove",
                    symbol: "minus.circle",
                    isHoveredSymbol: "minus.circle.fill",
                    help: NSLocalizedString("settings.common.delete", comment: "")
                ) {
                    settings.remove(id: id)
                }
            }
        }
        .frame(minHeight: AppearanceRowLayout.moduleRowHeight)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.2),
            value: isReordering
        )
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                hoveredRowIndex = hovering ? index : nil
            }
        }

        return row
    }

    private func rowActionButton(
        actionKey: String,
        symbol: String,
        isHoveredSymbol: String? = nil,
        isDisabled: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredActionKey == actionKey

        return Button(action: action) {
            Image(systemName: isHoveredSymbol.map { isHovered ? $0 : symbol } ?? symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(Color.primary.opacity(isHovered ? 0.10 : 0))
                }
        }
        .buttonStyle(.borderless)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.3 : 1)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                hoveredActionKey = hovering ? actionKey : nil
            }
        }
        .help(help)
    }
}

/// 排序模式的本地切换按钮：进入排序模式后行内显示上移/下移图标。
private struct SettingsSortModeButton: View {
    @Binding var isActive: Bool

    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                isActive.toggle()
            }
        } label: {
            Label(
                LocalizedStringKey(isActive ? "settings.common.done" : "settings.common.sort"),
                systemImage: isActive ? "checkmark" : "arrow.up.arrow.down"
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(
                        isActive
                            ? Color.accentColor.opacity(isHovering ? 0.18 : 0.12)
                            : Color.primary.opacity(isHovering ? 0.12 : 0.06)
                    )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .onHover { isHovering = $0 }
        .help(isActive ? NSLocalizedString("settings.common.finishSort", comment: "") : NSLocalizedString("settings.common.enterSort", comment: ""))
        .accessibilityLabel(isActive ? NSLocalizedString("settings.common.finishSort", comment: "") : NSLocalizedString("settings.common.enterSort", comment: ""))
    }
}
