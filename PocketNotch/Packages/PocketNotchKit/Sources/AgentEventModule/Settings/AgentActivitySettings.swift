import Combine
import Foundation

/// Agent 活动采集的用户偏好。默认关闭（功能需要用户到设置中心主动开启）。
@MainActor
public final class AgentActivitySettings: ObservableObject {
    private enum Keys {
        static let enabled = "agentActivity.enabled"
        static let petBindings = "agentActivity.petBindings"
    }

    @Published public var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
        }
    }

    public let port: UInt16

    @Published public private(set) var petBindings: [String: String] {
        didSet {
            defaults.set(petBindings, forKey: Keys.petBindings)
        }
    }

    private let defaults: UserDefaults

    public init(
        defaults: UserDefaults = .standard,
        port: UInt16 = AgentEventBridge.defaultPort
    ) {
        self.defaults = defaults
        self.port = port
        isEnabled = defaults.bool(forKey: Keys.enabled)
        petBindings = defaults.dictionary(forKey: Keys.petBindings) as? [String: String] ?? [:]
    }

    public func setPetBinding(_ petID: String?, for agentID: String) {
        if let petID {
            petBindings[agentID] = petID
        } else {
            petBindings.removeValue(forKey: agentID)
        }
    }

    public func resetToDefault() {
        isEnabled = false
        petBindings = [:]
    }

    public var usesDefaultValues: Bool {
        !isEnabled && petBindings.isEmpty
    }
}
