import Combine
import PocketNotchCore
import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject var settings: IslandNotificationSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsHeaderLayout.cardSpacing) {
                header
                    .padding(.bottom, SettingsHeaderLayout.surroundingPadding)

                songChangeNotificationCard

                notificationCard(rows: islandNotificationRows)

                SettingsCard {
                    NotificationToggleRow(item: volumeToggleItem)
                    AppearanceRowDivider()
                    rightEarBatteryToggleRow
                    AppearanceRowDivider()
                    NotificationToggleRow(item: hideSystemVolumeHUDItem)
                    AppearanceRowDivider()
                    volumeIconStyleRow
                    AppearanceRowDivider()
                    volumeBarColorSection
                }

                SettingsCard {
                    NotificationToggleRow(item: brightnessToggleItem)
                    AppearanceRowDivider()
                    brightnessPercentageToggleRow
                    AppearanceRowDivider()
                    NotificationToggleRow(item: hideSystemBrightnessHUDItem)
                }
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
                SettingsResetButton(isDisabled: settings.usesDefaultValues) {
                    settings.resetToDefault()
                }
                .offset(y: SettingsHeaderLayout.resetButtonOffset)
            }
    }

    private func notificationCard(
        rows: [NotificationToggleItem]
    ) -> some View {
        SettingsCard {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                NotificationToggleRow(item: item)

                if index < rows.count - 1 {
                    AppearanceRowDivider()
                }
            }
        }
    }


    private var islandNotificationRows: [NotificationToggleItem] {
        [
            NotificationToggleItem(
                title: NSLocalizedString("settings.notification.batteryStatus", comment: ""),
                description: NSLocalizedString("settings.notification.batteryStatus.description", comment: ""),
                isOn: binding(\.isPowerStatusEnabled)
            ),
            NotificationToggleItem(
                title: NSLocalizedString("settings.notification.deviceConnection", comment: ""),
                description: NSLocalizedString("settings.notification.deviceConnection.description", comment: ""),
                isOn: binding(\.isBluetoothConnectionEnabled)
            ),
        ]
    }

    private var volumeToggleItem: NotificationToggleItem {
        NotificationToggleItem(
            title: NSLocalizedString("settings.notification.volumeAdjustment", comment: ""),
            description: NSLocalizedString("settings.notification.volumeAdjustment.description", comment: ""),
            isOn: binding(\.isVolumeAdjustmentEnabled)
        )
    }

    private var brightnessToggleItem: NotificationToggleItem {
        NotificationToggleItem(
            title: NSLocalizedString("settings.notification.brightnessAdjustment", comment: ""),
            description: NSLocalizedString("settings.notification.brightnessAdjustment.description", comment: ""),
            isOn: binding(\.isBrightnessAdjustmentEnabled)
        )
    }

    private var hideSystemVolumeHUDItem: NotificationToggleItem {
        NotificationToggleItem(
            title: NSLocalizedString("settings.notification.hideSystemVolumeHUD", comment: ""),
            description: NSLocalizedString("settings.notification.hideSystemVolumeHUD.description", comment: ""),
            isOn: binding(\.isSystemVolumeHUDHidden),
            isEnabled: settings.isVolumeAdjustmentEnabled
        )
    }

    private var hideSystemBrightnessHUDItem: NotificationToggleItem {
        NotificationToggleItem(
            title: NSLocalizedString("settings.notification.hideSystemBrightnessHUD", comment: ""),
            description: NSLocalizedString("settings.notification.hideSystemBrightnessHUD.description", comment: ""),
            isOn: binding(\.isSystemBrightnessHUDHidden),
            isEnabled: settings.isBrightnessAdjustmentEnabled
        )
    }

    private var volumeIconStyleRow: some View {
        ModuleSettingRow(
            title: NSLocalizedString("settings.notification.volumeIcon", comment: ""),
            description: NSLocalizedString("settings.notification.volumeIcon.description", comment: "")
        ) {
            SettingsSegmentedControl(
                selection: volumeIconStyleBinding,
                options: VolumeIconStyle.allCases,
                title: { $0.caption },
                accessibilityTitle: NSLocalizedString("settings.notification.volumeIcon", comment: ""),
                symbolName: { $0.symbolName }
            )
        }
    }

    private var rightEarBatteryToggleRow: some View {
        NotificationToggleRow(item: rightEarBatteryToggleItem)
    }

    private var brightnessPercentageToggleRow: some View {
        NotificationToggleRow(item: brightnessPercentageToggleItem)
    }

    private var rightEarBatteryToggleItem: NotificationToggleItem {
        NotificationToggleItem(
            title: NSLocalizedString("settings.notification.showBatteryPercentage", comment: ""),
            description: NSLocalizedString("settings.notification.showBatteryPercentage.description", comment: ""),
            isOn: binding(\.isRightEarBatteryEnabled),
            isEnabled: settings.isVolumeAdjustmentEnabled
        )
    }

    private var brightnessPercentageToggleItem: NotificationToggleItem {
        NotificationToggleItem(
            title: NSLocalizedString("settings.notification.showBrightnessPercentage", comment: ""),
            description: NSLocalizedString("settings.notification.showBrightnessPercentage.description", comment: ""),
            isOn: binding(\.isBrightnessPercentageEnabled),
            isEnabled: settings.isBrightnessAdjustmentEnabled
        )
    }

    private var volumeIconStyleBinding: Binding<VolumeIconStyle> {
        Binding(
            get: { settings.volumeIconStyle },
            set: { settings.volumeIconStyle = $0 }
        )
    }

    private var volumeBarColorSection: some View {
        VStack(spacing: 0) {
            volumeBarColorStyleRow

            if settings.volumeBarColorStyle == .coverTheme {
                AppearanceRowDivider()
                coverThemeGradientToggleRow
            }

            if settings.volumeBarColorStyle == .custom {
                AppearanceRowDivider()
                customVolumeBarColorSection
            }
        }
        .animation(.easeOut(duration: 0.16), value: settings.volumeBarColorStyle)
    }

    private var coverThemeGradientToggleRow: some View {
        ModuleSettingRow(
            title: NSLocalizedString("settings.notification.gradient", comment: ""),
            description: NSLocalizedString("settings.notification.coverGradient.description", comment: "")
        ) {
            Toggle("settings.notification.gradient", isOn: volumeBarCustomGradientBinding)
                .labelsHidden()
                .toggleStyle(SettingsCompactSwitchToggleStyle())
                .frame(width: 44, height: 44)
        }
    }

    private var volumeBarColorStyleRow: some View {
        ModuleSettingRow(
            title: NSLocalizedString("settings.notification.volumeBarColor", comment: ""),
            description: NSLocalizedString("settings.notification.volumeBarColor.description", comment: "")
        ) {
            SettingsSegmentedControl(
                selection: volumeBarColorStyleBinding,
                options: VolumeBarColorStyle.allCases,
                title: { $0.title },
                accessibilityTitle: NSLocalizedString("settings.notification.volumeBarColor", comment: "")
            )
        }
    }

    private var customVolumeBarColorSection: some View {
        VStack(spacing: 0) {
            ModuleSettingRow(
                title: NSLocalizedString("settings.notification.gradient", comment: ""),
                description: NSLocalizedString("settings.notification.customGradient.description", comment: "")
            ) {
                Toggle("settings.notification.gradient", isOn: volumeBarCustomGradientBinding)
                    .labelsHidden()
                    .toggleStyle(SettingsCompactSwitchToggleStyle())
                    .frame(width: 44, height: 44)
            }

            AppearanceRowDivider()

            ModuleSettingRow(
                title: NSLocalizedString("settings.notification.color1", comment: ""),
                description: NSLocalizedString("settings.notification.color1.description", comment: "")
            ) {
                ColorPicker("settings.notification.color1", selection: volumeBarCustomColorBinding, supportsOpacity: false)
                    .labelsHidden()
            }

            if settings.isVolumeBarCustomGradientEnabled {
                AppearanceRowDivider()

                ModuleSettingRow(
                    title: NSLocalizedString("settings.notification.color2", comment: ""),
                    description: NSLocalizedString("settings.notification.color2.description", comment: "")
                ) {
                    ColorPicker(
                        "settings.notification.color2",
                        selection: volumeBarCustomGradientEndColorBinding,
                        supportsOpacity: false
                    )
                    .labelsHidden()
                }
            }
        }
        .animation(.easeOut(duration: 0.16), value: settings.isVolumeBarCustomGradientEnabled)
    }

    private var volumeBarColorStyleBinding: Binding<VolumeBarColorStyle> {
        Binding(
            get: { settings.volumeBarColorStyle },
            set: { settings.volumeBarColorStyle = $0 }
        )
    }

    private var volumeBarCustomColorBinding: Binding<Color> {
        Binding(
            get: { settings.volumeBarCustomColor.color },
            set: { settings.volumeBarCustomColor = VolumeBarColor(color: $0) }
        )
    }

    private var volumeBarCustomGradientEndColorBinding: Binding<Color> {
        Binding(
            get: { settings.volumeBarCustomGradientEndColor.color },
            set: { settings.volumeBarCustomGradientEndColor = VolumeBarColor(color: $0) }
        )
    }

    private var volumeBarCustomGradientBinding: Binding<Bool> {
        Binding(
            get: { settings.isVolumeBarCustomGradientEnabled },
            set: { settings.isVolumeBarCustomGradientEnabled = $0 }
        )
    }

    private var songChangeNotificationCard: some View {
        SettingsCard {
            NotificationToggleRow(
                item: NotificationToggleItem(
                    title: NSLocalizedString("settings.notification.songChange", comment: ""),
                    description: NSLocalizedString("settings.notification.songChange.description", comment: ""),
                    isOn: binding(\.isSongChangeEnabled)
                )
            )
            AppearanceRowDivider()
            songChangeDismissalEffectRow
        }
    }

    private var songChangeDismissalEffectRow: some View {
        ModuleSettingRow(
            title: NSLocalizedString("settings.notification.dismissalAnimation", comment: ""),
            description: NSLocalizedString("settings.notification.dismissalAnimation.description", comment: ""),
            controlWidth: AppearanceRowLayout.rangeControlWidth
        ) {
            Picker("settings.notification.dismissalAnimation", selection: dismissalEffectBinding(\.songChangeDismissalEffect)) {
                ForEach(IslandNotificationDismissalEffect.allCases) { effect in
                    Text(effect.title).tag(effect)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .disabled(!settings.isSongChangeEnabled)
            .accessibilityLabel(NSLocalizedString("settings.notification.songChangeDismissalAnimation", comment: ""))
        }
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<IslandNotificationSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0 }
        )
    }

    private func dismissalEffectBinding(
        _ keyPath: ReferenceWritableKeyPath<IslandNotificationSettings, IslandNotificationDismissalEffect>
    ) -> Binding<IslandNotificationDismissalEffect> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0 }
        )
    }
}

private extension VolumeIconStyle {
    var symbolName: String {
        switch self {
        case .system: "speaker.wave.2.fill"
        case .device: "airpods.pro"
        }
    }

    var caption: String {
        switch self {
        case .system: NSLocalizedString("settings.notification.volumeIconDefault", comment: "")
        case .device: NSLocalizedString("settings.notification.volumeIconDevice", comment: "")
        }
    }
}

private extension VolumeBarColorStyle {
    var title: String {
        switch self {
        case .standard: NSLocalizedString("settings.notification.colorStyleDefault", comment: "")
        case .coverTheme: NSLocalizedString("settings.notification.colorStyleCoverTheme", comment: "")
        case .gradient: NSLocalizedString("settings.notification.gradient", comment: "")
        case .custom: NSLocalizedString("settings.notification.colorStyleCustom", comment: "")
        }
    }
}

private struct NotificationToggleItem: Identifiable {
    var id: String { title }
    let title: String
    let description: String
    let isOn: Binding<Bool>
    var dismissalEffect: Binding<IslandNotificationDismissalEffect>? = nil
    var isEnabled: Bool? = nil
}

private struct NotificationToggleRow: View {
    let item: NotificationToggleItem

    var body: some View {
        ModuleSettingRow(
            title: item.title,
            description: item.description,
            controlWidth: notificationControlWidth
        ) {
            HStack(spacing: 10) {
                if let dismissalEffect = item.dismissalEffect {
                    Picker("settings.notification.dismissalAnimation", selection: dismissalEffect) {
                        ForEach(IslandNotificationDismissalEffect.allCases) { effect in
                            Text(effect.title).tag(effect)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 148)
                    .disabled(!item.isOn.wrappedValue)
                    .accessibilityLabel(String(format: NSLocalizedString("settings.notification.dismissalAnimationFormat", comment: ""), item.title))
                }

                Toggle(LocalizedStringKey(item.title), isOn: item.isOn)
                    .labelsHidden()
                    .toggleStyle(SettingsCompactSwitchToggleStyle())
                    .frame(width: 44, height: 44)
                    .disabled(item.isEnabled == false)
                    .accessibilityHint(item.description)
            }
        }
        .animation(.easeOut(duration: 0.16), value: item.isOn.wrappedValue)
    }

    private var notificationControlWidth: CGFloat {
        AppearanceRowLayout.rangeControlWidth
            + AppearanceRowLayout.controlSpacing
            + AppearanceRowLayout.actionWidth
    }
}
