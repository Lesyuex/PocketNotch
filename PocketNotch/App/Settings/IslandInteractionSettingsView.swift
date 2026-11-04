import AppKit
import Combine
import PocketNotchCore
import SwiftUI

struct IslandInteractionSettingsView: View {
    @ObservedObject var settings: NotchInteractionSettings
    @ObservedObject var tabSettings: ExpandedTabSettings
    @ObservedObject var displaySettings: NotchDisplaySettings
    let onDisplaySelectionChange: () -> Void
    @State private var connectedDisplays = NotchDisplayCatalog.connectedDisplays()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let allDisplaysSelection = "__all_displays__"

    private var hoverDelayBinding: Binding<Double> {
        Binding(
            get: { settings.hoverRevealDelay },
            set: { settings.setHoverRevealDelay($0) }
        )
    }

    private var usesDefaults: Bool {
        settings.isMinimalModeEnabled == false
            && settings.hoverRevealDelay == NotchInteractionSettings.defaultHoverRevealDelay
            && settings.isClickEnabled
            && settings.hoverHapticIntensity == .light
            && settings.isHiddenInScreenCapture
            && settings.isHoverTriggerEnabled
            && tabSettings.order == ExpandedIslandTab.defaultOrder
            && tabSettings.disabledTabs.isEmpty
            && displaySettings.mode == .all
            && displaySettings.selectedDisplayIdentifier == nil
    }

    private var displaySelectionBinding: Binding<String> {
        Binding(
            get: {
                guard displaySettings.mode == .single else {
                    return Self.allDisplaysSelection
                }

                if let selectedIdentifier = displaySettings.selectedDisplayIdentifier,
                   connectedDisplays.contains(where: { $0.id == selectedIdentifier }) {
                    return selectedIdentifier
                }

                if let recommendedIdentifier = NotchDisplayCatalog.recommendedDisplayIdentifier(),
                   connectedDisplays.contains(where: { $0.id == recommendedIdentifier }) {
                    return recommendedIdentifier
                }

                return connectedDisplays.first?.id ?? Self.allDisplaysSelection
            },
            set: { selection in
                if selection == Self.allDisplaysSelection {
                    displaySettings.showOnAllDisplays()
                } else {
                    displaySettings.showOnDisplay(identifier: selection)
                }
                onDisplaySelectionChange()
            }
        )
    }

    private var hoverDelayText: String {
        String(format: NSLocalizedString("settings.interaction.hoverDelayFormat", comment: ""), settings.hoverRevealDelay)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsHeaderLayout.cardSpacing) {
                header
                interactionCard
                expandedTabsCard
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .settingsDetailScrolling()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        Color.clear
            .frame(height: SettingsHeaderLayout.placeholderHeight)
            .overlay(alignment: .topTrailing) {
                SettingsResetButton(isDisabled: usesDefaults) {
                    settings.resetToDefaults()
                    tabSettings.resetToDefaults()
                    displaySettings.resetToDefault()
                    onDisplaySelectionChange()
                }
                .offset(y: SettingsHeaderLayout.resetButtonOffset)
            }
            .padding(.bottom, SettingsHeaderLayout.surroundingPadding)
    }

    private var interactionCard: some View {
        SettingsCard {
            minimalModeSection

            AppearanceRowDivider()

            displaySection

            AppearanceRowDivider()

            hoverTriggerSection

            AppearanceRowDivider()

            hoverDelaySection

            AppearanceRowDivider()

            hoverHapticSection

            AppearanceRowDivider()

            clickSection

            AppearanceRowDivider()

            screenCaptureSection
        }
    }

    private var minimalModeSection: some View {
        ModuleSettingRow(
            title: NSLocalizedString("settings.interaction.minimalMode", comment: ""),
            description: nil,
            controlWidth: interactionControlWidth
        ) {
            Toggle("settings.interaction.minimalMode", isOn: $settings.isMinimalModeEnabled)
                .labelsHidden()
                .toggleStyle(SettingsCompactSwitchToggleStyle())
                .frame(width: 44, height: 44)
                .accessibilityHint("settings.interaction.minimalMode.description")
        }
        .animation(.easeOut(duration: 0.16), value: settings.isMinimalModeEnabled)
    }

    private var currentDisplayLabel: String {
        let selection = displaySelectionBinding.wrappedValue
        if selection == Self.allDisplaysSelection {
            return NSLocalizedString("settings.interaction.allDisplays", comment: "")
        }
        return connectedDisplays.first(where: { $0.id == selection })?.name ?? NSLocalizedString("settings.interaction.allDisplays", comment: "")
    }

    private var displaySection: some View {
        ModuleSettingRow(
            title: NSLocalizedString("settings.interaction.selectDisplay", comment: ""),
            description: nil,
            controlWidth: interactionControlWidth
        ) {
            SettingsMenuPicker(
                selection: displaySelectionBinding,
                options: [Self.allDisplaysSelection] + connectedDisplays.map { $0.id },
                optionTitle: { option in
                    if option == Self.allDisplaysSelection {
                        return NSLocalizedString("settings.interaction.allDisplays", comment: "")
                    }
                    return connectedDisplays.first(where: { $0.id == option })?.name ?? ""
                },
                currentTitle: currentDisplayLabel,
                accessibilityLabel: NSLocalizedString("settings.interaction.selectDisplay", comment: "")
            )
            .accessibilityHint("settings.interaction.selectDisplay.description")
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification
            )
        ) { _ in
            connectedDisplays = NotchDisplayCatalog.connectedDisplays()
        }
    }

    private var hoverTriggerSection: some View {
        ModuleSettingRow(
            title: NSLocalizedString("settings.interaction.hoverTrigger", comment: ""),
            description: nil,
            controlWidth: interactionControlWidth
        ) {
            Toggle("settings.interaction.hoverTrigger", isOn: $settings.isHoverTriggerEnabled)
                .labelsHidden()
                .toggleStyle(SettingsCompactSwitchToggleStyle())
                .frame(width: 44, height: 44)
                .accessibilityHint("settings.interaction.hoverTrigger.description")
        }
        .animation(.easeOut(duration: 0.16), value: settings.isHoverTriggerEnabled)
    }

    private var hoverDelaySection: some View {
        VStack(alignment: .leading, spacing: AppearanceRowLayout.titleDescriptionSpacing) {
            HStack(alignment: .center, spacing: 12) {
                    Text("settings.interaction.hoverRevealDelay")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LabeledValueSlider(
                        value: hoverDelayBinding,
                        range: NotchInteractionSettings.hoverRevealDelayRange,
                        width: AppearanceRowLayout.valueSliderWidth,
                        valueText: hoverDelayText,
                        sliderLabel: NSLocalizedString("settings.interaction.hoverRevealDelay", comment: ""),
                        sliderHint: NSLocalizedString("settings.interaction.hoverRevealDelay.hint", comment: "")
                    )
            }
        }
        .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)
        .disabled(!settings.isHoverTriggerEnabled)
        .opacity(settings.isHoverTriggerEnabled ? 1 : 0.55)
    }

    private var clickSection: some View {
        ModuleSettingRow(
            title: NSLocalizedString("settings.interaction.clickToExpand", comment: ""),
            description: nil,
            controlWidth: interactionControlWidth
        ) {
            Toggle("settings.interaction.clickToExpand", isOn: $settings.isClickEnabled)
                .labelsHidden()
                .toggleStyle(SettingsCompactSwitchToggleStyle())
                .frame(width: 44, height: 44)
                .accessibilityHint("settings.interaction.clickToExpand.description")
        }
        .animation(.easeOut(duration: 0.16), value: settings.isClickEnabled)
    }

    private var hoverHapticSection: some View {
        ModuleSettingRow(
            title: NSLocalizedString("settings.interaction.hoverHaptic", comment: ""),
            description: nil,
            controlWidth: interactionControlWidth
        ) {
            SettingsSegmentedControl(
                selection: $settings.hoverHapticIntensity,
                options: HoverHapticIntensity.allCases,
                title: hapticIntensityTitle,
                accessibilityTitle: NSLocalizedString("settings.interaction.hoverHaptic", comment: ""),
                onSelect: performHaptic,
                onHover: { intensity, isInside in
                    if isInside { performHaptic(intensity) }
                }
            )
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func hapticIntensityTitle(_ intensity: HoverHapticIntensity) -> String {
        switch intensity {
        case .none: NSLocalizedString("settings.interaction.hapticNone", comment: "")
        case .light: NSLocalizedString("settings.interaction.hapticLight", comment: "")
        case .medium: NSLocalizedString("settings.interaction.hapticMedium", comment: "")
        case .strong: NSLocalizedString("settings.interaction.hapticStrong", comment: "")
        }
    }

    private func performHaptic(_ intensity: HoverHapticIntensity) {
        guard intensity != .none else { return }
        let performer = NSHapticFeedbackManager.defaultPerformer
        performer.perform(.levelChange, performanceTime: .now)
        if intensity == .medium || intensity == .strong {
            performer.perform(.levelChange, performanceTime: .now)
        }
        if intensity == .strong {
            performer.perform(.levelChange, performanceTime: .now)
        }
    }

    private var screenCaptureSection: some View {
        ModuleSettingRow(
            title: NSLocalizedString("settings.interaction.hideInScreenshot", comment: ""),
            description: nil,
            controlWidth: interactionControlWidth
        ) {
            Toggle("settings.interaction.hideInScreenshot", isOn: $settings.isHiddenInScreenCapture)
                .labelsHidden()
                .toggleStyle(SettingsCompactSwitchToggleStyle())
                .frame(width: 44, height: 44)
                .accessibilityHint("settings.interaction.hideInScreenshot.description")
        }
        .animation(.easeOut(duration: 0.16), value: settings.isHiddenInScreenCapture)
    }

    // MARK: - 展开页标签

    private var expandedTabsCard: some View {
        SettingsCard {
            expandedTabsHeader

            AppearanceRowDivider()

            VStack(spacing: 0) {
                let tabs = tabSettings.managedTabs
                ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                    expandedTabRow(tab, isFirst: index == 0, isLast: index == tabs.count - 1)
                    if index < tabs.count - 1 {
                        AppearanceRowDivider()
                    }
                }
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.18),
                value: tabSettings.order
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.18),
                value: tabSettings.disabledTabs
            )
        }
    }

    private var expandedTabsHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("settings.interaction.expandedTabs")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            Text("settings.interaction.expandedTabs.description")
                .settingsNoteStyle(fixedSize: false)
                .lineLimit(1)
        }
        .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)
    }

    private func expandedTabRow(
        _ tab: ExpandedIslandTab,
        isFirst: Bool,
        isLast: Bool
    ) -> some View {
        let isEnabled = tabSettings.isEnabled(tab)
        let isOnlyEnabledTab = isEnabled && tabSettings.visibleTabs.count <= 1

        return HStack(spacing: 12) {
            Text(tab.displayName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(LocalizedStringKey(String(format: NSLocalizedString("settings.interaction.showTabFormat", comment: ""), tab.displayName)), isOn: Binding(
                get: { isEnabled },
                set: { tabSettings.setEnabled($0, for: tab) }
            ))
            .labelsHidden()
            .toggleStyle(SettingsCompactSwitchToggleStyle())
            .frame(width: 44, height: 44)
            .disabled(isOnlyEnabledTab)
            .accessibilityHint(isOnlyEnabledTab ? NSLocalizedString("settings.interaction.keepAtLeastOneTab", comment: "") : NSLocalizedString("settings.interaction.controlTabVisibility", comment: ""))

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
                        tabSettings.moveUp(tab)
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
                        tabSettings.moveDown(tab)
                    }
                }
            }
        }
        .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)
        .opacity(isEnabled ? 1 : 0.55)
        .animation(.easeOut(duration: 0.16), value: isEnabled)
    }

    private var interactionControlWidth: CGFloat {
        AppearanceRowLayout.rangeControlWidth
            + AppearanceRowLayout.controlSpacing
            + AppearanceRowLayout.actionWidth
    }
}
