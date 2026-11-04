import Combine
import Display
import Foundation
import os

/// 内置 Hook 上报脚本的定位与落盘工具。
enum AgentAppScript {
    static let currentVersion = 1

    static func bundledScriptURL() -> URL? {
        Bundle.module.url(forResource: "agent-events.sh", withExtension: nil)
    }

    /// 随 PocketNotch 软件版本同步内置脚本，并确保具备执行权限。
    @discardableResult
    static func installCurrentVersion(at target: URL) throws -> Bool {
        guard let source = bundledScriptURL() else {
            throw AgentHookManagerError.missingScriptResource
        }
        let fm = FileManager.default
        let dir = target.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let sourceData = try Data(contentsOf: source)
        let needsWrite = !fm.fileExists(atPath: target.path)
            || (try? Data(contentsOf: target)) != sourceData
        if needsWrite {
            try sourceData.write(to: target)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        }

        try syncDebugMarker(for: target)
        return needsWrite
    }

    static func installedVersion(at target: URL) -> Int? {
        guard let contents = try? String(contentsOf: target, encoding: .utf8) else { return nil }
        let prefix = "POCKETNOTCH_AGENT_SCRIPT_VERSION="
        guard let line = contents.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return Int(line.dropFirst(prefix.count))
    }

    /// Keeps CLI hook diagnostics aligned with the currently running build,
    /// without changing hook commands (and therefore Codex trust hashes).
    static func syncDebugMarker(for target: URL) throws {
        let fm = FileManager.default
        let debugMarker = target.appendingPathExtension("debug")
#if DEBUG
        if fm.fileExists(atPath: target.path), !fm.fileExists(atPath: debugMarker.path) {
            try Data().write(to: debugMarker)
        }
#else
        if fm.fileExists(atPath: debugMarker.path) {
            try fm.removeItem(at: debugMarker)
        }
#endif
    }
}

enum AgentHookManagerError: LocalizedError {
    case missingScriptResource
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingScriptResource: "找不到内置 Hook 脚本资源"
        case .installFailed(let message): message
        }
    }
}

/// 独立于 Controller 的事件计数对象（避免在 init 中捕获 self）。
@MainActor
public final class AgentEventCounter: ObservableObject {
    @Published public private(set) var count = 0

    func increment() {
        count += 1
    }
}

/// 把桥接事件计数抛回主线程。
private final class CounterSink: EventSink {
    private let counter: AgentEventCounter

    init(_ counter: AgentEventCounter) {
        self.counter = counter
    }

    func handle(_ event: AgentEvent) {
        Task { @MainActor [counter] in
            counter.increment()
        }
    }
}

/// Thread-safe snapshot used by the bridge to reject events from disabled Agents.
private final class AgentListenerSelection: @unchecked Sendable {
    private let lock = NSLock()
    private var enabledAgentIDs: Set<String> = []

    func replace(with statuses: [AgentHookStatus]) {
        let enabled = Set(statuses.compactMap { status in
            status.isInstalled && !status.needsAuthorization ? status.agent.rawValue : nil
        })
        lock.lock()
        enabledAgentIDs = enabled
        lock.unlock()
    }

    func setEnabled(_ enabled: Bool, for agent: AgentHookAgent) {
        lock.lock()
        if enabled {
            enabledAgentIDs.insert(agent.rawValue)
        } else {
            enabledAgentIDs.remove(agent.rawValue)
        }
        lock.unlock()
    }

    func contains(_ agent: AgentHookAgent) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabledAgentIDs.contains(agent.rawValue)
    }

    func accepts(_ event: AgentEvent) -> Bool {
        let agentID = AgentAdapterFactory.canonicalID(event.agent)
        lock.lock()
        defer { lock.unlock() }
        return enabledAgentIDs.contains(agentID)
    }
}

/// Agent 事件采集的总控：负责全局监听与各 Agent 的启用状态。
@MainActor
public final class AgentActivityController: ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public private(set) var agentStatuses: [AgentHookStatus] = []
    @Published public private(set) var isBusy = false
    @Published public var notice: AgentNotice?

    public enum AgentNotice: Equatable {
        case running
        case stopped
        case agentEnabled(AgentHookAgent)
        case agentDisabled(AgentHookAgent)
        case agentAuthorizationRequired(AgentHookAgent)
        case error(String)

        public var isError: Bool {
            switch self {
            case .error:
                return true
            default:
                return false
            }
        }
    }

    public let settings: AgentActivitySettings
    public let petController: AgentPetController
    /// Hook 命令引用的上报脚本路径。
    public let scriptURL: URL
    public let eventCounter: AgentEventCounter
    let workingPresentationController: AgentWorkingPresentationController

    /// 当前是否有可见的 Agent 工作展示。
    /// 运行反馈（宠物/状态文字）在场时，常驻内容（媒体/股票/天气）应让位；
    /// 反馈过期消失后应立即释放，避免灵动岛被持续让位而留空。
    public var agentPresentationPublisher: AnyPublisher<Bool, Never> {
        workingPresentationController.$presentation
            .map { $0 != nil }
            .eraseToAnyPublisher()
    }

    private let bridge: AgentEventBridge
    private let codexSessionLogMonitor: CodexSessionLogMonitor
    private let installer: AgentHookInstaller
    private let codexAuthorizer: CodexHookAuthorizer
    private let listenerSelection: AgentListenerSelection
    private let trackingLogger = Logger(subsystem: "PocketNotch", category: "AgentActivityController")
    private var displayEventCancellable: AnyCancellable?
    private var displaySessionCancellable: AnyCancellable?
    private var statusRefreshTask: Task<Void, Never>?
    private var petPreparationTask: Task<Void, Never>?
    private var preparingDisplayEvent: Display.AgentEvent?
    private var sessionPetPreparationTasks: [String: Task<Void, Never>] = [:]
    private var pendingDisplayEvents: [Display.AgentEvent] = []
    private var latestDisplaySessions: [Display.AgentSession] = []
    private var preparedPetCacheKeys: Set<String> = []
    private var hookMigrationNeeded = false

    public init(
        settings: AgentActivitySettings,
        scriptURL: URL? = nil,
        extraSinks: [EventSink] = []
    ) {
        self.settings = settings
        self.petController = AgentPetController(settings: settings)
        let resolvedScript: URL
        if let scriptURL {
            resolvedScript = scriptURL
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            resolvedScript = dir
                .appendingPathComponent("PocketNotch", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("agent-events.sh")
        }
        self.scriptURL = resolvedScript

        let counter = AgentEventCounter()
        self.eventCounter = counter
        let workingPresentationController = AgentWorkingPresentationController()
        self.workingPresentationController = workingPresentationController
        self.installer = AgentHookInstaller(port: settings.port, scriptURL: resolvedScript)
        self.codexAuthorizer = CodexHookAuthorizer(scriptURL: resolvedScript)
        let listenerSelection = AgentListenerSelection()
        self.listenerSelection = listenerSelection

        var sinks = extraSinks
#if DEBUG
        // 控制台输出仅用于开发调试；发布包继续写入 JSONL 并更新计数，但不打印事件。
        sinks.append(ConsoleSink())
#endif
        sinks.append(JSONLFileSink(fileURL: AgentEventBridge.defaultPath))
        sinks.append(CounterSink(counter))
        let bridge = AgentEventBridge(
            port: settings.port,
            sinks: sinks,
            shouldAcceptEvent: { listenerSelection.accepts($0) }
        )
        self.bridge = bridge
        let codexSessionLogMonitor = CodexSessionLogMonitor { [weak bridge] payload in
            _ = try? bridge?.ingest(payload)
        }
        self.codexSessionLogMonitor = codexSessionLogMonitor
        bridge.setEventObserver { [weak codexSessionLogMonitor] event in
            codexSessionLogMonitor?.observe(event)
        }

        do {
            hookMigrationNeeded = try AgentAppScript.installCurrentVersion(at: resolvedScript)
        } catch {
            notice = .error("同步 Agent Hook 脚本失败：\(error.localizedDescription)")
        }
        if !hookMigrationNeeded {
            refreshStatus()
        }
    }

    // MARK: - Bridge control

    /// 由模块激活时调用：仅当用户在设置中开启后才启动监听。
    public func startIfEnabled() {
        guard settings.isEnabled else {
            isRunning = false
            return
        }
        start()
    }

    public func setEnabled(_ enabled: Bool) {
        settings.isEnabled = enabled
        enabled ? start() : stop()
    }

    private func start() {
        guard !isRunning else { return }
        Task {
            do {
                try AgentAppScript.installCurrentVersion(at: scriptURL)
                try await bridge.start()
                isRunning = bridge.isRunning
                syncCodexListener()
                notice = .running
            } catch {
                isRunning = false
                notice = .error("启动本地监听失败：\(error.localizedDescription)")
            }
        }
    }

    public func stop() {
        petPreparationTask?.cancel()
        petPreparationTask = nil
        preparingDisplayEvent = nil
        sessionPetPreparationTasks.values.forEach { $0.cancel() }
        sessionPetPreparationTasks.removeAll()
        pendingDisplayEvents.removeAll()
        latestDisplaySessions.removeAll()
        preparedPetCacheKeys.removeAll()
        codexSessionLogMonitor.stop()
        bridge.stop()
        workingPresentationController.clear()
        PetPreviewView.releaseCachedResources()
        isRunning = false
        notice = .stopped
    }

    public func bindDisplayEvents(_ publisher: AnyPublisher<Display.AgentEvent, Never>) {
        displayEventCancellable = publisher
            .sink { [weak self] event in
                self?.enqueueDisplayEvent(event)
            }
    }

    private func enqueueDisplayEvent(_ event: Display.AgentEvent) {
        if event.isStateOnly || isDismissalEvent(event) {
            if preparingDisplayEvent.map({ isSameSession($0, event) }) == true {
                petPreparationTask?.cancel()
                petPreparationTask = nil
                preparingDisplayEvent = nil
            }
            pendingDisplayEvents.removeAll { isSameSession($0, event) }
            workingPresentationController.receive(event)
            drainPendingDisplayEvents()
            return
        }

        guard petPreparationTask == nil else {
            pendingDisplayEvents.append(event)
            return
        }

        guard let pet = petController.selectedPet(for: event.agentId) else {
            workingPresentationController.receive(event)
            drainPendingDisplayEvents()
            return
        }

        if markPreparedIfCached(pet) {
            workingPresentationController.receive(event)
            drainPendingDisplayEvents()
            return
        }

        preparingDisplayEvent = event
        petPreparationTask = Task { @MainActor [weak self] in
            let loaded = await PetSpriteView.prepareForPresentation(pet: pet)
            guard !Task.isCancelled, let self else { return }
            self.petPreparationTask = nil
            self.preparingDisplayEvent = nil
            if loaded {
                self.preparedPetCacheKeys.insert(pet.assetCacheKey)
                self.applyLatestPreparedSessions()

                // The assignment may have changed while the old asset was loading.
                if self.petController.selectedPet(for: event.agentId)?.assetCacheKey == pet.assetCacheKey {
                    self.workingPresentationController.receive(event)
                } else {
                    self.pendingDisplayEvents.insert(event, at: 0)
                }
            }
            self.drainPendingDisplayEvents()
        }
    }

    private func drainPendingDisplayEvents() {
        guard petPreparationTask == nil, !pendingDisplayEvents.isEmpty else { return }
        let event = pendingDisplayEvents.removeFirst()
        enqueueDisplayEvent(event)
    }

    private func isDismissalEvent(_ event: Display.AgentEvent) -> Bool {
        switch event.type {
        case .sessionStopped, .sessionUnknown, .sessionStopRequested:
            return true
        default:
            return false
        }
    }

    private func isSameSession(_ lhs: Display.AgentEvent, _ rhs: Display.AgentEvent) -> Bool {
        AgentAdapterFactory.canonicalID(lhs.agentId) == AgentAdapterFactory.canonicalID(rhs.agentId)
            && lhs.sessionId == rhs.sessionId
    }

    public func bindDisplaySessions(_ sessionStore: Display.SessionStore) {
        displaySessionCancellable = sessionStore.$sessions
            .sink { [weak self] sessions in
                guard let self else { return }
                self.latestDisplaySessions = sessions
                self.applyLatestPreparedSessions()
                self.preparePetsNeededByRunningSessions(sessions)
                guard self.listenerSelection.contains(.codex) else { return }
                for session in sessions where session.agentId == "codex" && !session.state.isTerminal {
                    self.trackingLogger.info("track codex session=\(session.id, privacy: .public) state=\(session.state.rawValue, privacy: .public)")
                    self.codexSessionLogMonitor.track(sessionID: session.id)
                }
            }
    }

    private func applyLatestPreparedSessions() {
        let visibleSessions = latestDisplaySessions.filter { session in
            guard session.state == .running,
                  let pet = petController.selectedPet(for: session.agentId) else {
                return true
            }
            return markPreparedIfCached(pet)
        }
        workingPresentationController.updateSessions(visibleSessions)
    }

    private func preparePetsNeededByRunningSessions(_ sessions: [Display.AgentSession]) {
        let pets = sessions
            .filter { $0.state == .running }
            .compactMap { petController.selectedPet(for: $0.agentId) }

        for pet in pets where !markPreparedIfCached(pet) {
            let cacheKey = pet.assetCacheKey
            guard sessionPetPreparationTasks[cacheKey] == nil else { continue }
            sessionPetPreparationTasks[cacheKey] = Task { @MainActor [weak self] in
                let loaded = await PetSpriteView.prepareForPresentation(pet: pet)
                guard !Task.isCancelled, let self else { return }
                self.sessionPetPreparationTasks[cacheKey] = nil
                if loaded {
                    self.preparedPetCacheKeys.insert(cacheKey)
                    self.applyLatestPreparedSessions()
                }
            }
        }
    }

    private func markPreparedIfCached(_ pet: PetDescriptor) -> Bool {
        if preparedPetCacheKeys.contains(pet.assetCacheKey) {
            return true
        }
        guard PetSpriteView.isPreparedForPresentation(pet: pet) else { return false }
        preparedPetCacheKeys.insert(pet.assetCacheKey)
        return true
    }

    // MARK: - Hook management

    public func refreshStatus() {
        statusRefreshTask?.cancel()
        let installer = installer
        statusRefreshTask = Task { [weak self] in
            let statuses = await Task.detached(priority: .utility) {
                installer.detectStatuses()
            }.value
            guard !Task.isCancelled, let self else { return }
            apply(statuses)
            petController.refresh()
        }
    }

    /// 软件更新替换了内置脚本后，仅迁移此前已开启的 Agent Hook。
    /// Codex 配置会被更新，但若信任哈希失效，由设置页引导用户重新授权。
    public func synchronizeEnabledHooksAfterSoftwareUpdateIfNeeded() {
        guard hookMigrationNeeded else { return }
        guard !isBusy else { return }
        hookMigrationNeeded = false
        statusRefreshTask?.cancel()
        isBusy = true
        let installer = installer
        statusRefreshTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                let enabledAgents = AgentHookAgent.allCases.filter(installer.hasManagedHook)
                let failures = enabledAgents.compactMap { agent -> AgentHookResult? in
                    let result = installer.install(agent)
                    return result.success ? nil : result
                }
                return (
                    statuses: installer.detectStatuses(),
                    failures: failures
                )
            }.value
            guard let self else { return }
            if Task.isCancelled {
                hookMigrationNeeded = true
                isBusy = false
                return
            }
            apply(result.statuses)
            petController.refresh()
            isBusy = false

            if !result.failures.isEmpty {
                let detail = result.failures
                    .map { "\($0.agent.displayName)：\($0.message)" }
                    .joined(separator: "；")
                notice = .error("更新 Agent Hook 失败：\(detail)")
            } else if result.statuses.contains(where: { $0.agent == .codex && $0.needsAuthorization }) {
                notice = .agentAuthorizationRequired(.codex)
            }
        }
    }

    /// 首次引导清理全部 PocketNotch Hook，让用户从关闭状态重新选择要感知的 Agent。
    public func resetInstalledHooksForFirstLaunch() {
        guard !isBusy else { return }
        statusRefreshTask?.cancel()
        isBusy = true
        let installer = installer
        statusRefreshTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                let failures = AgentHookAgent.allCases.compactMap { agent -> AgentHookResult? in
                    let result = installer.uninstall(agent)
                    return result.success ? nil : result
                }
                return (statuses: installer.detectStatuses(), failures: failures)
            }.value
            guard !Task.isCancelled, let self else { return }
            apply(result.statuses)
            petController.refresh()
            isBusy = false
            if !result.failures.isEmpty {
                let detail = result.failures
                    .map { "\($0.agent.displayName)：\($0.message)" }
                    .joined(separator: "；")
                notice = .error("重置旧 Hook 失败：\(detail)")
            }
        }
    }

    public func setAgentEnabled(_ enabled: Bool, for agent: AgentHookAgent) {
        enabled ? enable(agent) : disable(agent)
    }

    private func enable(_ agent: AgentHookAgent) {
        guard !isBusy else { return }
        isBusy = true
        if agent == .codex {
            installAndAuthorizeCodex()
            return
        }
        let result: AgentHookResult
        do {
            try AgentAppScript.installCurrentVersion(at: scriptURL)
            result = installer.install(agent)
        } catch {
            result = AgentHookResult(agent: agent, success: false, message: error.localizedDescription)
        }
        refreshStatus()
        isBusy = false
        notice = result.success ? .agentEnabled(result.agent) : .error("开启失败：\(result.message)")
    }

    private func disable(_ agent: AgentHookAgent) {
        guard !isBusy else { return }
        isBusy = true
        listenerSelection.setEnabled(false, for: agent)
        if agent == .codex {
            codexSessionLogMonitor.stop()
        }
        let result = installer.uninstall(agent)
        refreshStatus()
        isBusy = false
        notice = result.success ? .agentDisabled(result.agent) : .error("关闭失败：\(result.message)")
    }

    private func installAndAuthorizeCodex() {
        notice = nil
        Task {
            do {
                try AgentAppScript.installCurrentVersion(at: scriptURL)
                let installResult = installer.install(.codex)
                guard installResult.success else {
                    throw AgentHookManagerError.installFailed(installResult.message)
                }
                try await codexAuthorizer.authorize()
                let statuses = await Task.detached(priority: .utility) { [installer] in
                    installer.detectStatuses()
                }.value
                apply(statuses)
                petController.refresh()
                guard statuses.first(where: { $0.agent == .codex })?.needsAuthorization == false else {
                    throw CodexHookAuthorizationError.invalidResponse("持久授权状态")
                }
                notice = .agentEnabled(.codex)
            } catch {
                // 安装和授权是一个事务：授权失败时撤销本次 Hook 注入。
                _ = installer.uninstall(.codex)
                refreshStatus()
                notice = .error("Codex 开启并授权失败：\(error.localizedDescription)")
            }
            isBusy = false
        }
    }

    private func apply(_ statuses: [AgentHookStatus]) {
        agentStatuses = statuses
        listenerSelection.replace(with: statuses)
        syncCodexListener()
    }

    private func syncCodexListener() {
        if isRunning && listenerSelection.contains(.codex) {
            codexSessionLogMonitor.start()
        } else {
            codexSessionLogMonitor.stop()
        }
    }

}
