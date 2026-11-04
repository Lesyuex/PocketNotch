import AppKit
import Combine
import Foundation
import PocketNotchCore
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var languageSettings: AppLanguageSettings
    @ObservedObject var themeSettings: AppThemeSettings
    @ObservedObject var menuBarSettings: MenuBarSettings
    @ObservedObject var launchAtLoginSettings: LaunchAtLoginSettings
    @Environment(\.haloSurface) private var surface

    private static let controlWidth: CGFloat = 132

    private var usesDefaults: Bool {
        languageSettings.selectedLanguage == automaticallyResolvedLanguage
            && themeSettings.theme == .system
            && menuBarSettings.showInMenuBar == true
            && launchAtLoginSettings.launchAtLogin == false
    }

    private var automaticallyResolvedLanguage: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                SettingsCard {
                    generalRow(titleKey: "general.language", controlWidth: Self.controlWidth) {
                        SettingsMenuPicker(
                            selection: $languageSettings.selectedLanguage,
                            options: AppLanguage.allCases,
                            optionTitle: { NSLocalizedString($0.titleKey, comment: "") },
                            currentTitle: NSLocalizedString(languageSettings.selectedLanguage.titleKey, comment: ""),
                            accessibilityLabel: NSLocalizedString("settings.general.language", comment: "")
                        )
                    }

                    AppearanceRowDivider()

                    generalRow(titleKey: "general.theme", controlWidth: Self.controlWidth) {
                        ThemeSegmentedControl(selection: $themeSettings.theme)
                    }

                    AppearanceRowDivider()

                    generalRow(titleKey: "general.showInMenuBar", controlWidth: Self.controlWidth) {
                        Toggle("", isOn: $menuBarSettings.showInMenuBar)
                            .labelsHidden()
                            .toggleStyle(SettingsCompactSwitchToggleStyle())
                            .frame(width: 44, height: 44)
                    }

                    AppearanceRowDivider()

                    generalRow(titleKey: "general.launchAtLogin", controlWidth: Self.controlWidth) {
                        Toggle("", isOn: $launchAtLoginSettings.launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(SettingsCompactSwitchToggleStyle())
                            .frame(width: 44, height: 44)
                    }
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
                SettingsResetButton(isDisabled: usesDefaults) {
                    languageSettings.resetToDefault()
                    themeSettings.resetToDefault()
                    menuBarSettings.resetToDefault()
                    launchAtLoginSettings.resetToDefault()
                }
                .offset(y: SettingsHeaderLayout.resetButtonOffset)
            }
    }

    private func generalRow<Control: View>(
        titleKey: String,
        controlWidth: CGFloat? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 16) {
            Text(LocalizedStringKey(titleKey))
                .font(.system(size: 12, weight: .semibold))

            Spacer(minLength: 24)

            control()
                .frame(width: controlWidth, alignment: .trailing)
        }
        .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)
    }
}

/// 外观主题文字分段选择控件（自动/深色/浅色）。
struct ThemeSegmentedControl: View {
    @Binding var selection: AppTheme

    static let controlWidth: CGFloat = 188

    var body: some View {
        SettingsSegmentedControl(
            selection: $selection,
            options: AppTheme.allCases,
            title: { theme in
                switch theme {
                case .system: NSLocalizedString("settings.general.themeAutomatic", comment: "")
                case .dark: NSLocalizedString("settings.general.themeDark", comment: "")
                case .light: NSLocalizedString("settings.general.themeLight", comment: "")
                }
            },
            accessibilityTitle: NSLocalizedString("settings.general.theme", comment: "")
        )
    }
}

@MainActor
private final class SymbolCatalogModel: ObservableObject {
    @Published var searchText = ""
    @Published private(set) var copiedSymbolName: String?
    @Published private(set) var symbolEffectPreset: [String: HaloSymbolEffectPreset] = [:]
    let symbols: [String]

    init() {
        symbols = Self.loadSymbols()
    }

    var filteredSymbols: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return symbols }
        return symbols.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    func copy(_ symbolName: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(symbolName, forType: .string)
        copiedSymbolName = symbolName
    }

    func effectPreset(for symbolName: String) -> HaloSymbolEffectPreset? {
        symbolEffectPreset[symbolName]
    }

    func setEffectPreset(_ preset: HaloSymbolEffectPreset?, for symbolName: String) {
        if let preset {
            symbolEffectPreset[symbolName] = preset
        } else {
            symbolEffectPreset.removeValue(forKey: symbolName)
        }
    }

    private static func loadSymbols() -> [String] {
        let path = "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphs.bundle/Contents/Resources/symbol_order.plist"
        guard
            let data = FileManager.default.contents(atPath: path),
            let symbols = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String]
        else {
            return fallbackSymbols
        }
        let filtered = symbols.filter {
            !isLocalizedSymbolVariant($0) && !isNumericSymbolVariant($0)
        }
        return Array(NSOrderedSet(array: filtered)) as? [String] ?? fallbackSymbols
    }

    private static func isLocalizedSymbolVariant(_ symbolName: String) -> Bool {
        let localizedSuffixes: Set<String> = [
            "ar", "he", "hi", "ja", "ko", "th"
        ]
        let localizedDoubleSuffixes: Set<String> = [
            "zh.cn", "zh.hk", "zh.tw"
        ]

        let parts = symbolName.split(separator: ".").map(String.init)
        guard !parts.isEmpty else { return false }

        if let last = parts.last, localizedSuffixes.contains(last) {
            return true
        }

        if parts.count >= 2 {
            let trailingPair = parts.suffix(2).joined(separator: ".")
            if localizedDoubleSuffixes.contains(trailingPair) {
                return true
            }
        }

        return false
    }

    private static func isNumericSymbolVariant(_ symbolName: String) -> Bool {
        guard let first = symbolName.split(separator: ".").first else { return false }
        return !first.isEmpty && first.allSatisfy(\.isNumber)
    }

    private static let fallbackSymbols: [String] = [
        "house.fill",
        "tray.full.fill",
        "cpu",
        "chart.line.uptrend.xyaxis",
        "cloud.sun",
        "music.note",
        "sparkles",
        "bell.badge",
        "rectangle.3.group",
        "lock.display",
        "gearshape",
    ]
}

struct SymbolCatalogSettingsView: View {
    @StateObject private var model = SymbolCatalogModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.haloSurface) private var surface

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Color.clear
                    .frame(height: 24)
                searchField
                symbolGridCard
                footnote
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .settingsDetailScrolling()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("settings.general.searchSymbolName", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.callout)

            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("settings.general.clearSearch")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(surface.searchBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(surface.cardBorder)
        }
    }

    private var symbolGridCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                Text(String(format: NSLocalizedString("settings.general.symbolCountFormat", comment: ""), model.filteredSymbols.count))
                    .font(.system(size: 12, weight: .semibold))

                if let copied = model.copiedSymbolName {
                    Label {
                        Text(String(format: NSLocalizedString("settings.general.copiedFormat", comment: ""), copied))
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                        .font(.caption)
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(model.filteredSymbols, id: \.self) { symbolName in
                    Button {
                        model.copy(symbolName)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            symbolPreview(for: symbolName)
                                .frame(width: 36, height: 36)

                            Text(symbolName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(surface.labelPrimary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(surface.searchBackground)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    model.copiedSymbolName == symbolName
                                        ? Color.accentColor.opacity(0.55)
                                        : surface.cardBorder
                                )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("settings.general.default") {
                            model.setEffectPreset(nil, for: symbolName)
                        }

                        Divider()

                        ForEach(HaloSymbolEffectPreset.allCases) { preset in
                            Button(preset.title) {
                                model.setEffectPreset(preset, for: symbolName)
                            }
                        }
                    }
                }
            }

            if model.filteredSymbols.isEmpty {
                Text("settings.general.noMatchingSymbol")
                    .settingsNoteStyle(fixedSize: false)
            }
        }
        }
    }

    @ViewBuilder
    private func symbolPreview(for symbolName: String) -> some View {
        let preset = model.effectPreset(for: symbolName)
        if let preset {
            Image(systemName: symbolName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(surface.labelPrimary)
                .haloSymbolEffect(preset, isActive: true, reduceMotion: reduceMotion)
        } else {
            Image(systemName: symbolName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(surface.labelPrimary)
        }
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.on.doc")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text("settings.general.symbolFootnote")
                .settingsNoteStyle(fixedSize: false)
        }
        .padding(.horizontal, 2)
    }
}
