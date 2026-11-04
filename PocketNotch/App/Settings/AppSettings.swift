import AppKit
import Combine
import Foundation
import SwiftUI
import ServiceManagement
import PocketNotchShared

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .simplifiedChinese: "language.chinese"
        case .english: "language.english"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }
}

/// 设置面板的界面主题。
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .system: "theme.system"
        case .dark: "theme.dark"
        case .light: "theme.light"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .dark: "moon.fill"
        case .light: "sun.max.fill"
        }
    }

    /// 与「跟随系统」相对：是否强制固定为某个深浅外观。
    var isForced: Bool { self != .system }
}

@MainActor
final class AppThemeSettings: ObservableObject {
    private enum Keys {
        static let selectedTheme = "general.selectedTheme"
    }

    @Published var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Keys.selectedTheme)
        }
    }

    /// 系统当前实际深浅。跟随系统模式下由它决定最终效果，并随系统主题切换实时更新。
    @Published private(set) var systemColorScheme: ColorScheme

    private let defaults: UserDefaults
    private var systemAppearanceCancellable: AnyCancellable?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedValue = defaults.string(forKey: Keys.selectedTheme)
        if let storedValue, let storedTheme = AppTheme(rawValue: storedValue) {
            theme = storedTheme
        } else {
            theme = .system
        }
        systemColorScheme = Self.currentSystemColorScheme()
        systemAppearanceCancellable = DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .sink { [weak self] _ in
                self?.refreshSystemColorScheme()
            }
    }

    /// 重新读取系统深浅并发布变更（跟随系统模式下，切主题或系统换肤时调用）。
    func refreshSystemColorScheme() {
        systemColorScheme = Self.currentSystemColorScheme()
    }

    /// 恢复为跟随系统。
    func resetToDefault() {
        theme = .system
    }

    /// 设置窗口最终采用的深浅：强制主题用自身值，跟随系统用系统当前深浅。永远返回具体值。
    var resolvedColorScheme: ColorScheme {
        switch theme {
        case .dark: .dark
        case .light: .light
        case .system: systemColorScheme
        }
    }

    /// 读取系统全局的 AppleInterfaceStyle 获取真实深浅。
    /// 不要用 NSApp.effectiveAppearance——它会被本应用窗口已强制的外观污染。
    private static func currentSystemColorScheme() -> ColorScheme {
        if let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle"),
           !style.isEmpty {
            return style == "Dark" ? .dark : .light
        }
        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .dark
            : .light
    }
}

@MainActor
final class AppLanguageSettings: ObservableObject {
    private enum Keys {
        static let selectedLanguage = "general.selectedLanguage"
    }

    @Published var selectedLanguage: AppLanguage {
        didSet {
            defaults.set(selectedLanguage.rawValue, forKey: Keys.selectedLanguage)
            L10n.currentLanguage = selectedLanguage.rawValue
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedValue = defaults.string(forKey: Keys.selectedLanguage)
        if let storedValue, let storedLanguage = AppLanguage(rawValue: storedValue) {
            selectedLanguage = storedLanguage
        } else {
            let preferredLanguage = Locale.preferredLanguages.first ?? "en"
            selectedLanguage = preferredLanguage.hasPrefix("zh") ? .simplifiedChinese : .english
        }
        L10n.currentLanguage = selectedLanguage.rawValue
    }

    var locale: Locale {
        selectedLanguage.locale
    }

    func localizedString(_ key: String) -> String {
        guard let path = Bundle.main.path(
            forResource: selectedLanguage.rawValue,
            ofType: "lproj"
        ), let bundle = Bundle(path: path) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// 恢复为按系统偏好语言自动选择。
    func resetToDefault() {
        let preferredLanguage = Locale.preferredLanguages.first ?? "en"
        selectedLanguage = preferredLanguage.hasPrefix("zh") ? .simplifiedChinese : .english
    }
}

@MainActor
final class MenuBarSettings: ObservableObject {
    private enum Keys {
        static let showInMenuBar = "general.showInMenuBar"
    }

    @Published var showInMenuBar: Bool {
        didSet {
            defaults.set(showInMenuBar, forKey: Keys.showInMenuBar)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 默认显示在菜单栏
        if defaults.object(forKey: Keys.showInMenuBar) != nil {
            showInMenuBar = defaults.bool(forKey: Keys.showInMenuBar)
        } else {
            showInMenuBar = true
        }
    }

    func resetToDefault() {
        showInMenuBar = true
    }
}

@MainActor
final class LaunchAtLoginSettings: ObservableObject {
    private enum Keys {
        static let launchAtLogin = "general.launchAtLogin"
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyRegistration()
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Keys.launchAtLogin) != nil {
            launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        } else {
            launchAtLogin = false
        }
        applyRegistration()
    }

    func resetToDefault() {
        launchAtLogin = false
    }

    private func applyRegistration() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 注册/注销失败时静默忽略，不影响用户体验
        }
    }
}
struct LocaleInjector<Content: View>: View {
    @ObservedObject var languageSettings: AppLanguageSettings
    @ViewBuilder var content: () -> Content

    var body: some View {
        content().environment(\.locale, languageSettings.locale)
    }
}
