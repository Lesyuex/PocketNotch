import Combine
import Display
import Foundation
import os

struct AgentWorkingPresentation: Equatable, Identifiable {
    let id: UUID
    let agentID: String
    let sessionID: String
    let petState: PetAnimationState
    /// 是否为「文字版」通知（创建会话前 3 秒展示提示词与状态文字）。
    /// 其他状态为「图标版」，此值恒为 false。
    let isFullDetail: Bool
    /// 用户发送的提示词（创建会话事件的 message）；为空时左耳回退显示 agent 名。
    let prompt: String?
    /// 瞬时反馈的结束时间；活动会话驱动的运行展示没有固定结束时间。
    let expiresAt: Date?

    var agentDisplayName: String {
        AgentIdentity(rawValue: agentID)?.displayName ?? agentID.capitalized
    }

    var statusText: String {
        switch petState {
        case .waving: "已启动"
        case .jumping: "已完成"
        case .failed: "失败"
        case .waiting: "等待确认"
        case .review: "思考中"
        case .idle, .running, .runningLeft, .runningRight: "正在执行"
        }
    }
}

@MainActor
final class AgentWorkingPresentationController: ObservableObject {
    @Published private(set) var presentation: AgentWorkingPresentation?

    private struct ActivityKey: Hashable {
        let agentID: String
        let sessionID: String
    }

    private struct Activity {
        let id: UUID
        let key: ActivityKey
        let receivedAt: Date
        let sequence: UInt64
        let initialState: PetAnimationState
        let transitionAt: Date?
        let transitionedState: PetAnimationState?
        let fullDetailUntil: Date
        /// 用户提示词（创建会话事件的 message）。
        let prompt: String?
        let expiresAt: Date?
        let requiresActiveSession: Bool
        let priority: Int

        func state(at date: Date) -> PetAnimationState {
            guard let transitionAt, let transitionedState, date >= transitionAt else {
                return initialState
            }
            return transitionedState
        }
    }

    private let waitingDuration: TimeInterval
    /// 首次通知完整信息（agent 名 + 状态文字）的停留时长。
    private let fullDetailDuration: TimeInterval
    /// 多 agent 同时运行时，普通运行态在组内轮播时每个 agent 的展示时长。
    private let rotationInterval: TimeInterval
    private let now: () -> Date
    /// 多 agent 轮播偏移：0 表示展示「最近活跃」的 agent（新事件立即顶上来），
    /// 每次轮播 tick 递增，在最高优先级组内向前偏移轮流展示。
    private var rotationOffset = 0
    private var activities: [ActivityKey: Activity] = [:]
    /// 以「非创建会话」事件开始的会话：这些会话永不展示创建会话文字版。
    private var nonCreationStartedKeys: Set<ActivityKey> = []
    /// 每个会话创建时记录的提示词（用户输入），供「已完成」等文字版回退显示。
    private var sessionPrompts: [ActivityKey: String] = [:]
    /// 创建会话文字版展示期间暂存的事件，等文字版结束后再按序处理。
    private var pendingEvents: [AgentEvent] = []
    private var boundaryTask: Task<Void, Never>?
    private var nextSequence: UInt64 = 0
    private var hasSessionSnapshot = false
    private var activeSessionKeys: Set<ActivityKey> = []
    private var recentDisplayEventIDs: [String] = []
    private var recentDisplayEventIDSet: Set<String> = []
    private let logger = Logger(subsystem: "PocketNotch", category: "AgentWorkingPresentationController")
    private static let recentDisplayEventLimit = 512

    init(
        waitingDuration: TimeInterval = 10 * 60,
        fullDetailDuration: TimeInterval = 3,
        rotationInterval: TimeInterval = 10,
        now: @escaping () -> Date = Date.init
    ) {
        self.waitingDuration = waitingDuration
        self.fullDetailDuration = fullDetailDuration
        self.rotationInterval = rotationInterval
        self.now = now
    }

    func receive(_ event: AgentEvent) {
        // 生命周期边界不产生工作通知：创建由 agentStart 表达，关闭仅用于历史状态收口。
        if event.type == .sessionStart || event.type == .sessionEnd { return }
        // 高优先级事件（失败/等待确认）即使文字版展示中也立即打断，不排队。
        // 创建会话事件（agentStart 短时间连发）也立即处理以便合并。
        if !isCreationEvent(event.type)
            && priority(of: event.type) <= 1
            && isTextPhaseActive(at: now()) {
            pendingEvents.append(event)
            return
        }
        process(event)
    }

    func receive(_ event: Display.AgentEvent) {
        guard rememberDisplayEvent(event.id) else { return }
        guard !event.isStateOnly else { return }

        switch event.type {
        case .sessionStopped, .sessionUnknown:
            dismissSession(agentID: event.agentId, sessionID: event.sessionId)
            return
        case .sessionStopRequested:
            dismissSession(agentID: event.agentId, sessionID: event.sessionId)
            return
        default:
            break
        }

        let rawEvent = AgentEvent(
            id: event.id,
            agent: event.agentId,
            sessionId: event.sessionId,
            type: eventType(from: event),
            message: event.message,
            timestamp: event.timestamp
        )
        receive(rawEvent)
    }

    private func rememberDisplayEvent(_ id: String) -> Bool {
        guard recentDisplayEventIDSet.insert(id).inserted else { return false }
        recentDisplayEventIDs.append(id)
        if recentDisplayEventIDs.count > Self.recentDisplayEventLimit {
            let removed = recentDisplayEventIDs.removeFirst()
            recentDisplayEventIDSet.remove(removed)
        }
        return true
    }

    /// 运行展示由 SessionStore 的真实状态驱动，而不是由某条事件启动固定倒计时。
    /// 只要 Agent 下仍有 `.running` 会话就持续展示；最后一个活动会话结束后立即撤下。
    func updateSessions(_ sessions: [Display.AgentSession]) {
        hasSessionSnapshot = true
        let runningSessions = sessions.filter { $0.state == .running }
        let runningSummary = runningSessions
            .map { "\(AgentAdapterFactory.canonicalID($0.agentId)):\($0.id)" }
            .joined(separator: ", ")
        logger.info("updateSessions running=[\(runningSummary, privacy: .public)]")
        activeSessionKeys = Set(runningSessions.map {
            ActivityKey(agentID: AgentAdapterFactory.canonicalID($0.agentId), sessionID: $0.id)
        })

        activities = activities.filter { _, activity in
            !activity.requiresActiveSession || activeSessionKeys.contains(activity.key)
        }

        let date = now()
        for session in runningSessions {
            let key = ActivityKey(
                agentID: AgentAdapterFactory.canonicalID(session.agentId),
                sessionID: session.id
            )
            guard activities[key] == nil else { continue }
            nextSequence &+= 1
            activities[key] = persistentRunningActivity(
                key: key,
                receivedAt: session.updatedAt,
                sequence: nextSequence
            )
            logger.info("RUN appeared agent=\(key.agentID, privacy: .public) session=\(key.sessionID, privacy: .public)")
            // 新出现的运行 agent：重置轮播偏移，立即顶上展示。
            rotationOffset = 0
        }
        refresh(at: date)
    }

    private func isCreationEvent(_ type: EventType) -> Bool {
        type == .agentStart
    }

    private func priority(of type: EventType) -> Int {
        switch type {
        case .waitingApproval: 3
        case .failed: 2
        default: 1
        }
    }

    /// 当前是否正处于创建会话文字版阶段（实时判断，不依赖已缓存的 presentation）。
    private func isTextPhaseActive(at date: Date) -> Bool {
        guard let selected = selectActivity(at: date) else { return false }
        return date < selected.fullDetailUntil
    }

    private func process(_ event: AgentEvent) {
        let receivedAt = now()
        nextSequence &+= 1
        let agentID = AgentAdapterFactory.canonicalID(event.agent)
        let key = ActivityKey(agentID: agentID, sessionID: event.sessionId)
        // 会话收到的首个事件若非创建会话，则标记该会话永不展示创建会话文字版。
        if !isCreationEvent(event.type) && !activities.keys.contains(key) {
            nonCreationStartedKeys.insert(key)
        }
        // 创建会话事件到达时，记录该会话的用户提示词。
        if isCreationEvent(event.type), let message = event.message, !message.isEmpty {
            sessionPrompts[key] = message
        }
        let activity = makeActivity(
            event: event,
            agentID: agentID,
            receivedAt: receivedAt,
            sequence: nextSequence
        )
        activities[activity.key] = activity
        // 新事件到达：重置轮播偏移，使该「最近活跃」的 agent 立即顶上展示。
        rotationOffset = 0
        refresh(at: receivedAt)
    }

    /// 文字版结束后，若队列中有暂存事件，取出第一条继续展示。
    private func drainPending() {
        let date = now()
        guard let selected = selectActivity(at: date),
              date >= selected.fullDetailUntil,
              !pendingEvents.isEmpty else {
            return
        }
        let event = pendingEvents.removeFirst()
        process(event)
    }

    func clear() {
        boundaryTask?.cancel()
        boundaryTask = nil
        rotationOffset = 0
        activities.removeAll()
        pendingEvents.removeAll()
        nonCreationStartedKeys.removeAll()
        sessionPrompts.removeAll()
        activeSessionKeys.removeAll()
        recentDisplayEventIDs.removeAll()
        recentDisplayEventIDSet.removeAll()
        hasSessionSnapshot = false
        presentation = nil
    }

    func dismiss(presentationID: UUID) {
        activities = activities.filter { $0.value.id != presentationID }
        refresh(at: now())
    }

    private func dismissSession(agentID: String, sessionID: String) {
        let key = ActivityKey(
            agentID: AgentAdapterFactory.canonicalID(agentID),
            sessionID: sessionID
        )
        activities.removeValue(forKey: key)
        pendingEvents.removeAll {
            AgentAdapterFactory.canonicalID($0.agent) == key.agentID && $0.sessionId == key.sessionID
        }
        refresh(at: now())
    }

    private func makeActivity(
        event: AgentEvent,
        agentID: String,
        receivedAt: Date,
        sequence: UInt64
    ) -> Activity {
        let key = ActivityKey(agentID: agentID, sessionID: event.sessionId)
        let id = UUID()
        switch event.type {
        case .sessionStart, .sessionEnd, .agentStart:
            // 该会话以非创建会话事件开始（如监听中途接入）：不展示创建会话文字版。
            if nonCreationStartedKeys.contains(key) {
                return simpleActivity(
                    id: id,
                    key: key,
                    receivedAt: receivedAt,
                    sequence: sequence,
                    state: .running,
                    duration: nil,
                    requiresActiveSession: true,
                    priority: 1
                )
            }
            // agentStart 短时间连发时合并为一次创建会话文字版：
            // 若同 key 已有文字版仍在展示（fullDetailUntil 未过期），复用其 id 与时长，
            // 仅更新 sequence，避免重复展示两次文字版。
            if let existing = activities[key],
               existing.fullDetailUntil > receivedAt {
                return Activity(
                    id: existing.id,
                    key: key,
                    receivedAt: existing.receivedAt,
                    sequence: sequence,
                    initialState: .waving,
                    transitionAt: existing.transitionAt,
                    transitionedState: .running,
                    fullDetailUntil: existing.fullDetailUntil,
                    prompt: existing.prompt ?? event.message,
                    expiresAt: existing.expiresAt,
                    requiresActiveSession: true,
                    priority: 1
                )
            }
            return Activity(
                id: id,
                key: key,
                receivedAt: receivedAt,
                sequence: sequence,
                initialState: .waving,
                // 「已启动」文字停留整个文字版阶段（fullDetailDuration），
                // 结束后再切为运行态。
                transitionAt: receivedAt.addingTimeInterval(fullDetailDuration),
                transitionedState: .running,
                fullDetailUntil: receivedAt.addingTimeInterval(fullDetailDuration),
                prompt: event.message,
                expiresAt: nil,
                requiresActiveSession: true,
                priority: 1
            )
        case .thinking:
            return simpleActivity(
                id: id,
                key: key,
                receivedAt: receivedAt,
                sequence: sequence,
                state: .review,
                duration: nil,
                requiresActiveSession: true,
                priority: 1
            )
        case .toolStart, .toolEnd, .commandStart, .commandEnd:
            return simpleActivity(
                id: id,
                key: key,
                receivedAt: receivedAt,
                sequence: sequence,
                state: .running,
                duration: nil,
                requiresActiveSession: true,
                priority: 1
            )
        case .waitingApproval:
            return simpleActivity(
                id: id,
                key: key,
                receivedAt: receivedAt,
                sequence: sequence,
                state: .waiting,
                duration: waitingDuration,
                priority: 3
            )
        case .completed:
            // 已完成使用文字版：整个展示期（4 秒）都显示「已完成」文字，不进入图标版。
            // 4 秒与 sessionCompleted 通知的展示时长同步，避免通知消失后
            // 灵动岛仍被工作展示占用，导致常驻内容（音乐/天气/股票）无法恢复。
            let completedDuration: TimeInterval = 4
            let completedExpiry = receivedAt.addingTimeInterval(completedDuration)
            return Activity(
                id: id,
                key: key,
                receivedAt: receivedAt,
                sequence: sequence,
                initialState: .jumping,
                transitionAt: nil,
                transitionedState: nil,
                fullDetailUntil: completedExpiry,
                prompt: sessionPrompts[key] ?? event.message,
                expiresAt: completedExpiry,
                requiresActiveSession: false,
                priority: 1
            )
        case .failed:
            return simpleActivity(
                id: id,
                key: key,
                receivedAt: receivedAt,
                sequence: sequence,
                state: .failed,
                duration: 4,
                requiresActiveSession: false,
                priority: 2
            )
        case .stopRequested:
            return simpleActivity(
                id: id,
                key: key,
                receivedAt: receivedAt,
                sequence: sequence,
                state: .idle,
                duration: 0.01,
                requiresActiveSession: false,
                priority: 0
            )
        }
    }

    private func simpleActivity(
        id: UUID,
        key: ActivityKey,
        receivedAt: Date,
        sequence: UInt64,
        state: PetAnimationState,
        duration: TimeInterval?,
        requiresActiveSession: Bool = false,
        priority: Int,
        prompt: String? = nil
    ) -> Activity {
        Activity(
            id: id,
            key: key,
            receivedAt: receivedAt,
            sequence: sequence,
            initialState: state,
            transitionAt: nil,
            transitionedState: nil,
            // 非创建会话的消息都是「图标版」，跳过文字版阶段。
            fullDetailUntil: receivedAt,
            prompt: prompt,
            expiresAt: duration.map { receivedAt.addingTimeInterval($0) },
            requiresActiveSession: requiresActiveSession,
            priority: priority
        )
    }

    private func persistentRunningActivity(
        key: ActivityKey,
        receivedAt: Date,
        sequence: UInt64
    ) -> Activity {
        simpleActivity(
            id: UUID(),
            key: key,
            receivedAt: receivedAt,
            sequence: sequence,
            state: .running,
            duration: nil,
            requiresActiveSession: true,
            priority: 1
        )
    }

    private func refresh(at date: Date) {
        boundaryTask?.cancel()
        activities = activities.filter { _, activity in
            let isAlive = !activity.requiresActiveSession
                || !hasSessionSnapshot
                || activeSessionKeys.contains(activity.key)
            let isUnexpired = activity.expiresAt.map { $0 > date } ?? true
            return isAlive && isUnexpired
        }

        let selected = selectActivity(at: date)
        let newPresentation = selected.map {
            AgentWorkingPresentation(
                id: $0.id,
                agentID: $0.key.agentID,
                sessionID: $0.key.sessionID,
                petState: $0.state(at: date),
                isFullDetail: date < $0.fullDetailUntil,
                prompt: $0.prompt,
                expiresAt: $0.expiresAt
            )
        }
        if newPresentation != presentation {
            if let p = newPresentation {
                logger.info("SHOW agent=\(p.agentID, privacy: .public) session=\(p.sessionID, privacy: .public) state=\(p.statusText, privacy: .public) fullDetail=\(p.isFullDetail) prompt=\(p.prompt ?? "", privacy: .public)")
            } else {
                logger.info("CLEAR presentation")
            }
        }
        presentation = newPresentation
        scheduleNextBoundary(after: date)
    }

    /// 单个 Agent 在轮播池中的一个单位：以「Agent」为单位，聚合其全部会话。
    private struct AgentUnit {
        let agentID: String
        /// 代表该 Agent 当前聚合状态的某条会话 activity（其 petState 反映待授权/运行中）。
        let representative: Activity
        /// Agent 级优先级：2 = 等待授权，1 = 运行中（思考/启动均视为运行中）。
        let priority: Int
        /// 代表会话的 sequence（用于池内「最近活跃在前」排序）。
        let sequence: UInt64
    }

    private func selectActivity(at date: Date) -> Activity? {
        let pool = agentPool(at: date)
        // 1) 等待授权（最高级持续态）：只要任一会话等待授权即整体展示，等待授权的 Agent 间轮播。
        let waitingGroup = pool.filter { $0.priority == 2 }
        if !waitingGroup.isEmpty {
            return waitingGroup[rotationOffset % waitingGroup.count].representative
        }
        // 2) 瞬时反馈（已完成/失败）：优先于运行中，弹出一次。
        if let terminal = topTerminal(at: date) {
            return terminal
        }
        // 3) 运行中（次高持续态）：非空闲的 Agent 之间轮播。
        let runningGroup = pool.filter { $0.priority == 1 }
        guard !runningGroup.isEmpty else { return nil }
        return runningGroup[rotationOffset % runningGroup.count].representative
    }

    /// 选取「瞬时反馈」（已完成/失败）中优先级最高、最近的一则；无则返回 nil。
    private func topTerminal(at date: Date) -> Activity? {
        activities.values
            .filter { !isActiveActivity($0, at: date) }
            .max {
                if $0.priority != $1.priority { return $0.priority < $1.priority }
                return $0.sequence < $1.sequence
            }
    }

    /// 是否「活动中」（持续态）。运行 / 待授权 / 思考 / 启动均属活动状态；
    /// 完成 / 失败 / 停止为终态或瞬时反馈，不参与持续态聚合与轮播。
    private func isActiveActivity(_ activity: Activity, at date: Date) -> Bool {
        switch activity.state(at: date) {
        case .running, .runningLeft, .runningRight, .waiting, .review, .waving:
            return true
        case .jumping, .failed, .idle:
            return false
        }
    }

    /// 把「会话级 activity」聚合为「Agent 级单位」（以 Agent 为单位，不含空闲 Agent）。
    /// 聚合规则：同一 Agent 下，只要任一会话是「等待授权」→ 整体为等待授权；
    /// 否则任一会话在「运行中/思考/启动」→ 整体为运行中。
    private func agentPool(at date: Date) -> [AgentUnit] {
        let active = activities.values.filter { isActiveActivity($0, at: date) }
        var byAgent: [String: AgentUnit] = [:]
        for activity in active {
            let agentID = activity.key.agentID
            let isWaiting = activity.state(at: date) == .waiting
            let unitPriority = isWaiting ? 2 : 1
            if let existing = byAgent[agentID] {
                // 已有该 Agent：只要新会话是等待授权（更高级），则整体升级为代表。
                if unitPriority > existing.priority {
                    byAgent[agentID] = AgentUnit(
                        agentID: agentID,
                        representative: activity,
                        priority: unitPriority,
                        sequence: activity.sequence
                    )
                }
            } else {
                byAgent[agentID] = AgentUnit(
                    agentID: agentID,
                    representative: activity,
                    priority: unitPriority,
                    sequence: activity.sequence
                )
            }
        }
        return byAgent.values.sorted { $0.sequence > $1.sequence }
    }

    private func scheduleNextBoundary(after date: Date) {
        let pool = agentPool(at: date)
        let boundaries = activities.values.flatMap { activity -> [Date] in
            var result: [Date] = []
            if let expiresAt = activity.expiresAt {
                result.append(expiresAt)
            }
            if let transitionAt = activity.transitionAt, transitionAt > date {
                result.append(transitionAt)
            }
            if activity.fullDetailUntil > date {
                result.append(activity.fullDetailUntil)
            }
            return result
        }

        // Agent 级轮播 tick：存在终态反馈（已完成/失败）时不轮播（由其自身时长驱动）；
        // 否则当 Agent 池最高优先级组内有多于一个 Agent 时，到 rotationInterval 后切换。
        let hasTerminal = activities.values.contains { !isActiveActivity($0, at: date) }
        let topPriority = pool.map(\.priority).max() ?? 1
        let topAgentCount = pool.filter { $0.priority == topPriority }.count
        let rotationBoundary = !hasTerminal && topAgentCount > 1
            ? date.addingTimeInterval(rotationInterval)
            : nil

        let realBoundary = boundaries.min()
        let nextBoundary: Date?
        let isRotationNext: Bool
        if let rotationBoundary {
            if let realBoundary, realBoundary <= rotationBoundary {
                // 真实边界（过期/过渡/文字版结束）先发生，优先处理它，不做轮播。
                nextBoundary = realBoundary
                isRotationNext = false
            } else {
                nextBoundary = rotationBoundary
                isRotationNext = true
            }
        } else {
            nextBoundary = realBoundary
            isRotationNext = false
        }

        guard let nextBoundary else { return }
        let delay = max(nextBoundary.timeIntervalSince(date), 0)
        boundaryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            if isRotationNext {
                self.rotationOffset &+= 1
            }
            let tickTime = self.now()
            self.refresh(at: tickTime)
            // 文字版播满后，处理暂存的后续消息。
            self.drainPending()
        }
    }

    private func eventType(from event: Display.AgentEvent) -> EventType {
        if let originType = event.originType, let type = EventType(rawName: originType) {
            switch event.type {
            case .sessionCompleted:
                return .completed
            case .sessionFailed:
                return .failed
            default:
                return type
            }
        }

        switch event.type {
        case .sessionCreated:
            return .sessionStart
        case .sessionRunning:
            return .toolStart
        case .sessionWaitingApproval:
            return .waitingApproval
        case .sessionCompleted:
            return .completed
        case .sessionFailed:
            return .failed
        case .sessionStopped, .sessionUnknown, .sessionStopRequested, .sessionEnded:
            return .sessionEnd
        }
    }
}
