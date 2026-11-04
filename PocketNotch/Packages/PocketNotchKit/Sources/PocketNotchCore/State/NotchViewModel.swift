import Combine
import Foundation
import Observation

/// 岛的状态机，驱动窗口尺寸与 SwiftUI 动画。
@Observable
@MainActor
public final class NotchViewModel {
    public private(set) var state: NotchState? {
        didSet {
            let wasExpanded = oldValue == .expanded || oldValue == .dragging
            if wasExpanded != isExpanded {
                isExpandedSubject.send(isExpanded)
            }
        }
    }
    public let interactionSettings: NotchInteractionSettings
    public private(set) var isInteractionSuspended = false

    @ObservationIgnored private let isExpandedSubject: CurrentValueSubject<Bool, Never>
    @ObservationIgnored private let layoutChangeSubject = PassthroughSubject<Void, Never>()

    @ObservationIgnored private var displayViewModels: [String: NotchViewModel] = [:]
    @ObservationIgnored private var displayExpansionCancellables: [String: AnyCancellable] = [:]
    @ObservationIgnored private var managesDisplayViewModels = false
    @ObservationIgnored private var isAnyDisplayExpanded = false

    @ObservationIgnored private var hoverExpansionTask: Task<Void, Never>?
    @ObservationIgnored private var hoverCollapseTask: Task<Void, Never>?
    @ObservationIgnored private var isHovered = false
    @ObservationIgnored private var isHoverRevealEnabled = true
    @ObservationIgnored private var expandedContentInteractionCount = 0
    @ObservationIgnored private var expansionStartedAtUptime: TimeInterval?
    @ObservationIgnored private var hoverTriggerCancellable: AnyCancellable?

    /// 展开背板的 spring 动画会持续约 0.46 秒；动画期间窗口和 tracking area 都在扩缩，
    /// 必须等布局稳定后才能把 mouseExited 当成真实移出。
    private static let expansionHoverStabilizationDuration: TimeInterval = 0.6

    public init(interactionSettings: NotchInteractionSettings? = nil) {
        let interactionSettings = interactionSettings ?? NotchInteractionSettings(defaults: nil)
        let startsExpanded = !interactionSettings.startsHidden
        self.interactionSettings = interactionSettings
        state = startsExpanded ? .expanded : nil
        isExpandedSubject = CurrentValueSubject(startsExpanded)
        hoverTriggerCancellable = interactionSettings.$isHoverTriggerEnabled
            .sink { [weak self] isEnabled in
                self?.setHoverRevealEnabled(isEnabled)
            }
        setHoverRevealEnabled(interactionSettings.isHoverTriggerEnabled)
    }

    /// 兼容既有调用点：展开态和拖拽态都属于可见交互态。
    public var isVisible: Bool {
        if managesDisplayViewModels {
            return displayViewModels.values.contains(where: \.isVisible)
        }
        return state != nil
    }

    public var isExpanded: Bool {
        if managesDisplayViewModels {
            return isAnyDisplayExpanded
        }
        return state == .expanded || state == .dragging
    }

    public var isExpandedPublisher: AnyPublisher<Bool, Never> {
        isExpandedSubject.eraseToAnyPublisher()
    }

    public var layoutChangePublisher: AnyPublisher<Void, Never> {
        layoutChangeSubject.eraseToAnyPublisher()
    }

    /// 点击切换展开状态；展开页面仍是临时态，鼠标移出整个页面后会自动收起。
    public func click() {
        guard !isInteractionSuspended, interactionSettings.isClickEnabled else { return }
        cancelPendingHoverTransitions()
        isExpanded ? collapse() : expand()
    }

    /// 鼠标持续停留达到配置时长后展开；任意来源的展开态在移出页面后自动收起。
    public func hoverChanged(_ isHovered: Bool) {
        guard !isInteractionSuspended else { return }
        guard isHovered != self.isHovered else {
            // 展开可能由点击或文件拖拽触发，此时内部 hover 基线仍是 false。
            // 后续的 mouseExited 仍需安排收起，不能仅因值未变化而丢弃。
            if !isHovered, isExpanded, expandedContentInteractionCount == 0 {
                scheduleHoverCollapse()
            }
            return
        }
        self.isHovered = isHovered
        hoverExpansionTask?.cancel()
        hoverExpansionTask = nil
        hoverCollapseTask?.cancel()
        hoverCollapseTask = nil

        if isHovered {
            scheduleHoverExpansion()
        } else if isExpanded, expandedContentInteractionCount == 0 {
            scheduleHoverCollapse()
        }
    }

    /// Popover 等展开内容的临时子交互可持有 Island，避免指针进入子窗口时被误判为移出。
    public func beginExpandedContentInteraction() {
        if managesDisplayViewModels {
            for viewModel in displayViewModels.values where viewModel.isExpanded {
                viewModel.beginExpandedContentInteraction()
            }
            return
        }
        guard isExpanded else { return }
        expandedContentInteractionCount += 1
        hoverCollapseTask?.cancel()
        hoverCollapseTask = nil
    }

    public func endExpandedContentInteraction() {
        if managesDisplayViewModels {
            for viewModel in displayViewModels.values where viewModel.isExpanded {
                viewModel.endExpandedContentInteraction()
            }
            return
        }
        guard expandedContentInteractionCount > 0 else { return }
        expandedContentInteractionCount -= 1
        guard expandedContentInteractionCount == 0, !isHovered, isExpanded else { return }
        scheduleHoverCollapse()
    }

    func displayViewModel(for identifier: String) -> NotchViewModel {
        if let viewModel = displayViewModels[identifier] {
            return viewModel
        }

        managesDisplayViewModels = true
        let viewModel = NotchViewModel(interactionSettings: interactionSettings)
        displayViewModels[identifier] = viewModel
        displayExpansionCancellables[identifier] = viewModel.isExpandedPublisher
            .sink { [weak self] _ in
                self?.updateManagedDisplayExpansion()
            }
        updateManagedDisplayExpansion()
        return viewModel
    }

    func removeDisplayViewModel(for identifier: String) {
        displayExpansionCancellables.removeValue(forKey: identifier)
        displayViewModels.removeValue(forKey: identifier)
        updateManagedDisplayExpansion()
    }

    public func setHoverRevealEnabled(_ isEnabled: Bool) {
        guard isEnabled != isHoverRevealEnabled else { return }
        isHoverRevealEnabled = isEnabled
        hoverExpansionTask?.cancel()
        hoverExpansionTask = nil

        if isEnabled, !isInteractionSuspended, isHovered, !isExpanded {
            scheduleHoverExpansion()
        }
    }

    public func restartPendingHoverReveal() {
        guard !isInteractionSuspended,
              isHovered,
              !isExpanded,
              isHoverRevealEnabled else { return }
        hoverExpansionTask?.cancel()
        hoverExpansionTask = nil
        scheduleHoverExpansion()
    }

    /// 全屏抑制等系统场景把展开态收回到 compact。动画由 phaseController 驱动，
    /// 与用户移出触发的收起走同一条收起路径。
    public func collapseToIdle() {
        guard !isInteractionSuspended, isExpanded else { return }
        cancelPendingHoverTransitions()
        collapse()
    }

    public func suspendInteraction() {
        guard !isInteractionSuspended else { return }
        isInteractionSuspended = true
        isHovered = false
        expandedContentInteractionCount = 0
        expansionStartedAtUptime = nil
        cancelPendingHoverTransitions()

        guard state != nil else { return }
        state = nil
        layoutChangeSubject.send()
    }

    public func resumeInteraction() {
        isInteractionSuspended = false
    }

    private func scheduleHoverExpansion() {
        guard !isInteractionSuspended, !isExpanded, isHoverRevealEnabled else { return }
        let delay = max(interactionSettings.hoverRevealDelay, 0)
        hoverExpansionTask = Task { [weak self] in
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: Self.nanoseconds(for: delay))
                } catch {
                    return
                }
            }

            guard let self,
                  !self.isInteractionSuspended,
                  self.isHovered,
                  !self.isExpanded,
                  self.isHoverRevealEnabled else { return }
            self.expand()
        }
    }

    private func scheduleHoverCollapse() {
        guard expandedContentInteractionCount == 0, hoverCollapseTask == nil else { return }
        let expansionStabilizationRemaining = expansionStartedAtUptime.map {
            max(
                Self.expansionHoverStabilizationDuration
                    - (ProcessInfo.processInfo.systemUptime - $0),
                0
            )
        } ?? 0
        let delay = max(interactionSettings.hideDelay, expansionStabilizationRemaining)
        hoverCollapseTask = Task { [weak self] in
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: Self.nanoseconds(for: delay))
                } catch {
                    return
                }
            }

            guard let self else { return }
            self.hoverCollapseTask = nil
            guard !self.isHovered, self.isExpanded else { return }
            self.collapse()
        }
    }

    public func beginDragging() {
        guard !isInteractionSuspended else { return }
        guard state != .dragging else { return }
        cancelPendingHoverTransitions()
        expansionStartedAtUptime = ProcessInfo.processInfo.systemUptime
        state = .dragging
        layoutChangeSubject.send()
    }

    public func endDragging() {
        guard state == .dragging else { return }
        state = .expanded
        layoutChangeSubject.send()

        // 文件拖拽可能在指针已经离开 Island 后结束。此时 hoverChanged(false)
        // 不会再次到达，必须主动安排收起，避免 compact 提示被永久抑制。
        if !isHovered, expandedContentInteractionCount == 0 {
            scheduleHoverCollapse()
        }
    }

    private func expand() {
        guard !isInteractionSuspended else { return }
        expansionStartedAtUptime = ProcessInfo.processInfo.systemUptime
        state = .expanded
        layoutChangeSubject.send()
    }

    private func collapse() {
        expandedContentInteractionCount = 0
        expansionStartedAtUptime = nil
        state = nil
        layoutChangeSubject.send()
    }

    private func cancelPendingHoverTransitions() {
        hoverExpansionTask?.cancel()
        hoverExpansionTask = nil
        hoverCollapseTask?.cancel()
        hoverCollapseTask = nil
    }

    private func updateManagedDisplayExpansion() {
        let isExpanded = displayViewModels.values.contains(where: \.isExpanded)
        guard isExpanded != isAnyDisplayExpanded else { return }
        isAnyDisplayExpanded = isExpanded
        isExpandedSubject.send(isExpanded)
    }

    private static func nanoseconds(for delay: TimeInterval) -> UInt64 {
        let seconds = min(max(delay, 0), Double(UInt64.max) / 1_000_000_000)
        return UInt64(seconds * 1_000_000_000)
    }
}
