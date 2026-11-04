import AppKit
import Combine
import Foundation
import PocketNotchCore
import MediaModule
import SwiftUI

struct LockScreenMusicSettingsView: View {
    private enum MaterialLayout {
        static let previewSize = CGSize(width: 270, height: 164)
        static let horizontalContentInset: CGFloat = AppearanceRowLayout.contentPadding
    }

    @ObservedObject var settings: MediaMonitoringSettings
    let wallpaperImage: NSImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { settings.isLockScreenMusicEnabled },
            set: { settings.isLockScreenMusicEnabled = $0 }
        )
    }

    private var backdropStyle: Binding<LockScreenMusicBackdropStyle> {
        Binding(
            get: { settings.lockScreenMusicBackdropStyle },
            set: { settings.lockScreenMusicBackdropStyle = $0 }
        )
    }

    private var glassBlurPercent: Binding<Double> {
        Binding(
            get: { settings.lockScreenMusicGlassBlur * 100 },
            set: { settings.lockScreenMusicGlassBlur = $0 / 100 }
        )
    }

    private var glassMaterial: Binding<LiquidGlassMaterial> {
        Binding(
            get: { settings.lockScreenMusicGlassMaterial },
            set: { settings.lockScreenMusicGlassMaterial = $0 }
        )
    }

    private var solidColor: Binding<Color> {
        Binding(
            get: { settings.lockScreenMusicSolidColor.color },
            set: { settings.lockScreenMusicSolidColor = LockScreenMusicSolidColor(color: $0) }
        )
    }

    private var solidTextColor: Binding<Color> {
        Binding(
            get: { settings.lockScreenMusicSolidTextColor.color },
            set: {
                settings.lockScreenMusicSolidTextColor = LockScreenMusicSolidColor(color: $0)
            }
        )
    }

    private var usesArtworkGradient: Binding<Bool> {
        Binding(
            get: { settings.isLockScreenArtworkGradientEnabled },
            set: { settings.isLockScreenArtworkGradientEnabled = $0 }
        )
    }

    private var activeSpectrumSensitivity: Double {
        switch settings.musicSpectrumBarStyle {
        case .four: settings.fourBarSpectrumSensitivity
        case .five: settings.fiveBarSpectrumSensitivity
        case .seven: settings.sevenBarSpectrumSensitivity
        }
    }

    private var activeSpectrumAttackTime: Double {
        switch settings.musicSpectrumBarStyle {
        case .four: settings.fourBarSpectrumAttackTime
        case .five: settings.fiveBarSpectrumAttackTime
        case .seven: settings.sevenBarSpectrumAttackTime
        }
    }

    private var activeSpectrumReleaseTime: Double {
        switch settings.musicSpectrumBarStyle {
        case .four: settings.fourBarSpectrumReleaseTime
        case .five: settings.fiveBarSpectrumReleaseTime
        case .seven: settings.sevenBarSpectrumReleaseTime
        }
    }

    private var activeSpectrumWidthScale: Double { settings.musicSpectrumBarWidthScale }

    private var activeSpectrumSpacingScale: Double { settings.musicSpectrumBarSpacingScale }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsHeaderLayout.cardSpacing) {
                header
                    .padding(.bottom, SettingsHeaderLayout.surroundingPadding)

                enablementCard

                materialPreviewCard

                materialSelectionCard

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
                SettingsResetButton(isDisabled: settings.usesDefaultLockScreenValues) {
                    settings.resetLockScreenToDefault()
                }
                .offset(y: SettingsHeaderLayout.resetButtonOffset)
            }
    }

    private var enablementCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 5) {
                Text("settings.lockScreen.enableLockScreenMusic")
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            .overlay(alignment: .trailing) {
                Toggle("settings.lockScreen.enableLockScreenMusic", isOn: isEnabled)
                    .labelsHidden()
                    .toggleStyle(SettingsCompactSwitchToggleStyle())
                    .frame(width: 44, height: 44)
                    .accessibilityHint("settings.lockScreen.enableLockScreenMusic.description")
            }
            .frame(height: AppearanceRowLayout.moduleRowHeight)
        }
    }

    private var materialPreviewCard: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(materialTitle(settings.lockScreenMusicBackdropStyle))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(materialNoteText(settings.lockScreenMusicBackdropStyle))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                selectedMaterialPreview
            }
            .frame(height: MaterialLayout.previewSize.height)
            .padding(.vertical, AppearanceCardLayout.contentInset)
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: settings.lockScreenMusicBackdropStyle
        )
    }

    private var materialSelectionCard: some View {
        SettingsCard {
            HStack(spacing: 12) {
                Text("settings.lockScreen.selectStyle")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()

                Spacer(minLength: 12)

                SettingsSegmentedControl(
                    selection: backdropStyle,
                    options: LockScreenMusicBackdropStyle.allCases,
                    title: { materialTitle($0) },
                    accessibilityTitle: NSLocalizedString("settings.lockScreen.componentMaterial", comment: "")
                )
                .disabled(!settings.isLockScreenMusicEnabled)
            }
            .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)

            AppearanceRowDivider()

            selectedMaterialControls(settings.lockScreenMusicBackdropStyle)
                .disabled(!settings.isLockScreenMusicEnabled)
                .id(settings.lockScreenMusicBackdropStyle)
                .transition(modeSpecificTransition)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(settings.isLockScreenMusicEnabled ? 1 : 0.5)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: settings.lockScreenMusicBackdropStyle
        )
    }

    private func materialNoteText(_ style: LockScreenMusicBackdropStyle) -> String {
        switch style {
        case .glass: NSLocalizedString("settings.lockScreen.noteGlass", comment: "")
        case .clear: NSLocalizedString("settings.lockScreen.noteClear", comment: "")
        case .artworkTheme: NSLocalizedString("settings.lockScreen.noteArtworkTheme", comment: "")
        case .solidColor: NSLocalizedString("settings.lockScreen.noteSolidColor", comment: "")
        }
    }

    private var selectedMaterialPreview: some View {
        LockScreenMusicMaterialThumbnail(
            wallpaperImage: wallpaperImage,
            backdropStyle: settings.lockScreenMusicBackdropStyle,
            glassBlur: settings.lockScreenMusicGlassBlur,
            glassMaterial: settings.lockScreenMusicGlassMaterial,
            solidColor: settings.lockScreenMusicSolidColor,
            solidTextColor: settings.lockScreenMusicSolidTextColor,
            usesArtworkGradient: settings.isLockScreenArtworkGradientEnabled,
            isActive: settings.isLockScreenMusicEnabled,
            musicSpectrumBarStyle: settings.musicSpectrumBarStyle,
            musicSpectrumSensitivity: activeSpectrumSensitivity,
            musicSpectrumAttackTime: activeSpectrumAttackTime,
            musicSpectrumReleaseTime: activeSpectrumReleaseTime,
            musicSpectrumBarWidthScale: activeSpectrumWidthScale,
            musicSpectrumBarSpacingScale: activeSpectrumSpacingScale,
            musicSpectrumBarCornerRadiusScale: settings.musicSpectrumCornerRadiusScale
        )
        .frame(
            width: MaterialLayout.previewSize.width,
            height: MaterialLayout.previewSize.height
        )
        .id(settings.lockScreenMusicBackdropStyle)
        .transition(.opacity)
    }

    private func materialTitle(_ style: LockScreenMusicBackdropStyle) -> String {
        switch style {
        case .glass: NSLocalizedString("settings.lockScreen.frostedGlass", comment: "")
        case .clear: NSLocalizedString("settings.lockScreen.liquidGlass", comment: "")
        case .artworkTheme: NSLocalizedString("settings.lockScreen.artworkBackplate", comment: "")
        case .solidColor: NSLocalizedString("settings.lockScreen.custom", comment: "")
        }
    }

    @ViewBuilder
    private func selectedMaterialControls(_ style: LockScreenMusicBackdropStyle) -> some View {
        switch style {
        case .glass:
            frostControl
        case .clear:
            compactControlRow(title: NSLocalizedString("settings.lockScreen.glassMaterial", comment: "")) {
                Picker("settings.lockScreen.glassMaterial", selection: glassMaterial) {
                    ForEach(LiquidGlassMaterial.allCases) { material in
                        Text(material.displayName).tag(material)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        case .artworkTheme:
            compactControlRow(title: NSLocalizedString("settings.lockScreen.artworkGradient", comment: "")) {
                Toggle("settings.lockScreen.useArtworkGradient", isOn: usesArtworkGradient)
                    .labelsHidden()
                    .toggleStyle(SettingsCompactSwitchToggleStyle())
            }
        case .solidColor:
            VStack(spacing: 0) {
                compactControlRow(title: NSLocalizedString("settings.lockScreen.backdropColor", comment: "")) {
                    ColorPicker("settings.lockScreen.backdropColor", selection: solidColor, supportsOpacity: false)
                        .labelsHidden()
                }

                AppearanceRowDivider()


                compactControlRow(title: NSLocalizedString("settings.lockScreen.fontColor", comment: "")) {
                    ColorPicker("settings.lockScreen.fontColor", selection: solidTextColor, supportsOpacity: false)
                        .labelsHidden()
                }
            }
        }
    }

    private var frostControl: some View {
        AppearanceSliderRow(
            title: NSLocalizedString("settings.lockScreen.frostIntensity", comment: ""),
            subtitle: NSLocalizedString("settings.lockScreen.frostIntensity.description", comment: ""),
            value: glassBlurPercent,
            range: 0.0...100.0,
            valueText: "\(Int((settings.lockScreenMusicGlassBlur * 100).rounded()))%"
        )
    }

    private func compactControlRow<Control: View>(
        title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 16)

            control()
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
        }

        .frame(height: 56)
    }

    private var modeSpecificTransition: AnyTransition {
        .opacity
    }
}

struct MediaMonitoringSettingsView: View {
    private enum MediaPreviewLayout {
        static let previewSize = CGSize(width: 270, height: 164)
    }

    @ObservedObject var settings: MediaMonitoringSettings
    var isEmbedded = false
    var wallpaperImage: NSImage?
    var appearanceSettings: IslandAppearanceSettings?
    var registry: ModuleRegistry?

    @State private var isSpectrumTuningExpanded = false
    @State private var isSpectrumAppearanceExpanded = false

    init(
        settings: MediaMonitoringSettings,
        isEmbedded: Bool = false,
        wallpaperImage: NSImage? = nil,
        appearanceSettings: IslandAppearanceSettings? = nil,
        registry: ModuleRegistry? = nil
    ) {
        self._settings = ObservedObject(wrappedValue: settings)
        self.isEmbedded = isEmbedded
        self.wallpaperImage = wallpaperImage
        self.appearanceSettings = appearanceSettings
        self.registry = registry
    }

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { settings.isRealtimeMusicMonitoringEnabled },
            set: { settings.isRealtimeMusicMonitoringEnabled = $0 }
        )
    }

    private var isArtworkRotationEnabled: Binding<Bool> {
        Binding(
            get: { settings.isCompactArtworkRotationEnabled },
            set: { settings.isCompactArtworkRotationEnabled = $0 }
        )
    }

    private var rotatingArtworkCornerRadiusPercentage: Binding<Double> {
        Binding(
            get: { settings.compactRotatingArtworkCornerRadiusPercentage },
            set: { settings.compactRotatingArtworkCornerRadiusPercentage = $0 }
        )
    }

    private var staticArtworkCornerRadiusPercentage: Binding<Double> {
        Binding(
            get: { settings.compactStaticArtworkCornerRadiusPercentage },
            set: { settings.compactStaticArtworkCornerRadiusPercentage = $0 }
        )
    }

    private var spectrumSensitivity: Binding<Double> {
        Binding(
            get: {
                switch settings.musicSpectrumBarStyle {
                case .four: settings.fourBarSpectrumSensitivity
                case .five: settings.fiveBarSpectrumSensitivity
                case .seven: settings.sevenBarSpectrumSensitivity
                }
            },
            set: { value in
                switch settings.musicSpectrumBarStyle {
                case .four: settings.fourBarSpectrumSensitivity = value
                case .five: settings.fiveBarSpectrumSensitivity = value
                case .seven: settings.sevenBarSpectrumSensitivity = value
                }
            }
        )
    }

    private var spectrumAttackTime: Binding<Double> {
        Binding(
            get: {
                switch settings.musicSpectrumBarStyle {
                case .four: settings.fourBarSpectrumAttackTime
                case .five: settings.fiveBarSpectrumAttackTime
                case .seven: settings.sevenBarSpectrumAttackTime
                }
            },
            set: { value in
                switch settings.musicSpectrumBarStyle {
                case .four: settings.fourBarSpectrumAttackTime = value
                case .five: settings.fiveBarSpectrumAttackTime = value
                case .seven: settings.sevenBarSpectrumAttackTime = value
                }
            }
        )
    }

    private var spectrumReleaseTime: Binding<Double> {
        Binding(
            get: {
                switch settings.musicSpectrumBarStyle {
                case .four: settings.fourBarSpectrumReleaseTime
                case .five: settings.fiveBarSpectrumReleaseTime
                case .seven: settings.sevenBarSpectrumReleaseTime
                }
            },
            set: { value in
                switch settings.musicSpectrumBarStyle {
                case .four: settings.fourBarSpectrumReleaseTime = value
                case .five: settings.fiveBarSpectrumReleaseTime = value
                case .seven: settings.sevenBarSpectrumReleaseTime = value
                }
            }
        )
    }

    private var spectrumRhythmDetail: Binding<Double> {
        Binding(
            get: { settings.musicSpectrumRhythmDetail },
            set: { settings.musicSpectrumRhythmDetail = $0 }
        )
    }

    private var spectrumUpdateRate: Binding<MusicSpectrumUpdateRate> {
        Binding(
            get: { settings.musicSpectrumUpdateRate },
            set: { settings.musicSpectrumUpdateRate = $0 }
        )
    }

    private var spectrumBarWidthScale: Binding<Double> {
        Binding(
            get: { settings.musicSpectrumBarWidthScale },
            set: { settings.musicSpectrumBarWidthScale = $0 }
        )
    }

    private var spectrumBarSpacingScale: Binding<Double> {
        Binding(
            get: { settings.musicSpectrumBarSpacingScale },
            set: { settings.musicSpectrumBarSpacingScale = $0 }
        )
    }

    private var spectrumBarCornerRadiusScale: Binding<Double> {
        Binding(
            get: { settings.musicSpectrumCornerRadiusScale },
            set: { settings.musicSpectrumCornerRadiusScale = $0 }
        )
    }

    private var rotatingArtworkCornerRadiusText: String {
        "\(Int(settings.compactRotatingArtworkCornerRadiusPercentage.rounded()))%"
    }

    private var staticArtworkCornerRadiusText: String {
        "\(Int(settings.compactStaticArtworkCornerRadiusPercentage.rounded()))%"
    }

    private var header: some View {
        Color.clear
            .frame(height: SettingsHeaderLayout.placeholderHeight)
            .overlay(alignment: .topTrailing) {
                SettingsResetButton(isDisabled: settings.usesDefaultVisualPreferences) {
                    settings.resetToDefault()
                }
                .offset(y: SettingsHeaderLayout.resetButtonOffset)
            }
    }

    var body: some View {
        Group {
            if isEmbedded {
                cards
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header

                        cards
                    }
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
                .settingsDetailScrolling()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: SettingsHeaderLayout.cardSpacing) {
            SettingsCard {
                realtimeMusicCard
            }

            mediaPreviewCard

            coverSettingsCard

            SettingsCard {
                spectrumCard
            }

            SettingsCard {
                spectrumAppearanceControls
            }
        }
    }

    private var realtimeMusicCard: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("settings.media.realtimeMusic")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                statusBadge
            }

            Spacer(minLength: 8)

            Toggle("settings.media.showRealtimeMusic", isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(SettingsCompactSwitchToggleStyle())
                .frame(width: 44, height: 44)
                .accessibilityHint("settings.media.showRealtimeMusic.description")
        }
        .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)

    }

    @ViewBuilder
    private var mediaPreviewCard: some View {
        if let appearanceSettings, let registry {
            SettingsCard {
                HStack(alignment: .top, spacing: 0) {
                    Text("settings.media.mediaDynamic")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    MediaLivingIslandPreview(
                        wallpaperImage: wallpaperImage,
                        registry: registry
                    )
                    .frame(
                        width: MediaPreviewLayout.previewSize.width,
                        height: MediaPreviewLayout.previewSize.height
                    )
                }
                .frame(height: MediaPreviewLayout.previewSize.height)
                .padding(.vertical, AppearanceCardLayout.contentInset)
            }
        }
    }

    private var coverSettingsCard: some View {
        SettingsCard {
            coverCustomizationControls
        }
    }

    private var spectrumCard: some View {
        VStack(spacing: 0) {
            spectrumCustomizationControls
        }
    }

    private var coverCustomizationControls: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text("settings.media.artworkRotation")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Toggle("settings.media.artworkRotation", isOn: isArtworkRotationEnabled)
                    .labelsHidden()
                    .toggleStyle(SettingsCompactSwitchToggleStyle())
                    .frame(width: 44, height: 44)
            }
            .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)

            AppearanceRowDivider()

            VStack(alignment: .leading, spacing: 0) {
                artworkCornerRadiusControl(
                    title: NSLocalizedString("settings.media.rotatingCornerRadius", comment: ""),
                    value: rotatingArtworkCornerRadiusPercentage,
                    valueText: rotatingArtworkCornerRadiusText,
                    isEnabled: settings.isCompactArtworkRotationEnabled
                )

                AppearanceRowDivider()


                artworkCornerRadiusControl(
                    title: NSLocalizedString("settings.media.staticCornerRadius", comment: ""),
                    value: staticArtworkCornerRadiusPercentage,
                    valueText: staticArtworkCornerRadiusText,
                    isEnabled: !settings.isCompactArtworkRotationEnabled
                )
            }
        }
    }

    private var spectrumAppearanceControls: some View {
        VStack(spacing: 0) {
            ModuleSettingRow(
                title: NSLocalizedString("settings.media.spectrumBarCount", comment: ""),
                description: nil
            ) {
                SettingsSegmentedControl(
                    selection: $settings.musicSpectrumBarStyle,
                    options: MusicSpectrumBarStyle.allCases,
                    title: { $0.title },
                    accessibilityTitle: NSLocalizedString("settings.media.spectrumBarCount", comment: "")
                )
            }

            AppearanceRowDivider()

            ModuleSettingRow(
                title: NSLocalizedString("settings.media.spectrumBarColor", comment: ""),
                description: settings.spectrumBarColorMode.description
            ) {
                SettingsSegmentedControl(
                    selection: $settings.spectrumBarColorMode,
                    options: SpectrumBarColorMode.allCases,
                    title: { $0.title },
                    accessibilityTitle: NSLocalizedString("settings.media.spectrumBarColor", comment: "")
                )
            }

            AppearanceRowDivider()

            SettingsDisclosureRow(title: NSLocalizedString("settings.common.moreSettings", comment: ""), isExpanded: $isSpectrumAppearanceExpanded)

            if isSpectrumAppearanceExpanded {
                AppearanceRowDivider()

                spectrumTuningRow(
                    title: NSLocalizedString("settings.media.spectrumBarWidth", comment: ""),
                    value: spectrumBarWidthScale,
                    range: MediaMonitoringSettings.spectrumBarWidthRange,
                    valueText: String(format: "%.1f pt", spectrumBarWidthScale.wrappedValue)
                )
                .transition(.opacity)

                AppearanceRowDivider()

                spectrumTuningRow(
                    title: NSLocalizedString("settings.media.spectrumBarSpacing", comment: ""),
                    value: spectrumBarSpacingScale,
                    range: MediaMonitoringSettings.spectrumBarSpacingRange,
                    valueText: String(format: "%.1f pt", spectrumBarSpacingScale.wrappedValue)
                )
                .transition(.opacity)

                AppearanceRowDivider()

                spectrumTuningRow(
                    title: NSLocalizedString("settings.media.spectrumBarCornerRadius", comment: ""),
                    value: spectrumBarCornerRadiusScale,
                    range: MediaMonitoringSettings.spectrumBarCornerRadiusRange,
                    valueText: "\(Int((spectrumBarCornerRadiusScale.wrappedValue * 100).rounded()))%"
                )
                .transition(.opacity)
            }
        }
    }

    private var spectrumCustomizationControls: some View {
        VStack(spacing: 0) {
            ModuleSettingRow(
                title: NSLocalizedString("settings.media.frameRate", comment: ""),
                description: NSLocalizedString("settings.media.frameRate.description", comment: "")
            ) {
                SettingsSegmentedControl(
                    selection: spectrumUpdateRate,
                    options: MusicSpectrumUpdateRate.allCases,
                    title: { $0 == .standard ? NSLocalizedString("settings.media.frameRateStandard", comment: "") : NSLocalizedString("settings.media.frameRateSmooth", comment: "") },
                    accessibilityTitle: NSLocalizedString("settings.media.frameRate", comment: "")
                )
                .help(NSLocalizedString("settings.media.frameRate.help", comment: ""))
            }

            AppearanceRowDivider()

            SettingsDisclosureRow(title: NSLocalizedString("settings.common.moreSettings", comment: ""), isExpanded: $isSpectrumTuningExpanded)

            if isSpectrumTuningExpanded {
                AppearanceRowDivider()

                spectrumTuningRow(
                    title: NSLocalizedString("settings.media.rhythmAmplitude", comment: ""),
                    value: spectrumSensitivity,
                    description: NSLocalizedString("settings.media.rhythmAmplitude.description", comment: "")
                )
                .transition(.opacity)

                AppearanceRowDivider()

                spectrumTuningRow(
                    title: NSLocalizedString("settings.media.attackSpeed", comment: ""),
                    value: spectrumAttackTime,
                    range: MediaMonitoringSettings.spectrumAttackReleaseRange,
                    description: NSLocalizedString("settings.media.attackSpeed.description", comment: "")
                )
                .transition(.opacity)

                AppearanceRowDivider()

                spectrumTuningRow(
                    title: NSLocalizedString("settings.media.releaseSpeed", comment: ""),
                    value: spectrumReleaseTime,
                    range: MediaMonitoringSettings.spectrumAttackReleaseRange,
                    description: NSLocalizedString("settings.media.releaseSpeed.description", comment: "")
                )
                .transition(.opacity)

                AppearanceRowDivider()

                spectrumTuningRow(
                    title: NSLocalizedString("settings.media.detailResponse", comment: ""),
                    value: spectrumRhythmDetail,
                    description: NSLocalizedString("settings.media.detailResponse.description", comment: "")
                )
                .transition(.opacity)
            }
        }
    }

    private func spectrumTuningRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double> = MediaMonitoringSettings.musicSpectrumTuningRange,
        description: String? = nil,
        valueText: String? = nil
    ) -> some View {
        let displayValue = valueText ?? "\(Int((value.wrappedValue * 100).rounded()))%"
        let sliderWidth = AppearanceRowLayout.valueSliderWidth
        return ModuleSettingRow(
            title: title,
            description: description,
            controlWidth: sliderWidth
        ) {
            LabeledValueSlider(
                value: value,
                range: range,
                width: sliderWidth,
                valueText: displayValue,
                sliderLabel: title,
                sliderHint: description ?? "",
                helpText: description ?? title
            )
        }
    }

    private func artworkCornerRadiusControl(
        title: String,
        value: Binding<Double>,
        valueText: String,
        isEnabled: Bool
    ) -> some View {
        ModuleSettingRow(
            title: title,
            description: nil,
            controlWidth: AppearanceRowLayout.valueSliderWidth
        ) {
            LabeledValueSlider(
                value: value,
                range: MediaMonitoringSettings.compactArtworkCornerRadiusPercentageRange,
                width: AppearanceRowLayout.valueSliderWidth,
                valueText: valueText,
                sliderLabel: String(format: NSLocalizedString("settings.media.artworkCornerRadiusFormat", comment: ""), title)
            )
            .disabled(!isEnabled)
        }
        .opacity(isEnabled ? 1 : 0.42)
    }

    private var statusBadge: some View {
        Text(settings.isRealtimeMusicMonitoringEnabled ? NSLocalizedString("settings.common.enabled", comment: "") : NSLocalizedString("settings.common.closed", comment: ""))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(settings.isRealtimeMusicMonitoringEnabled ? Color.accentColor : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(settings.isRealtimeMusicMonitoringEnabled ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.10))
            }
            .animation(.easeOut(duration: 0.16), value: settings.isRealtimeMusicMonitoringEnabled)
    }

}
