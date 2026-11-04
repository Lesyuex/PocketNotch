import AppKit
import Combine
import Foundation
import PocketNotchShared

public enum NotchDisplayMode: String, CaseIterable, Sendable {
    case single
    case all
}

public struct NotchDisplayDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let isBuiltIn: Bool
    public let hasNotch: Bool

    public init(id: String, name: String, isBuiltIn: Bool, hasNotch: Bool) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.hasNotch = hasNotch
    }
}

@MainActor
public enum NotchDisplayCatalog {
    public static func connectedDisplays() -> [NotchDisplayDescriptor] {
        NSScreen.screens.map {
            NotchDisplayDescriptor(
                id: $0.pocketnotchDisplayIdentifier,
                name: $0.localizedName,
                isBuiltIn: $0.isBuiltInDisplay,
                hasNotch: $0.hasNotch
            )
        }
    }

    public static func recommendedDisplayIdentifier() -> String? {
        NotchPositioner().targetScreen()?.pocketnotchDisplayIdentifier
    }
}

/// 灵动刘海显示位置偏好。单屏模式未指定显示器时沿用系统推荐屏幕。
@MainActor
public final class NotchDisplaySettings: ObservableObject {
    private enum Keys {
        static let mode = "display.island.mode"
        static let selectedDisplayIdentifier = "display.island.selectedIdentifier"
    }

    @Published public private(set) var mode: NotchDisplayMode {
        didSet { defaults?.set(mode.rawValue, forKey: Keys.mode) }
    }

    @Published public private(set) var selectedDisplayIdentifier: String? {
        didSet {
            if let selectedDisplayIdentifier {
                defaults?.set(selectedDisplayIdentifier, forKey: Keys.selectedDisplayIdentifier)
            } else {
                defaults?.removeObject(forKey: Keys.selectedDisplayIdentifier)
            }
        }
    }

    private let defaults: UserDefaults?

    public init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        mode = defaults?.string(forKey: Keys.mode)
            .flatMap(NotchDisplayMode.init(rawValue:)) ?? .all
        selectedDisplayIdentifier = defaults?.string(forKey: Keys.selectedDisplayIdentifier)
    }

    public func showOnAllDisplays() {
        mode = .all
    }

    public func showOnDisplay(identifier: String) {
        selectedDisplayIdentifier = identifier
        mode = .single
    }

    public func resetToDefault() {
        selectedDisplayIdentifier = nil
        mode = .all
    }
}
