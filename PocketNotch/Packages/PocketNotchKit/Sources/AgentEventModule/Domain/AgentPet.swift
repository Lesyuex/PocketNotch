import Foundation

public enum AgentIdentity: String, CaseIterable, Identifiable, Sendable, Hashable {
    case claude
    case codex
    case gemini

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini"
        }
    }
}

public enum PetAnimationState: String, CaseIterable, Sendable, Equatable, Hashable {
    case idle
    case runningRight = "running-right"
    case runningLeft = "running-left"
    case waving
    case jumping
    case failed
    case waiting
    case running
    case review

    public var displayName: String {
        switch self {
        case .idle: "空闲"
        case .runningRight: "向右移动"
        case .runningLeft: "向左移动"
        case .waving: "会话开始"
        case .jumping: "任务完成"
        case .failed: "任务失败"
        case .waiting: "等待确认"
        case .running: "正在运行"
        case .review: "正在审查"
        }
    }

    var row: Int {
        switch self {
        case .idle: 0
        case .runningRight: 1
        case .runningLeft: 2
        case .waving: 3
        case .jumping: 4
        case .failed: 5
        case .waiting: 6
        case .running: 7
        case .review: 8
        }
    }

    var frameDurations: [TimeInterval] {
        switch self {
        case .idle: [0.28, 0.11, 0.11, 0.14, 0.14, 0.32]
        case .runningRight, .runningLeft:
            [0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.22]
        case .waving: [0.14, 0.14, 0.14, 0.28]
        case .jumping: [0.14, 0.14, 0.14, 0.14, 0.28]
        case .failed: [0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.24]
        case .waiting: [0.15, 0.15, 0.15, 0.15, 0.15, 0.26]
        case .running: [0.12, 0.12, 0.12, 0.12, 0.12, 0.22]
        case .review: [0.15, 0.15, 0.15, 0.15, 0.15, 0.28]
        }
    }
}

public struct PetManifest: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String?
    public let spritesheetPath: String?
    public let stateAnimationPaths: [String: String]?

    public init(
        id: String,
        displayName: String,
        description: String?,
        spritesheetPath: String? = nil,
        stateAnimationPaths: [String: String]? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.spritesheetPath = spritesheetPath
        self.stateAnimationPaths = stateAnimationPaths
    }
}

public enum PetSource: String, Sendable, Equatable, Hashable {
    case bundled
    case pocketnotchLibrary
    case claudeExternal
    case codexExternal
    case geminiExternal

    public var agent: AgentIdentity? {
        switch self {
        case .claudeExternal: .claude
        case .codexExternal: .codex
        case .geminiExternal: .gemini
        case .bundled, .pocketnotchLibrary: nil
        }
    }

    public var isAgentExternal: Bool { agent != nil }
}

public struct PetDescriptor: Identifiable, Sendable, Equatable {
    public let id: String
    public let manifest: PetManifest
    public let packageURL: URL
    public let spritesheetURL: URL?
    public let stateAnimationURLs: [PetAnimationState: URL]
    public let source: PetSource
    public let sources: Set<PetSource>
    public let defaultAgentIDs: Set<AgentIdentity>

    public var assetCacheKey: String {
        if let spritesheetURL {
            return spritesheetURL.path
        }
        return PetAnimationState.allCases.compactMap { state in
            stateAnimationURLs[state].map { "\(state.rawValue)=\($0.path)" }
        }.joined(separator: "|")
    }

    public var isRemovable: Bool { source == .pocketnotchLibrary }

    public var sourceLabel: String {
        sources.sorted { sourceOrder($0) < sourceOrder($1) }
            .map(sourceLabel(for:))
            .joined(separator: " · ")
    }

    private func sourceLabel(for source: PetSource) -> String {
        switch source {
        case .bundled: "Pocket Notch内置"
        case .pocketnotchLibrary:
            manifest.id.lowercased().hasPrefix("custom-") ? "自定义" : "Pet导入"
        case .claudeExternal: "Claude内置"
        case .codexExternal: "Codex内置"
        case .geminiExternal: "Gemini内置"
        }
    }

    private func sourceOrder(_ source: PetSource) -> Int {
        switch source {
        case .bundled: 0
        case .claudeExternal: 1
        case .codexExternal: 2
        case .geminiExternal: 3
        case .pocketnotchLibrary: 4
        }
    }
}
