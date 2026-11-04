import Combine
import PocketNotchCore
import SwiftUI

private enum SimulatedMacVersion: String, CaseIterable, Identifiable {
    case system
    case macOS26
    case macOS15
    case macOS14
    case macOS13

    var id: Self { self }

    var title: String {
        switch self {
        case .system: NSLocalizedString("settings.systemVersion.followSystem", comment: "")
        case .macOS26: "macOS 26"
        case .macOS15: "macOS 15"
        case .macOS14: "macOS 14"
        case .macOS13: "macOS 13"
        }
    }

    var version: SystemVersionInfo? {
        switch self {
        case .system: nil
        case .macOS26: SystemVersionInfo(major: 26, minor: 0, patch: 0)
        case .macOS15: SystemVersionInfo(major: 15, minor: 0, patch: 0)
        case .macOS14: SystemVersionInfo(major: 14, minor: 0, patch: 0)
        case .macOS13: SystemVersionInfo(major: 13, minor: 0, patch: 0)
        }
    }

    init(override: SystemVersionInfo?) {
        guard let override else {
            self = .system
            return
        }
        switch override.major {
        case 26: self = .macOS26
        case 15: self = .macOS15
        case 14: self = .macOS14
        case 13: self = .macOS13
        default: self = .system
        }
    }
}

/// 版本模拟调试面板：切换模拟的 macOS 版本，控制 PocketNotch 中所有走
/// `SystemVersionService` 的版本判断（液态玻璃/仿液态、锁屏材质、系统音频录制等）。
/// 改回「跟随系统」即恢复真实版本。
struct SystemVersionSettingsView: View {
    @State private var selection: SimulatedMacVersion

    init() {
        _selection = State(initialValue: SimulatedMacVersion(override: SystemVersionService.shared.overriddenVersion))
    }

    private var usingDefaults: Bool {
        selection == .system
    }

    private var effectiveDisplay: String {
        let version = SystemVersionService.shared.currentVersion()
        let material = LiquidGlassSupport.isAvailable ? NSLocalizedString("settings.systemVersion.liquidGlassMode", comment: "") : NSLocalizedString("settings.systemVersion.frostedGlassMode", comment: "")
        return String(format: NSLocalizedString("settings.systemVersion.effectiveDisplayFormat", comment: ""), version.major, version.minor, version.patch, material)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                SettingsCard {
                    row(title: NSLocalizedString("settings.systemVersion.simulateVersion", comment: "")) {
                        SettingsMenuPicker(
                            selection: $selection,
                            options: SimulatedMacVersion.allCases,
                            optionTitle: { $0.title },
                            currentTitle: selection.title,
                            accessibilityLabel: NSLocalizedString("settings.systemVersion.simulateVersion", comment: "")
                        )
                    }

                    AppearanceRowDivider()

                    infoRow(
                        title: NSLocalizedString("settings.systemVersion.realVersion", comment: ""),
                        value: display(version: SystemVersionService.shared.realVersion)
                    )

                    AppearanceRowDivider()

                    infoRow(title: NSLocalizedString("settings.systemVersion.effectiveVersion", comment: ""), value: effectiveDisplay)
                }

                footnote
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .settingsDetailScrolling()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: selection) { _, newValue in
            SystemVersionService.shared.overriddenVersion = newValue.version
        }
    }

    private var header: some View {
        Color.clear
            .frame(height: SettingsHeaderLayout.placeholderHeight)
            .overlay(alignment: .topTrailing) {
                SettingsResetButton(isDisabled: usingDefaults) {
                    selection = .system
                    SystemVersionService.shared.overriddenVersion = nil
                }
                .offset(y: SettingsHeaderLayout.resetButtonOffset)
            }
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cpu")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text("settings.systemVersion.footnote")
                .settingsNoteStyle(fixedSize: false)
        }
        .padding(.horizontal, 2)
    }

    private func row<Control: View>(title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))

            Spacer(minLength: 24)

            control()
        }
        .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))

            Spacer(minLength: 24)

            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)
    }

    private func display(version: SystemVersionInfo) -> String {
        "macOS \(version.major).\(version.minor).\(version.patch)"
    }
}