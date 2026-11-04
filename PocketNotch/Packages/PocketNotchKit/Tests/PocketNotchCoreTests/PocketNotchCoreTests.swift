import Combine
import XCTest
import SwiftUI
@testable import PocketNotchCore

@MainActor
final class NotchViewModelTests: XCTestCase {
    func testStartsHiddenWithNoInteractionState() {
        let vm = NotchViewModel()
        XCTAssertNil(vm.state)
        XCTAssertFalse(vm.isVisible)
    }

    func testExpandedPublisherEmitsInitialAndSynchronousStateChanges() {
        let settings = NotchInteractionSettings(defaults: nil, startsHidden: true)
        let vm = NotchViewModel(interactionSettings: settings)
        var values: [Bool] = []
        let cancellable = vm.isExpandedPublisher.sink { values.append($0) }

        XCTAssertEqual(values, [false])
        vm.click()
        XCTAssertEqual(values, [false, true])
        vm.beginDragging()
        XCTAssertEqual(values, [false, true])
        vm.endDragging()
        XCTAssertEqual(values, [false, true])

        withExtendedLifetime(cancellable) {}
    }

    func testDisplayViewModelsKeepExpansionStateIndependent() {
        let settings = NotchInteractionSettings(defaults: nil, startsHidden: true)
        let coordinator = NotchViewModel(interactionSettings: settings)
        let firstDisplay = coordinator.displayViewModel(for: "first")
        let secondDisplay = coordinator.displayViewModel(for: "second")

        firstDisplay.click()

        XCTAssertTrue(firstDisplay.isExpanded)
        XCTAssertFalse(secondDisplay.isExpanded)
        XCTAssertTrue(coordinator.isExpanded)

        secondDisplay.click()
        XCTAssertTrue(firstDisplay.isExpanded)
        XCTAssertTrue(secondDisplay.isExpanded)

        firstDisplay.click()
        XCTAssertFalse(firstDisplay.isExpanded)
        XCTAssertTrue(secondDisplay.isExpanded)
        XCTAssertTrue(coordinator.isExpanded)

        secondDisplay.click()
        XCTAssertFalse(coordinator.isExpanded)
    }

    func testDisplayViewModelsShareInteractionSettings() {
        let settings = NotchInteractionSettings(defaults: nil, startsHidden: true)
        let coordinator = NotchViewModel(interactionSettings: settings)
        let firstDisplay = coordinator.displayViewModel(for: "first")
        let secondDisplay = coordinator.displayViewModel(for: "second")

        XCTAssertTrue(firstDisplay.interactionSettings === settings)
        XCTAssertTrue(secondDisplay.interactionSettings === settings)

        settings.isClickEnabled = false
        firstDisplay.click()
        secondDisplay.click()

        XCTAssertFalse(firstDisplay.isExpanded)
        XCTAssertFalse(secondDisplay.isExpanded)
    }

    func testRemovingExpandedDisplayUpdatesAggregateExpansionState() {
        let settings = NotchInteractionSettings(defaults: nil, startsHidden: true)
        let coordinator = NotchViewModel(interactionSettings: settings)
        let display = coordinator.displayViewModel(for: "display")
        display.click()
        XCTAssertTrue(coordinator.isExpanded)

        coordinator.removeDisplayViewModel(for: "display")

        XCTAssertFalse(coordinator.isExpanded)
    }

    func testClickTriggerTogglesExpandedState() {
        let settings = NotchInteractionSettings(defaults: nil, startsHidden: true)
        let vm = NotchViewModel(interactionSettings: settings)

        vm.click()
        XCTAssertTrue(vm.isVisible)
        XCTAssertTrue(vm.isExpanded)
        vm.click()
        XCTAssertFalse(vm.isVisible)
        XCTAssertFalse(vm.isExpanded)
    }

    func testClickIsIgnoredWhenDisabledAndWorksAfterReenabled() {
        let settings = NotchInteractionSettings(
            defaults: nil,
            startsHidden: true,
            isClickEnabled: false
        )
        let vm = NotchViewModel(interactionSettings: settings)

        vm.click()
        XCTAssertFalse(vm.isExpanded)

        settings.isClickEnabled = true
        vm.click()
        XCTAssertTrue(vm.isExpanded)
    }

    func testHoverRevealWaitsUntilGateReopens() async throws {
        let settings = NotchInteractionSettings(
            defaults: nil,
            startsHidden: true,
            hoverRevealDelay: 0.1
        )
        let vm = NotchViewModel(interactionSettings: settings)
        vm.setHoverRevealEnabled(false)
        vm.hoverChanged(true)

        try await Task.sleep(nanoseconds: 130_000_000)
        XCTAssertFalse(vm.isExpanded)

        vm.setHoverRevealEnabled(true)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(vm.isExpanded)

        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(vm.isExpanded)
    }

    func testHoverRevealDoesNotResumeAfterPointerLeavesWhileGated() async throws {
        let settings = NotchInteractionSettings(
            defaults: nil,
            startsHidden: true,
            hoverRevealDelay: 0.1
        )
        let vm = NotchViewModel(interactionSettings: settings)
        vm.setHoverRevealEnabled(false)
        vm.hoverChanged(true)
        vm.hoverChanged(false)
        vm.setHoverRevealEnabled(true)

        try await Task.sleep(nanoseconds: 130_000_000)

        XCTAssertFalse(vm.isExpanded)
    }

    func testHoverRevealGateDoesNotBlockClick() {
        let settings = NotchInteractionSettings(defaults: nil, startsHidden: true)
        let vm = NotchViewModel(interactionSettings: settings)
        vm.setHoverRevealEnabled(false)

        vm.click()

        XCTAssertTrue(vm.isExpanded)
    }

    func testHoverTriggerDisabledStillAllowsClickExpansion() {
        let settings = NotchInteractionSettings(
            defaults: nil,
            startsHidden: true,
            isHoverTriggerEnabled: false
        )
        let vm = NotchViewModel(interactionSettings: settings)

        vm.hoverChanged(true)
        vm.click()

        XCTAssertTrue(vm.isExpanded)
    }

    func testDefaultHoverDelayIsHalfSecond() {
        XCTAssertEqual(NotchInteractionSettings(defaults: nil).hoverRevealDelay, 0.5)
    }

    func testHoverExpandsAfterConfiguredDelayAndCollapsesOnExit() async throws {
        let settings = NotchInteractionSettings(
            defaults: nil,
            hideDelay: 0,
            startsHidden: true,
            hoverRevealDelay: 0.1
        )
        let vm = NotchViewModel(interactionSettings: settings)

        vm.hoverChanged(true)
        XCTAssertFalse(vm.isExpanded)

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(vm.isExpanded)

        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(vm.isExpanded)

        vm.hoverChanged(false)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(vm.isExpanded)

        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertFalse(vm.isExpanded)
    }

    func testTransientHoverExitDuringExpansionDoesNotCollapse() async throws {
        let settings = NotchInteractionSettings(
            defaults: nil,
            hideDelay: 0,
            startsHidden: true
        )
        let vm = NotchViewModel(interactionSettings: settings)

        vm.hoverChanged(true)
        vm.click()
        XCTAssertTrue(vm.isExpanded)

        // 展开改变 tracking area 时，SwiftUI 可能在相邻两帧内发出 false -> true。
        vm.hoverChanged(false)
        try await Task.sleep(nanoseconds: 30_000_000)
        vm.hoverChanged(true)

        try await Task.sleep(nanoseconds: 180_000_000)
        XCTAssertTrue(vm.isExpanded)
    }

    func testClickExpansionWaitsForPresentationBeforeCollapsingOnExit() async throws {
        let settings = NotchInteractionSettings(
            defaults: nil,
            hideDelay: 0,
            startsHidden: true
        )
        let vm = NotchViewModel(interactionSettings: settings)

        vm.hoverChanged(true)
        vm.click()
        XCTAssertTrue(vm.isExpanded)

        vm.hoverChanged(false)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(vm.isExpanded)

        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertFalse(vm.isExpanded)
    }

    func testPointerExitCollapsesPromptlyAfterExpansionPresentationStabilizes() async throws {
        let settings = NotchInteractionSettings(
            defaults: nil,
            hideDelay: 0.1,
            startsHidden: true
        )
        let vm = NotchViewModel(interactionSettings: settings)

        vm.click()
        try await Task.sleep(nanoseconds: 650_000_000)

        vm.hoverChanged(false)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(vm.isExpanded)

        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(vm.isExpanded)
    }

    func testClickingHoverExpansionCollapsesAfterMinimumDelay() async throws {
        let settings = NotchInteractionSettings(
            defaults: nil,
            startsHidden: true,
            hoverRevealDelay: 0.1
        )
        let vm = NotchViewModel(interactionSettings: settings)

        vm.hoverChanged(true)
        try await Task.sleep(nanoseconds: 130_000_000)
        XCTAssertTrue(vm.isExpanded)

        vm.click()
        XCTAssertFalse(vm.isExpanded)
    }

    func testRepeatedHoverEnterDoesNotRestartRevealDelay() async throws {
        let settings = NotchInteractionSettings(
            defaults: nil,
            startsHidden: true,
            hoverRevealDelay: 0.1
        )
        let vm = NotchViewModel(interactionSettings: settings)

        vm.hoverChanged(true)
        try await Task.sleep(nanoseconds: 70_000_000)
        vm.hoverChanged(true)
        try await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertTrue(vm.isExpanded)
    }

    func testRestartPendingHoverRevealUsesLatestDelay() async throws {
        let settings = NotchInteractionSettings(
            defaults: nil,
            startsHidden: true,
            hoverRevealDelay: 0.3
        )
        let vm = NotchViewModel(interactionSettings: settings)

        vm.hoverChanged(true)
        try await Task.sleep(nanoseconds: 50_000_000)
        settings.hoverRevealDelay = 0.1
        vm.restartPendingHoverReveal()
        try await Task.sleep(nanoseconds: 130_000_000)

        XCTAssertTrue(vm.isExpanded)
    }

    func testDraggingOutsideIslandCollapsesAfterPresentationStabilizes() async throws {
        let settings = NotchInteractionSettings(
            defaults: nil,
            hideDelay: 0,
            startsHidden: true
        )
        let vm = NotchViewModel(interactionSettings: settings)
        vm.beginDragging()
        XCTAssertEqual(vm.state, .dragging)
        XCTAssertTrue(vm.isExpanded)

        vm.endDragging()
        XCTAssertEqual(vm.state, .expanded)
        XCTAssertTrue(vm.isExpanded)

        try await Task.sleep(nanoseconds: 650_000_000)
        XCTAssertNil(vm.state)
        XCTAssertFalse(vm.isExpanded)
    }

    func testDraggingKeepsExpandedUntilHoveredPointerLeaves() async throws {
        let settings = NotchInteractionSettings(
            defaults: nil,
            hideDelay: 0,
            startsHidden: true
        )
        let vm = NotchViewModel(interactionSettings: settings)
        vm.hoverChanged(true)
        vm.beginDragging()
        vm.endDragging()

        try await Task.sleep(nanoseconds: 650_000_000)
        XCTAssertTrue(vm.isExpanded)

        vm.hoverChanged(false)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(vm.isExpanded)
    }

    func testSessionSuspensionCollapsesAndBlocksInteractionUntilResume() {
        let settings = NotchInteractionSettings(defaults: nil, startsHidden: true)
        let vm = NotchViewModel(interactionSettings: settings)
        vm.click()
        XCTAssertTrue(vm.isExpanded)

        vm.suspendInteraction()

        XCTAssertTrue(vm.isInteractionSuspended)
        XCTAssertNil(vm.state)
        vm.click()
        vm.hoverChanged(true)
        XCTAssertFalse(vm.isExpanded)

        vm.resumeInteraction()
        vm.click()
        XCTAssertFalse(vm.isInteractionSuspended)
        XCTAssertTrue(vm.isExpanded)
    }

    func testSessionSuspensionClearsOldHoverBeforeStationaryPointerIsResampled() async throws {
        let settings = NotchInteractionSettings(
            defaults: nil,
            startsHidden: true,
            hoverRevealDelay: 0.1
        )
        let vm = NotchViewModel(interactionSettings: settings)
        vm.hoverChanged(true)
        vm.suspendInteraction()
        vm.resumeInteraction()

        try await Task.sleep(nanoseconds: 130_000_000)
        XCTAssertFalse(vm.isExpanded)

        vm.hoverChanged(true)
        try await Task.sleep(nanoseconds: 130_000_000)
        XCTAssertTrue(vm.isExpanded)
    }
}

final class IslandPresentationStateMachineTests: XCTestCase {
    func testCompactPresentationPhases() {
        XCTAssertEqual(
            IslandPresentationStateMachine.phase(
                transition: .compact,
                isHovered: false,
                isExpandedContentVisible: false
            ),
            .idle
        )

        XCTAssertEqual(
            IslandPresentationStateMachine.phase(
                transition: .compact,
                isHovered: true,
                isExpandedContentVisible: false
            ),
            .hover
        )
    }

    func testExpandedPresentationPhases() {
        XCTAssertEqual(
            IslandPresentationStateMachine.phase(
                transition: .expanding,
                isHovered: true,
                isExpandedContentVisible: false
            ),
            .expanding
        )

        XCTAssertEqual(
            IslandPresentationStateMachine.phase(
                transition: .expanded,
                isHovered: true,
                isExpandedContentVisible: false
            ),
            .expanded
        )

        XCTAssertEqual(
            IslandPresentationStateMachine.phase(
                transition: .expanded,
                isHovered: true,
                isExpandedContentVisible: true
            ),
            .interactive
        )
    }

    func testCollapsePhaseKeepsItsDirection() {
        XCTAssertEqual(
            IslandPresentationStateMachine.phase(
                transition: .collapsing,
                isHovered: false,
                isExpandedContentVisible: false
            ),
            .collapsing
        )
    }

    func testCompactForm() {
        XCTAssertEqual(
            IslandPresentationStateMachine.compactForm(showsCompactContent: false),
            .resting
        )
        XCTAssertEqual(
            IslandPresentationStateMachine.compactForm(showsCompactContent: true),
            .dynamic
        )
    }

    func testAmbientShadowLayerSmoothsSilhouetteInsideCanvasBudget() {
        // 仅展开态投影：环境层比主层更大更淡，且两层都留在画布预算内。
        let shadowPhases: [IslandPresentationPhase] = [.expanding, .expanded, .interactive]
        for phase in shadowPhases {
            let primary = IslandMaterialToken.shadowStyle(for: phase, compactMorphProgress: 1)
            let ambient = IslandMaterialToken.ambientShadowStyle(for: phase, compactMorphProgress: 1)
            XCTAssertGreaterThan(ambient.radius, primary.radius, "\(phase)")
            XCTAssertLessThan(ambient.opacity, primary.opacity, "\(phase)")
            XCTAssertLessThanOrEqual(
                ambient.radius + ambient.offsetY,
                IslandLayoutToken.hoverOutset,
                "\(phase)"
            )
            XCTAssertLessThanOrEqual(
                primary.radius + primary.offsetY,
                IslandLayoutToken.hoverOutset,
                "\(phase)"
            )
        }

        // 收起 / 灵动态 / 收起过程不投影。
        let shadowlessPhases: [IslandPresentationPhase] = [.hidden, .idle, .hover, .collapsing]
        for phase in shadowlessPhases {
            XCTAssertEqual(
                IslandMaterialToken.shadowStyle(for: phase, compactMorphProgress: 1),
                IslandShadowStyle(opacity: 0, radius: 0, offsetY: 0),
                "\(phase)"
            )
            XCTAssertEqual(
                IslandMaterialToken.ambientShadowStyle(for: phase, compactMorphProgress: 1),
                IslandShadowStyle(opacity: 0, radius: 0, offsetY: 0),
                "\(phase)"
            )
        }
    }

    func testMaterialTokensKeepInteractionHierarchy() {
        XCTAssertLessThan(
            IslandMaterialToken.glowOpacity(for: .idle),
            IslandMaterialToken.glowOpacity(for: .hover)
        )
        XCTAssertGreaterThan(
            IslandMaterialToken.glowOpacity(for: .hover),
            IslandMaterialToken.glowOpacity(for: .interactive)
        )
        for phase in [
            IslandPresentationPhase.expanding,
            .expanded,
            .interactive,
            .collapsing
        ] {
            XCTAssertEqual(IslandMaterialToken.glowOpacity(for: phase), 0)
        }

        // 投影只属于展开态；收起 / 灵动态一律为零。
        for phase: IslandPresentationPhase in [.hidden, .idle, .hover, .collapsing] {
            XCTAssertEqual(
                IslandMaterialToken.shadowStyle(for: phase, compactMorphProgress: 1),
                IslandShadowStyle(opacity: 0, radius: 0, offsetY: 0),
                "\(phase)"
            )
        }

        // 展开 / 加载 / 交互保持「更大更淡」的渐进层级。
        let expandingShadow = IslandMaterialToken.shadowStyle(
            for: .expanding,
            compactMorphProgress: 1
        )
        let expandedShadow = IslandMaterialToken.shadowStyle(
            for: .expanded,
            compactMorphProgress: 1
        )
        let interactiveShadow = IslandMaterialToken.shadowStyle(
            for: .interactive,
            compactMorphProgress: 1
        )
        XCTAssertGreaterThan(expandingShadow.opacity, 0)
        XCTAssertGreaterThan(expandedShadow.opacity, 0)
        XCTAssertGreaterThan(interactiveShadow.opacity, 0)
        XCTAssertGreaterThan(expandingShadow.radius, interactiveShadow.radius)
        XCTAssertGreaterThan(expandingShadow.opacity, interactiveShadow.opacity)
    }

    func testExpandedShadowPreservesCanvasBudgetForFloatingIsland() {
        for phase: IslandPresentationPhase in [.hidden, .idle, .hover, .collapsing] {
            XCTAssertEqual(
                IslandMaterialToken.shadowStyle(
                    for: phase,
                    compactMorphProgress: 1,
                    isFloatingIsland: true
                ),
                IslandShadowStyle(opacity: 0, radius: 0, offsetY: 0),
                "\(phase)"
            )
        }
        XCTAssertGreaterThan(
            IslandMaterialToken.shadowStyle(
                for: .expanded,
                compactMorphProgress: 1,
                isFloatingIsland: true
            ).opacity,
            0
        )
    }
}

@MainActor
final class IslandPhaseControllerTests: XCTestCase {
    func testReducedMotionSetsCompactMorphToTargetImmediately() {
        let controller = IslandPhaseController()

        controller.setCompactModuleContentVisible(true, reduceMotion: true)
        XCTAssertTrue(controller.hasCompactModuleContent)
        XCTAssertEqual(controller.compactMorphProgress, 1)

        controller.setCompactModuleContentVisible(false, reduceMotion: true)
        XCTAssertFalse(controller.hasCompactModuleContent)
        XCTAssertEqual(controller.compactMorphProgress, 0)
    }

    func testExpansionStartsExpandingAndPreservesHoverPresentation() {
        let controller = IslandPhaseController()
        controller.isHovered = true
        let startSize = CGSize(width: 310, height: 43)

        controller.beginExpansion(from: startSize)

        XCTAssertTrue(
            controller.transition == .expanding || controller.transition == .expanded
        )
        XCTAssertEqual(controller.expansionStartSize, startSize)
        XCTAssertTrue(controller.usesExpandedGeometry)
        XCTAssertFalse(controller.showsCompactContent)
        XCTAssertFalse(controller.showsExpandedContent)
        XCTAssertFalse(controller.isHoverPreviewActive)
        XCTAssertTrue(controller.preservesCompactHoverPresentation)
    }

    func testExpansionWithoutHoverDoesNotPreserveHoverPresentation() {
        let controller = IslandPhaseController()

        controller.beginExpansion(from: CGSize(width: 300, height: 38))

        XCTAssertFalse(controller.preservesCompactHoverPresentation)
    }

    func testReducedMotionRestoresCompactContentBeforeBecomingReady() async throws {
        let controller = IslandPhaseController(isExpanded: true)
        controller.isHovered = true

        controller.beginCollapse(
            compactBackgroundSize: CGSize(width: 300, height: 38),
            reduceMotion: true
        )

        XCTAssertEqual(controller.transition, .collapsing)
        XCTAssertEqual(controller.expansionProgress, 0)
        XCTAssertFalse(controller.usesExpandedGeometry)
        XCTAssertTrue(controller.showsCompactContent)
        XCTAssertFalse(controller.showsExpandedContent)
        XCTAssertFalse(controller.isCompactPresentationReady)
        XCTAssertFalse(controller.isHoverPreviewActive)

        try await Task.sleep(
            nanoseconds: PocketNotchTheme.islandReducedMotionDurationNanoseconds + 5_000_000
        )

        XCTAssertEqual(controller.transition, .collapsing)
        XCTAssertFalse(controller.usesExpandedGeometry)
        XCTAssertFalse(controller.isCompactPresentationReady)
        XCTAssertFalse(controller.isHoverPreviewActive)

        try await Task.sleep(
            nanoseconds: PocketNotchTheme.islandCompactActivationDelayNanoseconds + 20_000_000
        )

        XCTAssertEqual(controller.transition, .compact)
        XCTAssertTrue(controller.isCompactPresentationReady)
        XCTAssertTrue(controller.isHoverPreviewActive)
    }

    func testPointerExitBeforeCompactActivationKeepsIdlePresentation() async throws {
        let controller = IslandPhaseController(isExpanded: true)
        controller.isHovered = true
        controller.beginCollapse(
            compactBackgroundSize: CGSize(width: 300, height: 38),
            reduceMotion: true
        )
        try await Task.sleep(
            nanoseconds: PocketNotchTheme.islandReducedMotionDurationNanoseconds + 5_000_000
        )
        XCTAssertEqual(controller.transition, .collapsing)
        XCTAssertFalse(controller.usesExpandedGeometry)

        controller.isHovered = false
        try await Task.sleep(
            nanoseconds: PocketNotchTheme.islandCompactActivationDelayNanoseconds + 20_000_000
        )

        XCTAssertEqual(controller.transition, .compact)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertFalse(controller.isHoverPreviewActive)
    }

    func testExpansionCancelsPendingCompactActivation() async throws {
        let controller = IslandPhaseController(isExpanded: true)
        controller.isHovered = true
        controller.beginCollapse(
            compactBackgroundSize: CGSize(width: 300, height: 38),
            reduceMotion: true
        )
        try await Task.sleep(
            nanoseconds: PocketNotchTheme.islandReducedMotionDurationNanoseconds + 5_000_000
        )
        XCTAssertEqual(controller.transition, .collapsing)
        XCTAssertFalse(controller.usesExpandedGeometry)

        controller.beginExpansion(from: CGSize(width: 300, height: 38))
        try await Task.sleep(
            nanoseconds: PocketNotchTheme.islandCompactActivationDelayNanoseconds + 30_000_000
        )

        XCTAssertNotEqual(controller.transition, .compact)
        XCTAssertTrue(controller.usesExpandedGeometry)
        XCTAssertFalse(controller.isCompactPresentationReady)
    }

    func testCollapseRecoversCompactContentBeforePresentationBecomesReady() async throws {
        let controller = IslandPhaseController(isExpanded: true)
        controller.isHovered = true

        controller.beginCollapse(compactBackgroundSize: CGSize(width: 300, height: 38))
        try await Task.sleep(
            nanoseconds: 110_000_000
                + PocketNotchTheme.islandCompactContentRecoveryDelayNanoseconds
                + 30_000_000
        )

        XCTAssertTrue(controller.showsCompactContent)
        XCTAssertEqual(controller.transition, .collapsing)
        XCTAssertFalse(controller.isCompactPresentationReady)
        XCTAssertFalse(controller.isHoverPreviewActive)

        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(controller.transition, .compact)
        XCTAssertTrue(controller.isCompactPresentationReady)
        XCTAssertTrue(controller.isHoverPreviewActive)
    }

    func testCollapseDoesNotActivateHoverAfterPointerLeavesDuringRecovery() async throws {
        let controller = IslandPhaseController(isExpanded: true)
        controller.isHovered = true
        controller.beginCollapse(compactBackgroundSize: CGSize(width: 300, height: 38))
        controller.isHovered = false

        try await Task.sleep(nanoseconds: 850_000_000)

        XCTAssertTrue(controller.isCompactPresentationReady)
        XCTAssertFalse(controller.isHoverPreviewActive)
        XCTAssertEqual(controller.phase, .idle)
    }

    func testExpansionInvalidatesPendingCompactRecovery() async throws {
        let controller = IslandPhaseController(isExpanded: true)
        controller.beginCollapse(compactBackgroundSize: CGSize(width: 300, height: 38))
        try await Task.sleep(
            nanoseconds: 110_000_000
                + PocketNotchTheme.islandCompactContentRecoveryDelayNanoseconds
                + 20_000_000
        )
        XCTAssertTrue(controller.showsCompactContent)
        XCTAssertEqual(controller.transition, .collapsing)

        controller.beginExpansion(from: CGSize(width: 300, height: 38))
        try await Task.sleep(
            nanoseconds: PocketNotchTheme.islandCompactContentRecoveryDurationNanoseconds
                + 30_000_000
        )

        XCTAssertNotEqual(controller.transition, .compact)
        XCTAssertFalse(controller.isCompactPresentationReady)
        XCTAssertTrue(controller.usesExpandedGeometry)
    }

    func testCollapseDuringExpansionTargetsCompactWithoutExitDelay() async throws {
        let controller = IslandPhaseController()
        controller.isHovered = true
        controller.beginExpansion(from: CGSize(width: 310, height: 43))
        XCTAssertTrue(
            controller.transition == .expanding || controller.transition == .expanded
        )
        XCTAssertEqual(controller.expansionProgress, 1)
        XCTAssertFalse(controller.showsExpandedContent)

        controller.beginCollapse(compactBackgroundSize: CGSize(width: 300, height: 38))

        XCTAssertEqual(controller.transition, .collapsing)
        XCTAssertEqual(controller.expansionProgress, 0)
        XCTAssertTrue(controller.usesExpandedGeometry)
        XCTAssertTrue(controller.showsCompactContent)
        XCTAssertFalse(controller.showsExpandedContent)
    }

    func testExpansionRetargetsAnActiveCollapseWithoutResettingGeometry() async throws {
        let controller = IslandPhaseController(isExpanded: true)
        controller.beginCollapse(compactBackgroundSize: CGSize(width: 300, height: 38))
        try await Task.sleep(
            nanoseconds: 110_000_000 + 30_000_000
        )
        XCTAssertEqual(controller.transition, .collapsing)
        XCTAssertEqual(controller.expansionProgress, 0)
        XCTAssertTrue(controller.usesExpandedGeometry)

        controller.beginExpansion(from: CGSize(width: 300, height: 38))

        XCTAssertTrue(
            controller.transition == .expanding || controller.transition == .expanded
        )
        XCTAssertEqual(controller.expansionProgress, 1)
        XCTAssertTrue(controller.usesExpandedGeometry)
        XCTAssertFalse(controller.showsCompactContent)

        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(controller.usesExpandedGeometry)
        XCTAssertNotEqual(controller.transition, .compact)
        XCTAssertFalse(controller.isCompactPresentationReady)
    }

    func testSessionSuspensionResetsExpandedPresentationWithoutAnimation() {
        let controller = IslandPhaseController(isExpanded: true)
        controller.isHovered = true

        controller.resetForSessionSuspension()

        XCTAssertEqual(controller.transition, .compact)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(controller.expansionProgress, 0)
        XCTAssertFalse(controller.usesExpandedGeometry)
        XCTAssertTrue(controller.showsCompactContent)
        XCTAssertFalse(controller.showsExpandedContent)
        XCTAssertNil(controller.expansionStartSize)
        XCTAssertFalse(controller.isHovered)
        XCTAssertFalse(controller.preservesCompactHoverPresentation)
        XCTAssertTrue(controller.isCompactPresentationReady)
    }

    /// 回归测试：展开进度为 0 时，展开态背板路径必须与灵动态路径逐点一致。
    /// 背板材质连续性依赖这一几何等价——fill 全程不透明，不存在淡入淡出，
    /// 几何跳变只能由路径本身消除。
    func testExpandedPathAtZeroProgressMatchesCompactPath() {
        let metrics = IslandBackgroundMetrics(
            hiddenWidth: 300,
            hiddenHeight: 38
        )
        let rect = CGRect(x: 0, y: 0, width: 300, height: 38)

        func signature(of path: CGPath) -> String {
            var components: [String] = []
            path.applyWithBlock { element in
                let pointCount: Int
                switch element.pointee.type {
                case .moveToPoint, .addLineToPoint: pointCount = 1
                case .addQuadCurveToPoint: pointCount = 2
                case .addCurveToPoint: pointCount = 3
                case .closeSubpath: pointCount = 0
                @unknown default: pointCount = 0
                }
                let points = (0..<pointCount).map { index -> String in
                    let point = element.pointee.points[index]
                    return String(format: "%.4f,%.4f", point.x, point.y)
                }
                components.append("\(element.pointee.type.rawValue)|\(points.joined(separator: ";"))")
            }
            return components.joined(separator: "\n")
        }

        let compact = IslandBackgroundPath.makePath(
            for: .hidden,
            in: rect,
            metrics: metrics,
            compactMorphProgress: 1,
            rendersInFullBounds: true
        )
        let expandedAtStart = IslandBackgroundPath.makePath(
            for: .expanded,
            in: rect,
            metrics: metrics,
            expansionProgress: 0,
            compactMorphProgress: 1,
            rendersInFullBounds: true
        )

        XCTAssertEqual(signature(of: compact), signature(of: expandedAtStart))
    }

    /// 回归测试：收起全程几何状态保持展开画布、progress 归零。
    /// （背板已无透明度通道，旧的「收起尾段不得淡出」约束由构造保证。）
    func testBackgroundStaysOnExpandedCanvasWhileCollapsing() {
        let controller = IslandPhaseController(isExpanded: true)

        XCTAssertTrue(controller.usesExpandedGeometry)

        controller.beginCollapse(compactBackgroundSize: CGSize(width: 300, height: 38))
        XCTAssertEqual(controller.transition, .collapsing)
        XCTAssertTrue(controller.usesExpandedGeometry)
        XCTAssertEqual(controller.expansionProgress, 0)
    }
}


@MainActor
final class NotchInteractionSettingsTests: XCTestCase {
    func testInteractionPreferencesPersistAndRestore() {
        let suiteName = "NotchInteractionSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = NotchInteractionSettings(defaults: defaults)
        XCTAssertEqual(settings.hoverRevealDelay, 0.5)
        XCTAssertTrue(settings.isClickEnabled)
        XCTAssertEqual(settings.hoverHapticIntensity, .light)
        XCTAssertTrue(settings.isHiddenInScreenCapture)

        settings.hoverRevealDelay = 0.7
        settings.isClickEnabled = false
        settings.hoverHapticIntensity = .strong
        settings.isHiddenInScreenCapture = false

        let restored = NotchInteractionSettings(defaults: defaults)
        XCTAssertEqual(restored.hoverRevealDelay, 0.7)
        XCTAssertFalse(restored.isClickEnabled)
        XCTAssertEqual(restored.hoverHapticIntensity, .strong)
        XCTAssertFalse(restored.isHiddenInScreenCapture)
    }

    func testHoverDelayIsClampedAndResetRestoresDefaults() {
        let suiteName = "NotchInteractionSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(3, forKey: "interaction.island.hoverRevealDelay")
        let settings = NotchInteractionSettings(defaults: defaults)
        settings.isClickEnabled = false
        settings.hoverHapticIntensity = .strong
        settings.isHiddenInScreenCapture = false

        XCTAssertEqual(settings.hoverRevealDelay, 1)
        XCTAssertEqual(defaults.double(forKey: "interaction.island.hoverRevealDelay"), 1)

        settings.resetToDefaults()
        XCTAssertEqual(settings.hoverRevealDelay, 0.5)
        XCTAssertTrue(settings.isClickEnabled)
        XCTAssertEqual(settings.hoverHapticIntensity, .light)
        XCTAssertTrue(settings.isHiddenInScreenCapture)
    }
}

@MainActor
final class ExpandedTabSettingsTests: XCTestCase {
    func testDefaultsMatchExpandedTabDefaultOrder() {
        let settings = ExpandedTabSettings(defaults: nil)

        XCTAssertEqual(settings.managedTabs, ExpandedIslandTab.defaultOrder)
        XCTAssertEqual(
            ExpandedIslandTab.defaultOrder,
            [.home, .applications, .transfer, .agentSessions, .clipboard, .stocks]
        )
        XCTAssertTrue(settings.disabledTabs.isEmpty)
        XCTAssertEqual(settings.visibleTabs, ExpandedIslandTab.defaultOrder)
        // 无标签栏入口的 tab 不参与管理。
        XCTAssertFalse(settings.managedTabs.contains(.ai))
    }

    func testOrderAndDisabledTabsPersistAndRestore() {
        let suiteName = "ExpandedTabSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = ExpandedTabSettings(defaults: defaults)
        settings.moveDown(.home)
        settings.setEnabled(false, for: .stocks)

        let restored = ExpandedTabSettings(defaults: defaults)
        XCTAssertEqual(restored.managedTabs.first, .applications)
        XCTAssertFalse(restored.isEnabled(.stocks))
        XCTAssertEqual(
            restored.visibleTabs,
            [.applications, .home, .transfer, .agentSessions, .clipboard]
        )
    }

    func testLastEnabledTabCannotBeDisabled() {
        let settings = ExpandedTabSettings(defaults: nil)
        ExpandedIslandTab.defaultOrder.dropFirst().forEach { tab in
            settings.setEnabled(false, for: tab)
        }
        XCTAssertTrue(settings.isEnabled(.home))
        XCTAssertEqual(settings.visibleTabs, [.home])

        settings.setEnabled(false, for: .home)
        XCTAssertTrue(settings.isEnabled(.home), "最后一个启用标签应保持启用")
        XCTAssertFalse(settings.canDisable(.home))

        settings.setEnabled(true, for: .stocks)
        XCTAssertTrue(settings.canDisable(.stocks))
        settings.setEnabled(false, for: .stocks)
        XCTAssertFalse(settings.isEnabled(.stocks))
    }

    func testMoveUpAndDownRespectBounds() {
        let settings = ExpandedTabSettings(defaults: nil)

        settings.moveUp(.home)
        XCTAssertEqual(settings.managedTabs.first, .home)

        settings.moveDown(.home)
        XCTAssertEqual(settings.managedTabs.first, .applications)
        XCTAssertEqual(settings.managedTabs[1], .home)

        settings.moveDown(.stocks)
        XCTAssertEqual(settings.managedTabs.last, .stocks)
    }

    func testResetToDefaultsRestoresOrderAndEnablesAllTabs() {
        let settings = ExpandedTabSettings(defaults: nil)
        settings.setEnabled(false, for: .transfer)
        settings.moveDown(.home)

        settings.resetToDefaults()

        XCTAssertEqual(settings.managedTabs, ExpandedIslandTab.defaultOrder)
        XCTAssertTrue(settings.disabledTabs.isEmpty)
    }

    func testManagedTabsAppendsTabsMissingFromStoredOrder() {
        let suiteName = "ExpandedTabSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // 模拟旧版本持久化数据缺少部分标签。
        defaults.set(
            [ExpandedIslandTab.home.rawValue, ExpandedIslandTab.stocks.rawValue],
            forKey: "interaction.island.expandedTabOrder"
        )

        let settings = ExpandedTabSettings(defaults: defaults)
        XCTAssertEqual(
            settings.managedTabs,
            [.home, .stocks, .applications, .transfer, .agentSessions, .clipboard]
        )
    }
}

@MainActor
final class ExpandedTabRequestControllerTests: XCTestCase {
    func testRequestThenConsumeSwitchesOnce() {
        let controller = ExpandedTabRequestController()
        controller.request(.clipboard)
        XCTAssertEqual(controller.pendingTab, .clipboard)
        XCTAssertEqual(controller.consume(), .clipboard)
        XCTAssertNil(controller.pendingTab)
        XCTAssertNil(controller.consume(), "消费后再次消费应返回 nil")
    }

    func testConsumeWithoutRequestReturnsNil() {
        let controller = ExpandedTabRequestController()
        XCTAssertNil(controller.consume())
    }

    func testRequestOverridesPreviousRequest() {
        let controller = ExpandedTabRequestController()
        controller.request(.folders)
        controller.request(.clipboard)
        XCTAssertEqual(controller.consume(), .clipboard)
    }

    func testRequestExpiresAfterInterval() async throws {
        let controller = ExpandedTabRequestController(expiryInterval: 0.05)
        controller.request(.clipboard)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNil(controller.pendingTab)
    }

    func testCancelClearsRequest() {
        let controller = ExpandedTabRequestController()
        controller.request(.clipboard)
        controller.cancel()
        XCTAssertNil(controller.pendingTab)
    }
}

@MainActor
final class ModuleRegistryTests: XCTestCase {
    struct StubModule: PocketNotchModule {
        let id: String
        let title: LocalizedStringKey = ""
        let priority: Int
        func collapsedView() -> AnyView { AnyView(EmptyView()) }
        func expandedView() -> AnyView { AnyView(EmptyView()) }
        func activate() {}
        func deactivate() {}
    }

    func testRegisterSortsByPriority() {
        let registry = ModuleRegistry()
        registry.register(StubModule(id: "b", priority: 30))
        registry.register(StubModule(id: "a", priority: 10))
        XCTAssertEqual(registry.modules.map(\.id), ["a", "b"])
    }

    func testRegisterIgnoresDuplicateID() {
        let registry = ModuleRegistry()
        registry.register(StubModule(id: "a", priority: 10))
        registry.register(StubModule(id: "a", priority: 20))
        XCTAssertEqual(registry.modules.count, 1)
    }
}

@MainActor
final class IslandAppearanceSettingsTests: XCTestCase {
    func testHiddenHeightPrioritizesNotchThenMenuBarThenThirtyTwoPoints() {
        XCTAssertEqual(
            NotchPositioner.resolvedHiddenHeight(notchHeight: 38, menuBarHeight: 24),
            38
        )
        XCTAssertEqual(
            NotchPositioner.resolvedHiddenHeight(notchHeight: 0, menuBarHeight: 24),
            24
        )
        XCTAssertEqual(
            NotchPositioner.resolvedHiddenHeight(notchHeight: .nan, menuBarHeight: 0),
            32
        )
    }

    func testVisualMenuBarHeightRemovesOnePhysicalPixelSeparator() {
        XCTAssertEqual(
            NotchPositioner.visualMenuBarHeight(
                reservedHeight: 25,
                backingScaleFactor: 1
            ),
            24
        )
        XCTAssertEqual(
            NotchPositioner.visualMenuBarHeight(
                reservedHeight: 24.5,
                backingScaleFactor: 2
            ),
            24
        )
        XCTAssertEqual(
            NotchPositioner.visualMenuBarHeight(
                reservedHeight: 24.6666666667,
                backingScaleFactor: 1.5
            ),
            24,
            accuracy: 0.001
        )
    }

    func testCompactContentHeightDerivesFromUnifiedIslandHeight() {
        XCTAssertEqual(
            IslandAppearanceConstraints.compactContentHeight(islandHeight: 32),
            24
        )
        XCTAssertEqual(
            IslandAppearanceConstraints.compactContentHeight(islandHeight: 40),
            32
        )
        XCTAssertEqual(
            IslandAppearanceConstraints.compactContentHeight(islandHeight: 48),
            40
        )
        // 低于兜底下限时回落到 minimumCompactHeight。
        XCTAssertEqual(
            IslandAppearanceConstraints.compactContentHeight(islandHeight: 20),
            IslandAppearanceConstraints.minimumCompactHeight
        )
    }

    func testAutomaticCompactOuterInsetDefaultsAndClampsRange() {
        XCTAssertEqual(
            IslandAppearanceConstraints.resolvedCompactOuterInset(
                preferredInset: nil,
                compactHeight: 38,
                wallInset: 8
            ),
            IslandAppearanceConstraints.defaultCompactOuterInset
        )
        XCTAssertEqual(
            IslandAppearanceConstraints.resolvedCompactOuterInset(
                preferredInset: 0,
                compactHeight: 38,
                wallInset: 8
            ),
            1
        )
        XCTAssertEqual(
            IslandAppearanceConstraints.resolvedCompactOuterInset(
                preferredInset: 20,
                compactHeight: 38,
                wallInset: 8
            ),
            10
        )
    }

    func testRestingHeightStillMatchesPhysicalNotchExactly() {
        XCTAssertEqual(
            IslandAppearanceConstraints.resolvedRestingHeight(
                preferredHeight: nil,
                physicalNotchHeight: 38
            ),
            38
        )
        XCTAssertEqual(
            IslandAppearanceConstraints.resolvedRestingHeight(
                preferredHeight: 30,
                physicalNotchHeight: 38
            ),
            38
        )
    }

    func testAutomaticRestingHeightUsesMeasuredDefaultBeforeThirtyTwoPointFallback() {
        XCTAssertEqual(
            IslandAppearanceConstraints.resolvedRestingHeight(
                preferredHeight: nil,
                physicalNotchHeight: 0,
                defaultIslandHeight: 24
            ),
            24
        )
        XCTAssertEqual(
            IslandAppearanceConstraints.resolvedRestingHeight(
                preferredHeight: nil,
                physicalNotchHeight: 0,
                defaultIslandHeight: 0
            ),
            32
        )
    }

    func testRestingBodyWidthMatchesPhysicalNotchWidth() {
        XCTAssertEqual(
            IslandAppearanceConstraints.automaticRestingBodyWidth(physicalNotchWidth: 0),
            200
        )
        XCTAssertEqual(
            IslandAppearanceConstraints.automaticRestingBodyWidth(physicalNotchWidth: 198),
            198
        )
        XCTAssertEqual(
            IslandAppearanceConstraints.automaticRestingBodyWidth(physicalNotchWidth: 220),
            220
        )
    }

    func testWidthRangesUseBodyWidthsWithoutShoulders() {
        XCTAssertEqual(IslandAppearanceConstraints.defaultRestingHorizontalInset, 0)
        XCTAssertEqual(IslandAppearanceConstraints.fallbackNotchWidth, 200)
        XCTAssertEqual(IslandAppearanceConstraints.defaultRestingWidth, 200)
        // 隐藏态可调最大宽度 = 灵动态默认/最小宽度 = 物理刘海宽 + 2×(耳朵 24 + 外 4 + 内 4)；
        // 无刘海时以兜底刘海宽 200 计得 264。
        let noNotchDefaultWidth = IslandAppearanceConstraints.defaultCompactBodyWidth(
            physicalNotchWidth: 0
        )
        XCTAssertEqual(noNotchDefaultWidth, 264)
        XCTAssertEqual(IslandAppearanceConstraints.maximumRestingWidth, noNotchDefaultWidth)
        XCTAssertEqual(IslandAppearanceConstraints.minimumCompactWidth, noNotchDefaultWidth)
        XCTAssertEqual(IslandAppearanceConstraints.defaultCompactWidth, noNotchDefaultWidth)
        XCTAssertEqual(
            IslandAppearanceConstraints.maximumCompactWidth,
            CompactIslandTier.secondTierMinimumWidth
        )
    }

    func testUnifiedIslandHeightDrivesRestingAndCompactLayout() {
        let height: CGFloat = 44
        let hiddenSize = CGSize(width: 220, height: 38)
        let restingMetrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: hiddenSize,
            notchPhysicalWidth: 220,
            expandedModuleCount: 1,
            showsCompactContent: false,
            preferredRestingHeight: height
        )
        let compactMetrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: hiddenSize,
            notchPhysicalWidth: 220,
            expandedModuleCount: 1,
            preferredRestingHeight: height
        )

        XCTAssertEqual(restingMetrics.hiddenHeight, 44)
        XCTAssertEqual(compactMetrics.hiddenHeight, 44)
    }

    func testLegacyEarHeightOverrideNoLongerDrivesIslandHeight() {
        let suiteName = "IslandAppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(22, forKey: "appearance.island.customEarHeight")

        let settings = IslandAppearanceSettings(defaults: defaults)
        XCTAssertNil(settings.customRestingHeight)
        XCTAssertTrue(settings.usesAutomaticRestingHeight)
    }

    func testLegacyFallbackCompactWidthMigratesToAutomatic() {
        let suiteName = "IslandAppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // 旧版本会把「无实测刘海」兜底宽度 264 写进设置，带刘海机器因此被顶到 264。
        defaults.set(264, forKey: "appearance.island.customIslandWidth")

        let settings = IslandAppearanceSettings(defaults: defaults)

        XCTAssertNil(settings.customCompactWidth)
        XCTAssertTrue(settings.usesAutomaticCompactWidth)
        XCTAssertNil(defaults.object(forKey: "appearance.island.customIslandWidth"))
    }

    func testCompactWidthBelowLegacyMinimumIsPreserved() {
        let suiteName = "IslandAppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // 带刘海机器上 249（185+64）是合法宽度，不应被旧下限 264 顶大。
        defaults.set(249, forKey: "appearance.island.customIslandWidth")

        let settings = IslandAppearanceSettings(defaults: defaults)

        XCTAssertEqual(settings.customCompactWidth, 249)
        XCTAssertFalse(settings.usesAutomaticCompactWidth)
    }

    func testLegacyFallbackCompactWidthMigrationRunsOnce() {
        let suiteName = "IslandAppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        _ = IslandAppearanceSettings(defaults: defaults)

        // 迁移已跑过：用户之后主动选 264 应被保留，而不是反复清掉。
        defaults.set(264, forKey: "appearance.island.customIslandWidth")
        let settings = IslandAppearanceSettings(defaults: defaults)

        XCTAssertEqual(settings.customCompactWidth, 264)
    }

    func testEarHeightSliderRangeMapsToIslandHeight() {
        let suiteName = "IslandAppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = IslandAppearanceSettings(defaults: defaults)

        // 耳朵独立于岛高，范围 12–36。
        settings.setCustomEarHeight(12)
        XCTAssertEqual(settings.resolvedEarHeight(), 12)

        settings.setCustomEarHeight(36)
        XCTAssertEqual(settings.resolvedEarHeight(), 36)
    }

    func testRaisingHiddenHeightDoesNotGrowEar() {
        let suiteName = "IslandAppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = IslandAppearanceSettings(defaults: defaults)
        settings.setCustomEarHeight(24)

        settings.setCustomRestingHeight(44, physicalNotchHeight: 32)
        XCTAssertEqual(settings.resolvedEarHeight(), 24)
        XCTAssertEqual(
            settings.resolvedIslandHeight(physicalNotchHeight: 32, defaultIslandHeight: 32),
            44
        )

        // 岛高不足时才抬到「耳朵 + 2×最小间距」。
        settings.setCustomRestingHeight(32, physicalNotchHeight: 32)
        XCTAssertEqual(settings.resolvedEarHeight(), 24)
        XCTAssertEqual(
            settings.resolvedIslandHeight(physicalNotchHeight: 32, defaultIslandHeight: 32),
            32
        )
        settings.setCustomEarHeight(36)
        XCTAssertEqual(
            settings.resolvedIslandHeight(physicalNotchHeight: 32, defaultIslandHeight: 32),
            38
        )
    }

    func testCompactVerticalInsetDrivesSharedIslandHeight() {
        let suiteName = "IslandAppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = IslandAppearanceSettings(defaults: defaults)
        settings.setCustomEarHeight(24)

        // 岛高 = 耳朵 + 2×间距，且写回隐藏态共用高度。
        settings.setCompactVerticalInset(8, physicalNotchHeight: 32)
        XCTAssertEqual(
            settings.resolvedIslandHeight(physicalNotchHeight: 32, defaultIslandHeight: 32),
            40,
            accuracy: 0.001
        )

        settings.setCompactVerticalInset(12, physicalNotchHeight: 32)
        XCTAssertEqual(
            settings.resolvedIslandHeight(physicalNotchHeight: 32, defaultIslandHeight: 32),
            48,
            accuracy: 0.001
        )
        XCTAssertEqual(
            settings.resolvedCompactVerticalInset(islandHeight: 48),
            12,
            accuracy: 0.001
        )
    }

    func testCompactVerticalInsetRangeNarrowsAsEarGrows() {
        let suiteName = "IslandAppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = IslandAppearanceSettings(defaults: defaults)

        settings.setCustomEarHeight(24)
        XCTAssertEqual(
            settings.compactVerticalInsetRange(physicalNotchHeight: 32).lowerBound,
            4,
            accuracy: 0.001
        )
        XCTAssertEqual(
            settings.compactVerticalInsetRange(physicalNotchHeight: 32).upperBound,
            12,
            accuracy: 0.001
        )

        settings.setCustomEarHeight(36)
        XCTAssertEqual(
            settings.compactVerticalInsetRange(physicalNotchHeight: 32).lowerBound,
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            settings.compactVerticalInsetRange(physicalNotchHeight: 32).upperBound,
            6,
            accuracy: 0.001
        )

        settings.setCustomEarHeight(12)
        XCTAssertEqual(
            settings.compactVerticalInsetRange(physicalNotchHeight: 32).lowerBound,
            10,
            accuracy: 0.001
        )
        XCTAssertEqual(
            settings.compactVerticalInsetRange(physicalNotchHeight: 32).upperBound,
            18,
            accuracy: 0.001
        )
    }

    func testCompactOuterInsetPersistsClampsAndResets() {
        let suiteName = "IslandAppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = IslandAppearanceSettings(defaults: defaults)
        XCTAssertEqual(
            settings.resolvedCompactOuterInset(),
            IslandAppearanceConstraints.defaultCompactOuterInset,
            accuracy: 0.001
        )

        settings.customCompactOuterInset = 9
        let restored = IslandAppearanceSettings(defaults: defaults)
        XCTAssertEqual(restored.customCompactOuterInset, 9)
        XCTAssertEqual(restored.resolvedCompactOuterInset(), 9, accuracy: 0.001)
        XCTAssertFalse(restored.usesAutomaticCompactLayout)

        restored.resetCompactToAutomatic()
        XCTAssertEqual(
            restored.resolvedCompactOuterInset(),
            IslandAppearanceConstraints.defaultCompactOuterInset,
            accuracy: 0.001
        )
        XCTAssertTrue(restored.usesAutomaticCompactLayout)
    }

    func testCompactOuterInsetWidensCompactIsland() {
        func islandWidth(outerInset: CGFloat) -> CGFloat {
            ResolvedCompactIslandLayout.resolve(
                contentHeight: IslandAppearanceConstraints.defaultCompactHeight,
                minimumIslandHeight: 32,
                notchPhysicalWidth: 185,
                restingBodyWidth: 249,
                preferredCompactOuterInset: outerInset
            ).islandWidth
        }

        XCTAssertGreaterThan(islandWidth(outerInset: 9), islandWidth(outerInset: 4))
        XCTAssertEqual(islandWidth(outerInset: 4), 285, accuracy: 0.001)
    }

    func testRestingAppearancePersistsSeparatelyFromCompactLayout() {
        let suiteName = "IslandAppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = IslandAppearanceSettings(defaults: defaults)
        settings.setCustomRestingHeight(44, physicalNotchHeight: 38)
        settings.setCustomRestingWidth(270, physicalNotchWidth: 220, restingHeight: 44)

        let restored = IslandAppearanceSettings(defaults: defaults)
        XCTAssertEqual(restored.customRestingHeight, 44)
        XCTAssertEqual(restored.customRestingWidth, 270)
        XCTAssertFalse(restored.usesAutomaticRestingLayout)
        XCTAssertTrue(restored.usesAutomaticCompactLayout)

        restored.resetRestingToAutomatic()
        XCTAssertTrue(restored.usesAutomaticRestingLayout)
        XCTAssertNil(defaults.object(forKey: "appearance.island.compact.customHeight"))
        XCTAssertNil(defaults.object(forKey: "appearance.island.compact.customWidth"))
    }

    func testAdditionalAppearanceValuesPersistAndResetTogether() {
        let suiteName = "IslandAppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = IslandAppearanceSettings(defaults: defaults)
        settings.customCompactWidth = 500

        let restored = IslandAppearanceSettings(defaults: defaults)
        XCTAssertEqual(restored.customCompactWidth, 345)
        XCTAssertFalse(restored.usesAutomaticLayout)

        restored.resetAllToAutomatic()
        XCTAssertTrue(restored.usesAutomaticLayout)
        XCTAssertNil(defaults.object(forKey: "appearance.island.customIslandWidth"))
    }

    func testVerticalInsetClampsToRangeAndFitsIslandHeight() {
        XCTAssertEqual(
            IslandAppearanceConstraints.resolvedCompactVerticalInset(
                preferred: 20,
                islandHeight: 24
            ),
            6
        )
        XCTAssertEqual(
            IslandAppearanceConstraints.resolvedCompactVerticalInset(
                preferred: 1,
                islandHeight: 38
            ),
            1
        )
        XCTAssertEqual(
            IslandAppearanceConstraints.resolvedCompactVerticalInset(
                preferred: nil,
                islandHeight: 32
            ),
            4
        )
    }
}

@MainActor
final class IslandNotificationSettingsTests: XCTestCase {
    func testNotificationSettingsDefaultToEnabledAndPersistIndependently() {
        let suiteName = "IslandNotificationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = IslandNotificationSettings(defaults: defaults)
        XCTAssertEqual(settings.enabledNotificationCount, 6)

        settings.isPowerStatusEnabled = false
        settings.isSongChangeEnabled = false
        settings.isAudioOutputChangeEnabled = false

        let restored = IslandNotificationSettings(defaults: defaults)
        XCTAssertFalse(restored.isPowerStatusEnabled)
        XCTAssertTrue(restored.isBluetoothConnectionEnabled)
        XCTAssertFalse(restored.isSongChangeEnabled)
        XCTAssertFalse(restored.isAudioOutputChangeEnabled)
        XCTAssertTrue(restored.isVolumeAdjustmentEnabled)
        XCTAssertTrue(restored.isBrightnessAdjustmentEnabled)
        XCTAssertEqual(restored.enabledNotificationCount, 3)
    }

    func testVolumeBarColorSettingsDefaultToStandardWhite() {
        let settings = IslandNotificationSettings(defaults: nil)

        XCTAssertEqual(settings.volumeBarColorStyle, .standard)
        XCTAssertEqual(settings.volumeBarCustomColor, .default)
        XCTAssertFalse(settings.isVolumeBarCustomGradientEnabled)
        XCTAssertEqual(settings.volumeBarCustomGradientEndColor, .default)
        XCTAssertTrue(settings.usesDefaultValues)
    }

    func testVolumeBarColorSettingsPersistCustomConfigurationAcrossInstances() {
        let suiteName = "IslandNotificationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = IslandNotificationSettings(defaults: defaults)
        settings.volumeBarColorStyle = .custom
        settings.volumeBarCustomColor = VolumeBarColor(red: 0.1, green: 0.2, blue: 0.3)
        settings.isVolumeBarCustomGradientEnabled = true
        settings.volumeBarCustomGradientEndColor = VolumeBarColor(red: 0.8, green: 0.7, blue: 0.6)

        let restored = IslandNotificationSettings(defaults: defaults)
        XCTAssertEqual(restored.volumeBarColorStyle, .custom)
        XCTAssertEqual(restored.volumeBarCustomColor, VolumeBarColor(red: 0.1, green: 0.2, blue: 0.3))
        XCTAssertTrue(restored.isVolumeBarCustomGradientEnabled)
        XCTAssertEqual(
            restored.volumeBarCustomGradientEndColor,
            VolumeBarColor(red: 0.8, green: 0.7, blue: 0.6)
        )
        XCTAssertFalse(restored.usesDefaultValues)
    }

    func testResetToDefaultRestoresVolumeBarColorSettings() {
        let suiteName = "IslandNotificationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = IslandNotificationSettings(defaults: defaults)
        settings.volumeBarColorStyle = .gradient
        settings.volumeBarCustomColor = VolumeBarColor(red: 0.4, green: 0.5, blue: 0.6)
        settings.isVolumeBarCustomGradientEnabled = true
        settings.volumeBarCustomGradientEndColor = VolumeBarColor(red: 0.2, green: 0.3, blue: 0.4)

        settings.resetToDefault()

        XCTAssertTrue(settings.usesDefaultValues)
        XCTAssertEqual(settings.volumeBarColorStyle, .standard)
        XCTAssertEqual(settings.volumeBarCustomColor, .default)
        XCTAssertFalse(settings.isVolumeBarCustomGradientEnabled)
        XCTAssertEqual(settings.volumeBarCustomGradientEndColor, .default)
    }
}

final class NotchWindowLayoutTests: XCTestCase {
    func testCompactAndExpandedFramesKeepExactlyTheSameHorizontalCenter() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let compactFrame = NotchWindowLayout.pixelAlignedTopCenteredFrame(
            in: screenFrame,
            size: CGSize(width: 394.3, height: 84.2),
            backingScaleFactor: 2
        )
        let expandedFrame = NotchWindowLayout.pixelAlignedTopCenteredFrame(
            in: screenFrame,
            size: CGSize(width: 600.1, height: 290.4),
            backingScaleFactor: 2
        )

        XCTAssertEqual(compactFrame.midX, screenFrame.midX, accuracy: 0.0001)
        XCTAssertEqual(expandedFrame.midX, screenFrame.midX, accuracy: 0.0001)
        XCTAssertEqual(compactFrame.maxY, screenFrame.maxY, accuracy: 0.0001)
        XCTAssertEqual(expandedFrame.maxY, screenFrame.maxY, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(compactFrame.width, 394.3)
        XCTAssertGreaterThanOrEqual(expandedFrame.width, 600.1)
    }

    func testTopCenteredFramePlacesBothHorizontalEdgesOnRetinaPixelBoundaries() {
        let frame = NotchWindowLayout.pixelAlignedTopCenteredFrame(
            in: CGRect(x: -1512, y: 0, width: 1512, height: 982),
            size: CGSize(width: 394.3, height: 84.2),
            backingScaleFactor: 2
        )

        XCTAssertEqual((frame.minX * 2).rounded(), frame.minX * 2, accuracy: 0.0001)
        XCTAssertEqual((frame.maxX * 2).rounded(), frame.maxX * 2, accuracy: 0.0001)
        XCTAssertEqual((frame.maxY * 2).rounded(), frame.maxY * 2, accuracy: 0.0001)
    }

    func testPixelAlignedFrameCanBeWiderThanRequestedSize() {
        let requestedSize = CGSize(width: 394.3, height: 84.2)
        let frame = NotchWindowLayout.pixelAlignedTopCenteredFrame(
            in: CGRect(x: 0, y: 0, width: 1512, height: 982),
            size: requestedSize,
            backingScaleFactor: 2
        )

        XCTAssertGreaterThan(frame.width, requestedSize.width)
        XCTAssertEqual(frame.midX, 756, accuracy: 0.0001)
    }

    func testFrameComparisonDoesNotIgnoreAVisibleRetinaPixelShift() {
        let current = CGRect(x: 456, y: 692, width: 600, height: 290)
        let shifted = CGRect(x: 456.5, y: 692, width: 600, height: 290)

        XCTAssertTrue(
            NotchWindowLayout.framesDiffer(
                current,
                shifted,
                backingScaleFactor: 2
            )
        )
    }

    func testExpandedReservationReplacesOnlyIslandCanvasHeight() {
        let size = NotchWindowLayout.sizeByReplacingIslandCanvas(
            in: CGSize(width: 380, height: 126),
            currentIslandCanvasSize: CGSize(width: 380, height: 74),
            replacementIslandCanvasSize: CGSize(width: 600, height: 290)
        )

        XCTAssertEqual(size, CGSize(width: 600, height: 342))
    }

    func testExpandedReservationDoesNotCreateNegativeSupplementalHeight() {
        let size = NotchWindowLayout.sizeByReplacingIslandCanvas(
            in: CGSize(width: 380, height: 60),
            currentIslandCanvasSize: CGSize(width: 380, height: 74),
            replacementIslandCanvasSize: CGSize(width: 600, height: 290)
        )

        XCTAssertEqual(size, CGSize(width: 600, height: 290))
    }

    func testReservationPreventsAnimatedMeasurementsFromShrinkingWindow() {
        let size = NotchWindowLayout.maximum(
            CGSize(width: 520, height: 210),
            CGSize(width: 600, height: 290)
        )

        XCTAssertEqual(size, CGSize(width: 600, height: 290))
    }
}

final class IslandCompactModuleMotionTests: XCTestCase {
    func testStandardConfigurationUsesSharedAsymmetricScaleAndTiming() {
        let configuration = IslandCompactModuleTransitionConfiguration.resolved(
            reduceMotion: false
        )

        XCTAssertEqual(configuration.insertionScale, 0.94)
        XCTAssertEqual(configuration.removalScale, 0.97)
        XCTAssertEqual(configuration.enterDuration, 0.17)
        XCTAssertEqual(configuration.enterDelay, 0.03)
        XCTAssertEqual(configuration.exitDuration, 0.11)
    }

    func testReducedMotionConfigurationIsOpacityOnlyWithoutDelay() {
        let configuration = IslandCompactModuleTransitionConfiguration.resolved(
            reduceMotion: true
        )

        XCTAssertNil(configuration.insertionScale)
        XCTAssertNil(configuration.removalScale)
        XCTAssertEqual(configuration.enterDuration, 0.14)
        XCTAssertEqual(configuration.enterDelay, 0)
        XCTAssertEqual(configuration.exitDuration, 0.14)
    }
}

final class IslandHoverMotionTokenTests: XCTestCase {
    func testHoverMotionRemainsSubtle() {
        XCTAssertEqual(IslandLayoutToken.hoverExpansion, CGSize(width: 10, height: 2))
        XCTAssertLessThanOrEqual(IslandLayoutToken.hoverSideVerticalOffset, 2)
        XCTAssertGreaterThan(IslandLayoutToken.hoverContentScale, 1)
        XCTAssertLessThanOrEqual(IslandLayoutToken.hoverContentScale, 1.006)
    }
}

final class IslandHoverCoordinatorTests: XCTestCase {
    func testEnterEmitsImmediately() {
        var coordinator = IslandHoverCoordinator()

        let actions = coordinator.sample(isInside: true, at: 0)

        XCTAssertEqual(actions.emission, true)
        XCTAssertNil(actions.exitValidationDelay)
    }

    func testTransientExitIsCancelledWithoutEmission() {
        var coordinator = IslandHoverCoordinator()
        _ = coordinator.sample(isInside: true, at: 0)

        let exitActions = coordinator.sample(isInside: false, at: 0.01)
        let reentryActions = coordinator.sample(isInside: true, at: 0.05)

        XCTAssertEqual(
            exitActions.exitValidationDelay ?? -1,
            IslandHoverCoordinator.exitDebounceInterval,
            accuracy: 0.0001
        )
        XCTAssertNil(exitActions.emission)
        XCTAssertNil(reentryActions.emission)
        XCTAssertTrue(reentryActions.cancelsExitValidation)
        XCTAssertNil(coordinator.pendingExitDeadline)
        XCTAssertTrue(coordinator.publishedIsInside)
    }

    func testSustainedExitUsesFixedDeadlineAndEmitsOnce() {
        var coordinator = IslandHoverCoordinator()
        _ = coordinator.sample(isInside: true, at: 0)
        let firstExit = coordinator.sample(isInside: false, at: 0.01)
        let deadline = coordinator.pendingExitDeadline
        let repeatedExit = coordinator.sample(isInside: false, at: 0.04)
        let confirmedExit = coordinator.sample(
            isInside: false,
            at: 0.085,
            validatesPendingExit: true
        )
        let laterExit = coordinator.sample(isInside: false, at: 0.2)

        XCTAssertNotNil(firstExit.exitValidationDelay)
        XCTAssertEqual(coordinator.pendingExitDeadline, nil)
        XCTAssertEqual(deadline ?? -1, 0.085, accuracy: 0.0001)
        XCTAssertEqual(repeatedExit, .init())
        XCTAssertEqual(confirmedExit.emission, false)
        XCTAssertNil(laterExit.emission)
        XCTAssertFalse(coordinator.publishedIsInside)
    }

    /// 回归测试：几何变化驱动的刷新（如收起缩窗）不走 75ms 退出防抖。
    /// 否则收起完成后的 compact 激活会读到过期的 isHovered=true，
    /// 先假性膨胀、再被迟到的退出事件缩回——悬停在附近的岛会抖一下。
    func testGeometryDrivenExitEmitsImmediately() {
        var coordinator = IslandHoverCoordinator()
        _ = coordinator.sample(isInside: true, at: 0)

        let exitActions = coordinator.sample(
            isInside: false,
            at: 0.01,
            isGeometryDriven: true
        )

        XCTAssertEqual(exitActions.emission, false)
        XCTAssertTrue(exitActions.cancelsExitValidation)
        XCTAssertNil(coordinator.pendingExitDeadline)
        XCTAssertFalse(coordinator.publishedIsInside)
    }

    /// 几何驱动的立即退出之后，再次悬停仍能正常立即入场。
    func testGeometryDrivenExitThenReenterEmitsImmediately() {
        var coordinator = IslandHoverCoordinator()
        _ = coordinator.sample(isInside: true, at: 0)
        _ = coordinator.sample(isInside: false, at: 0.01, isGeometryDriven: true)

        let reentry = coordinator.sample(isInside: true, at: 0.02)

        XCTAssertEqual(reentry.emission, true)
        XCTAssertTrue(coordinator.publishedIsInside)
    }

    func testExitValidationInsideKeepsHoverPublished() {
        var coordinator = IslandHoverCoordinator()
        _ = coordinator.sample(isInside: true, at: 0)
        _ = coordinator.sample(isInside: false, at: 0.01)

        let actions = coordinator.sample(
            isInside: true,
            at: 0.085,
            validatesPendingExit: true
        )

        XCTAssertNil(actions.emission)
        XCTAssertTrue(actions.cancelsExitValidation)
        XCTAssertTrue(coordinator.publishedIsInside)
    }

    func testRefreshRequestsUseLeadingAndFixedTrailingThrottle() {
        var coordinator = IslandHoverCoordinator()

        XCTAssertEqual(coordinator.requestRefresh(at: 0), .refreshNow)
        XCTAssertEqual(
            coordinator.requestRefresh(at: 0.004),
            .scheduleTrailing(after: 0.012)
        )
        XCTAssertEqual(coordinator.requestRefresh(at: 0.008), .none)
        XCTAssertEqual(coordinator.requestRefresh(at: 0.015), .none)

        coordinator.trailingRefreshFired(at: 0.016)
        XCTAssertEqual(
            coordinator.requestRefresh(at: 0.02),
            .scheduleTrailing(after: 0.012)
        )
    }

    func testRefreshAfterThrottleWindowRunsImmediately() {
        var coordinator = IslandHoverCoordinator()
        XCTAssertEqual(coordinator.requestRefresh(at: 0), .refreshNow)
        XCTAssertEqual(coordinator.requestRefresh(at: 0.02), .refreshNow)
    }
}

final class IslandHoverHitTestingTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 300, height: 72)
    private let windowFrame = CGRect(x: 606, y: 910, width: 300, height: 72)

    func testPointInsideTrackingBoundsIsHovered() {
        XCTAssertTrue(
            IslandHoverHitTesting.contains(
                pointInView: CGPoint(x: 150, y: 36),
                bounds: bounds,
                pointerScreenPoint: CGPoint(x: 756, y: 946),
                windowFrame: windowFrame,
                backingScaleFactor: 2
            )
        )
    }

    func testExactWindowTopEdgeIsHoveredWhenHorizontallyInside() {
        XCTAssertTrue(
            IslandHoverHitTesting.contains(
                pointInView: CGPoint(x: 150, y: bounds.maxY),
                bounds: bounds,
                pointerScreenPoint: CGPoint(x: 756, y: windowFrame.maxY),
                windowFrame: windowFrame,
                backingScaleFactor: 2
            )
        )
    }

    func testOneRetinaPixelBelowWindowTopIsStillHovered() {
        XCTAssertTrue(
            IslandHoverHitTesting.contains(
                pointInView: CGPoint(x: 150, y: bounds.maxY),
                bounds: bounds,
                pointerScreenPoint: CGPoint(x: 756, y: windowFrame.maxY - 0.5),
                windowFrame: windowFrame,
                backingScaleFactor: 2
            )
        )
    }

    func testTopEdgeOutsideTrackingWidthIsNotHovered() {
        XCTAssertFalse(
            IslandHoverHitTesting.contains(
                pointInView: CGPoint(x: bounds.maxX + 1, y: bounds.maxY),
                bounds: bounds,
                pointerScreenPoint: CGPoint(x: windowFrame.maxX + 1, y: windowFrame.maxY),
                windowFrame: windowFrame,
                backingScaleFactor: 2
            )
        )
    }

    func testPointOutsideBoundsAndAwayFromTopIsNotHovered() {
        XCTAssertFalse(
            IslandHoverHitTesting.contains(
                pointInView: CGPoint(x: 150, y: bounds.maxY + 2),
                bounds: bounds,
                pointerScreenPoint: CGPoint(x: 756, y: windowFrame.maxY - 2),
                windowFrame: windowFrame,
                backingScaleFactor: 2
            )
        )
    }

    func testTransparentShoulderIsNotHovered() {
        XCTAssertFalse(
            IslandHoverHitTesting.contains(
                pointInView: CGPoint(x: 5, y: 36),
                bounds: bounds,
                pointerScreenPoint: CGPoint(x: 611, y: 946),
                windowFrame: windowFrame,
                backingScaleFactor: 2,
                shapePath: compactShapePath()
            )
        )
    }

    func testTransparentShoulderAtWindowTopIsNotHovered() {
        XCTAssertFalse(
            IslandHoverHitTesting.contains(
                pointInView: CGPoint(x: 5, y: bounds.maxY),
                bounds: bounds,
                pointerScreenPoint: CGPoint(x: 611, y: windowFrame.maxY),
                windowFrame: windowFrame,
                backingScaleFactor: 2,
                shapePath: compactShapePath()
            )
        )
    }

    func testVisibleBodyBesideShoulderIsStillHovered() {
        XCTAssertTrue(
            IslandHoverHitTesting.contains(
                pointInView: CGPoint(x: 19, y: 36),
                bounds: bounds,
                pointerScreenPoint: CGPoint(x: 625, y: 946),
                windowFrame: windowFrame,
                backingScaleFactor: 2,
                shapePath: compactShapePath()
            )
        )
    }

    func testVisibleShoulderLipAtWindowTopIsHovered() {
        XCTAssertTrue(
            IslandHoverHitTesting.contains(
                pointInView: CGPoint(x: 13, y: bounds.maxY),
                bounds: bounds,
                pointerScreenPoint: CGPoint(x: 619, y: windowFrame.maxY),
                windowFrame: windowFrame,
                backingScaleFactor: 2,
                shapePath: compactShapePath()
            )
        )
    }

    private func compactShapePath() -> CGPath {
        IslandHoverHitTesting.shapePath(
            in: bounds,
            state: .hidden,
            metrics: .default,
            expansionProgress: 0,
            compactMorphProgress: 1,
            isFlipped: false
        )
    }
}

final class IslandHoverInputTests: XCTestCase {
    func testPressedMouseButtonSuppressesHoverEligibility() {
        XCTAssertFalse(
            IslandHoverInput.isEligible(
                isSpatiallyInside: true,
                pressedMouseButtons: 1
            )
        )
    }

    func testStationaryPointerInsideRemainsHoverEligible() {
        XCTAssertTrue(
            IslandHoverInput.isEligible(
                isSpatiallyInside: true,
                pressedMouseButtons: 0
            )
        )
    }
}

final class IslandFileDragApproachSessionTests: XCTestCase {
    func testStaleFilePasteboardDoesNotTurnWindowDragIntoFileDrag() {
        var session = IslandFileDragApproachSession()
        session.beginMouseSequence(pasteboardChangeCount: 12)

        XCTAssertFalse(
            session.isCurrentFileDrag(
                pasteboardChangeCount: 12,
                hasFileURLs: true
            )
        )
    }

    func testNewFilePasteboardInCurrentMouseSequenceIsRecognized() {
        var session = IslandFileDragApproachSession()
        session.beginMouseSequence(pasteboardChangeCount: 12)

        XCTAssertTrue(
            session.isCurrentFileDrag(
                pasteboardChangeCount: 13,
                hasFileURLs: true
            )
        )
    }

    func testMouseUpEndsFileDragRecognition() {
        var session = IslandFileDragApproachSession()
        session.beginMouseSequence(pasteboardChangeCount: 12)
        session.endMouseSequence()

        XCTAssertFalse(
            session.isCurrentFileDrag(
                pasteboardChangeCount: 13,
                hasFileURLs: true
            )
        )
    }
}

@MainActor
final class NotchWindowInteractionTests: XCTestCase {
    func testWindowAcceptsMouseMovedEvents() {
        let window = NotchWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 72))
        defer { window.close() }

        XCTAssertTrue(window.acceptsMouseMovedEvents)
        XCTAssertTrue(window.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertEqual(window.level, .screenSaver)
        XCTAssertEqual(window.sharingType, .none)
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.collectionBehavior.contains(.stationary))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllApplications))
        XCTAssertFalse(window.collectionBehavior.contains(.moveToActiveSpace))
    }

    func testWindowScreenCaptureVisibilityCanBeChanged() {
        let window = NotchWindow(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 72),
            isHiddenInScreenCapture: false
        )
        defer { window.close() }

        XCTAssertEqual(window.sharingType, .readOnly)
        window.setHiddenInScreenCapture(true)
        XCTAssertEqual(window.sharingType, .none)
    }
}

final class IslandBackgroundPathTests: XCTestCase {
    func testDefaultMetricsMatchNotchBaseline() {
        let metrics = IslandBackgroundMetrics.default
        XCTAssertEqual(metrics.hiddenSize, CGSize(width: 300, height: 38))
        XCTAssertEqual(metrics.collapsedSize, CGSize(width: 300, height: 72))
        XCTAssertEqual(metrics.expandedSize, CGSize(width: 420, height: 176))
    }

    func testResolvedMetricsKeepThreeStateGrowthOrder() {
        let metrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 280, height: 38),
            notchPhysicalWidth: 220,
            expandedModuleCount: 3
        )

        XCTAssertGreaterThan(metrics.hiddenWidth, 220)
        XCTAssertLessThanOrEqual(metrics.hiddenWidth, 460)
        XCTAssertEqual(metrics.hiddenHeight, 38)
        XCTAssertGreaterThan(metrics.collapsedWidth, metrics.hiddenWidth)
        XCTAssertGreaterThan(metrics.expandedWidth, metrics.collapsedWidth)
        XCTAssertEqual(metrics.expandedWidth, IslandLayoutToken.expandedNowPageTotalWidth)
        XCTAssertEqual(metrics.expandedHeight, 176)
        XCTAssertGreaterThan(metrics.collapsedHeight, metrics.hiddenHeight)
        XCTAssertGreaterThan(metrics.expandedHeight, metrics.collapsedHeight)
    }

    func testNowPageExpandedHeightFollowsPerTabContentPreference() {
        let metrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 280, height: 38),
            notchPhysicalWidth: 220,
            expandedModuleCount: 0,
            preferredExpandedContentHeight: IslandLayoutToken.expandedNowPageContentHeight
        )
        XCTAssertEqual(metrics.expandedWidth, IslandLayoutToken.expandedNowPageTotalWidth)
        XCTAssertEqual(metrics.expandedHeight, 38 + IslandLayoutToken.expandedNowPageContentHeight + 8 + 8)
        XCTAssertGreaterThan(metrics.expandedHeight, metrics.hiddenHeight)
        XCTAssertGreaterThanOrEqual(
            metrics.expandedHeight,
            38 + IslandLayoutToken.expandedContentHeight
                + IslandLayoutToken.expandedContentTopInset
                + IslandLayoutToken.expandedContentVerticalInset
        )
    }

    func testMetricsInterpolationIncludesEveryNumericFieldAndClampsProgress() {
        let resting = IslandBackgroundMetrics(
            hiddenWidth: 240,
            hiddenHeight: 38,
            collapsedWidth: 312,
            collapsedHeight: 72,
            expandedWidth: 520,
            expandedHeight: 250,
            topShoulderWidthRatio: 0.1,
            topShoulderDepthRatio: 0.3,
            hiddenTopCornerRatio: 0.4
        )
        let dynamic = IslandBackgroundMetrics(
            hiddenWidth: 400,
            hiddenHeight: 46,
            collapsedWidth: 472,
            collapsedHeight: 80,
            expandedWidth: 560,
            expandedHeight: 270,
            topShoulderWidthRatio: 0.2,
            topShoulderDepthRatio: 0.5,
            hiddenTopCornerRatio: 0.6
        )

        XCTAssertEqual(
            IslandBackgroundMetrics.interpolated(from: resting, to: dynamic, progress: -1),
            resting
        )
        XCTAssertEqual(
            IslandBackgroundMetrics.interpolated(from: resting, to: dynamic, progress: 2),
            dynamic
        )

        let middle = IslandBackgroundMetrics.interpolated(
            from: resting,
            to: dynamic,
            progress: 0.5
        )
        XCTAssertEqual(middle.hiddenWidth, 320)
        XCTAssertEqual(middle.hiddenHeight, 42)
        XCTAssertEqual(middle.collapsedWidth, 392)
        XCTAssertEqual(middle.collapsedHeight, 76)
        XCTAssertEqual(middle.expandedWidth, 540)
        XCTAssertEqual(middle.expandedHeight, 260)
        XCTAssertEqual(middle.topShoulderWidthRatio, 0.15, accuracy: 0.0001)
        XCTAssertEqual(middle.topShoulderDepthRatio, 0.4, accuracy: 0.0001)
        XCTAssertEqual(middle.hiddenTopCornerRatio, 0.5, accuracy: 0.0001)
    }


    func testAutomaticCompactMetricsKeepIslandAtNotchHeightAndUseTwentyFourPointContent() {
        let shortMetrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 220, height: 32),
            notchPhysicalWidth: 220,
            expandedModuleCount: 1
        )
        let tallMetrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 220, height: 46),
            notchPhysicalWidth: 220,
            expandedModuleCount: 1
        )
        let fallbackMetrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 220, height: 0),
            notchPhysicalWidth: 220,
            expandedModuleCount: 1
        )

        XCTAssertEqual(shortMetrics.hiddenHeight, 32)
        XCTAssertEqual(tallMetrics.hiddenHeight, 46)
        XCTAssertEqual(fallbackMetrics.hiddenHeight, 32)
    }

    func testRestingMetricsUseResolvedMenuBarHeightWithoutPhysicalNotch() {
        let metrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 300, height: 24),
            notchPhysicalWidth: 0,
            expandedModuleCount: 1,
            showsCompactContent: false
        )

        XCTAssertEqual(metrics.hiddenHeight, 24)
    }

    func testCompactMetricsFollowDynamicSideBudgetForNarrowNotch() {
        let notchWidth: CGFloat = 180
        let height: CGFloat = 38
        let restingHeight = IslandAppearanceConstraints.resolvedRestingHeight(
            preferredHeight: nil,
            physicalNotchHeight: height
        )
        let restingWidth = IslandAppearanceConstraints.resolvedRestingWidth(
            preferredWidth: nil,
            physicalNotchWidth: notchWidth,
            restingHeight: restingHeight
        )
        let restingBodyWidth = restingWidth
        let metrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: notchWidth, height: height),
            notchPhysicalWidth: notchWidth,
            expandedModuleCount: 1
        )
        let layout = ResolvedCompactIslandLayout.resolve(
            contentHeight: IslandAppearanceConstraints.defaultCompactHeight,
            minimumIslandHeight: height,
            notchPhysicalWidth: notchWidth,
            restingBodyWidth: restingBodyWidth
        )

        XCTAssertEqual(metrics.hiddenWidth, layout.islandWidth, accuracy: 0.001)
        XCTAssertEqual(layout.outerInset, IslandAppearanceConstraints.defaultCompactOuterInset)
        XCTAssertEqual(
            layout.containerOuterInset,
            layout.wallInset + IslandAppearanceConstraints.defaultCompactOuterInset
        )
        XCTAssertLessThan(metrics.hiddenWidth, 360)
    }

    func testAutomaticCompactInsetsStayInsideIslandContainer() {
        let layout = ResolvedCompactIslandLayout.resolve(
            contentHeight: 38,
            notchPhysicalWidth: 220
        )

        XCTAssertEqual(layout.islandHeight, 46)
        XCTAssertEqual(layout.verticalInset, 4)
        XCTAssertEqual(layout.contentHeight, 38)
        XCTAssertGreaterThanOrEqual(
            layout.leadingContentSize.width,
            CompactIslandContentSpec.defaultSideContentWidth
        )
        XCTAssertEqual(layout.leadingContentSize.height, 38)
        XCTAssertEqual(layout.outerInset, IslandAppearanceConstraints.defaultCompactOuterInset)
        XCTAssertEqual(
            layout.containerOuterInset,
            layout.wallInset + IslandAppearanceConstraints.defaultCompactOuterInset
        )
        XCTAssertEqual(
            layout.islandWidth,
            layout.centerNotchWidth + layout.sideRegionWidth * 2,
            accuracy: 0.001
        )
        XCTAssertGreaterThanOrEqual(
            layout.bodyWidth,
            IslandAppearanceConstraints.defaultCompactWidth
        )
        XCTAssertEqual(layout.islandWidth, layout.bodyWidth + layout.shoulderWidth * 2, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(layout.innerGap, IslandAppearanceConstraints.minimumCompactInnerGap)
    }

    func testCompactFallbackWidthUsesConfiguredDefaultLength() {
        let layout = ResolvedCompactIslandLayout.resolve(
            contentHeight: 20,
            minimumIslandHeight: 26,
            notchPhysicalWidth: 0
        )

        XCTAssertEqual(layout.centerNotchWidth, IslandAppearanceConstraints.fallbackNotchWidth)
        XCTAssertGreaterThanOrEqual(
            layout.bodyWidth,
            IslandAppearanceConstraints.defaultCompactWidth
        )
        XCTAssertEqual(
            layout.islandWidth,
            layout.bodyWidth + layout.shoulderWidth * 2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            layout.islandWidth,
            layout.centerNotchWidth + layout.sideRegionWidth * 2,
            accuracy: 0.001
        )
        XCTAssertGreaterThanOrEqual(
            layout.leadingContentWidth,
            CompactIslandContentSpec.defaultSideContentWidth
        )
    }

    func testCompactLayoutAlwaysReservesDefaultPointContentBudget() {
        for notch in stride(from: CGFloat(0), through: 300, by: 20) {
            let layout = ResolvedCompactIslandLayout.resolve(
                contentHeight: 24,
                notchPhysicalWidth: notch
            )
            XCTAssertGreaterThanOrEqual(
                layout.leadingContentWidth,
                CompactIslandContentSpec.defaultSideContentWidth
            )
            XCTAssertGreaterThanOrEqual(
                layout.trailingContentWidth,
                CompactIslandContentSpec.defaultSideContentWidth
            )
            XCTAssertGreaterThanOrEqual(
                layout.innerGap,
                IslandAppearanceConstraints.minimumCompactInnerGap
            )
            XCTAssertEqual(
                layout.islandWidth,
                layout.centerNotchWidth + layout.sideRegionWidth * 2,
                accuracy: 0.001
            )
            XCTAssertEqual(
                layout.islandWidth,
                layout.bodyWidth + layout.shoulderWidth * 2,
                accuracy: 0.001
            )
        }
    }

    func testFallbackHiddenIslandSizeUsesConstraintDefaults() {
        let size = NotchPositioner.fallbackHiddenIslandSize

        XCTAssertEqual(size.height, NotchPositioner.fallbackHiddenHeight)
        XCTAssertEqual(size.width, IslandAppearanceConstraints.fallbackNotchWidth)
    }

    func testAutomaticFloatingCompactLayoutFitsMenuBarHeight() {
        let layout = ResolvedCompactIslandLayout.resolve(
            contentHeight: 24,
            minimumIslandHeight: 24,
            notchPhysicalWidth: 0,
            fitsAutomaticContentToMinimumHeight: true
        )

        XCTAssertEqual(layout.islandHeight, 24)
        XCTAssertEqual(layout.contentHeight, 22)
        XCTAssertEqual(layout.verticalInset, 1)
    }

    func testConfiguredFloatingCompactLayoutMayExceedMenuBarHeight() {
        let layout = ResolvedCompactIslandLayout.resolve(
            contentHeight: 24,
            minimumIslandHeight: 24,
            notchPhysicalWidth: 0,
            preferredCompactVerticalInset: 4
        )

        XCTAssertEqual(layout.islandHeight, 32)
        XCTAssertEqual(layout.contentHeight, 24)
        XCTAssertEqual(layout.verticalInset, 4)
    }

    func testCompactContentBelowNotchHeightKeepsIslandHeightAndExpandsInsets() {
        let layout = ResolvedCompactIslandLayout.resolve(
            contentHeight: IslandAppearanceConstraints.defaultCompactHeight,
            minimumIslandHeight: 38,
            notchPhysicalWidth: 220,
            preferredCompactVerticalInset: 1
        )

        XCTAssertEqual(layout.contentHeight, 24)
        XCTAssertEqual(layout.verticalInset, 7)
        XCTAssertEqual(layout.islandHeight, 38)
    }

    func testConfiguredInsetsArePreservedWhenTheyAlreadyCoverNotchHeight() {
        let layout = ResolvedCompactIslandLayout.resolve(
            contentHeight: 30,
            minimumIslandHeight: 38,
            notchPhysicalWidth: 220,
            preferredCompactVerticalInset: 5
        )

        XCTAssertEqual(layout.verticalInset, 5)
        XCTAssertEqual(layout.islandHeight, 40)
    }

    func testCompactLeadingEarAllowsWideStatusContent() {
        let height: CGFloat = 38
        let contentHeight = CompactIslandContentSpec.resolvedContentHeight(for: height)
        let leadingWidth = CompactIslandContentSpec.leadingContentWidth(forHeight: height)
        let trailingWidth = CompactIslandContentSpec.trailingContentWidth(forHeight: height)
        let outerInset = CompactIslandContentSpec.outerInset(
            forHeight: height,
            wallInset: NotchShapeSpec.insetMin
        )
        let sideRegionWidth = CompactIslandContentSpec.sideRegionWidth(
            forHeight: height,
            wallInset: NotchShapeSpec.insetMin
        )

        XCTAssertEqual(
            leadingWidth,
            contentHeight * CompactIslandContentSpec.leadingWidthHeightRatio
        )
        XCTAssertEqual(trailingWidth, contentHeight)
        XCTAssertEqual(
            sideRegionWidth,
            NotchShapeSpec.insetMin
                + outerInset
                + leadingWidth
                + CompactIslandContentSpec.innerGap,
            accuracy: 0.001
        )
    }

    func testCompactEarsUseDefaultPointWidth() {
        let height = IslandAppearanceConstraints.defaultCompactHeight

        XCTAssertEqual(
            CompactIslandContentSpec.leadingContentWidth(forHeight: height),
            CompactIslandContentSpec.defaultSideContentWidth
        )
        XCTAssertEqual(
            CompactIslandContentSpec.trailingContentWidth(forHeight: height),
            CompactIslandContentSpec.defaultSideContentWidth
        )
    }

    func testResolvedLayoutWidensWithContentHeightToPreserveInnerGap() {
        let compact = ResolvedCompactIslandLayout.resolve(
            contentHeight: 38,
            notchPhysicalWidth: 220
        )
        let tall = ResolvedCompactIslandLayout.resolve(
            contentHeight: 48,
            notchPhysicalWidth: 220
        )

        XCTAssertEqual(compact.centerNotchWidth, 220)
        XCTAssertEqual(tall.centerNotchWidth, 220)
        XCTAssertEqual(compact.islandWidth, compact.centerNotchWidth + compact.sideRegionWidth * 2, accuracy: 0.001)
        XCTAssertEqual(tall.islandWidth, tall.centerNotchWidth + tall.sideRegionWidth * 2, accuracy: 0.001)
        XCTAssertGreaterThan(tall.contentHeight, compact.contentHeight)
        XCTAssertGreaterThan(tall.leadingContentWidth, compact.leadingContentWidth)
        XCTAssertGreaterThan(tall.islandWidth, compact.islandWidth)
        XCTAssertEqual(compact.leadingContentWidth, compact.trailingContentWidth)
        XCTAssertEqual(tall.leadingContentWidth, tall.trailingContentWidth)
        XCTAssertGreaterThanOrEqual(compact.innerGap, IslandAppearanceConstraints.minimumCompactInnerGap)
        XCTAssertGreaterThanOrEqual(tall.innerGap, IslandAppearanceConstraints.minimumCompactInnerGap)
    }

    func testCustomWidthAndInsetsResolveIndependentlyWithoutMovingCenterNotch() {
        let layout = ResolvedCompactIslandLayout.resolve(
            contentHeight: 38,
            notchPhysicalWidth: 220,
            preferredCompactOuterInset: 10,
            preferredCompactVerticalInset: 7,
            preferredCompactWidth: 520
        )

        // 自定义宽度上限受灵动态最大主体宽度（二档 345）约束。
        XCTAssertEqual(
            layout.bodyWidth,
            IslandAppearanceConstraints.maximumCompactWidth,
            accuracy: 0.001
        )
        XCTAssertEqual(layout.centerNotchWidth, 220)
        XCTAssertEqual(layout.outerInset, 10)
        XCTAssertEqual(layout.verticalInset, 7)
        XCTAssertEqual(layout.contentHeight, 38)
        XCTAssertEqual(layout.islandHeight, 52)
        XCTAssertEqual(
            layout.innerGap,
            layout.sideRegionWidth - layout.containerOuterInset - layout.leadingContentWidth,
            accuracy: 0.001
        )
        XCTAssertGreaterThanOrEqual(layout.innerGap, IslandAppearanceConstraints.minimumCompactInnerGap)
    }

    func testCompactEarWidthUsesBodyWidthWithoutShoulders() {
        let layout = ResolvedCompactIslandLayout.resolve(
            contentHeight: 24,
            notchPhysicalWidth: 220,
            preferredCompactWidth: 520
        )

        // 二档（宽度 345）：耳朵随宽度变宽 =（主体宽 − 物理刘海 − 两侧间距×2）/ 2。
        let expectedEarWidth = (
            layout.bodyWidth
                - layout.centerNotchWidth
                - layout.outerInset * 2
                - IslandAppearanceConstraints.minimumCompactInnerGap * 2
        ) / 2
        XCTAssertEqual(layout.leadingContentWidth, expectedEarWidth, accuracy: 0.001)
        XCTAssertEqual(layout.trailingContentWidth, expectedEarWidth, accuracy: 0.001)
        XCTAssertGreaterThan(layout.leadingContentWidth, layout.contentHeight)
    }

    func testFirstTierKeepsSquareEarAndGrowsInnerGap() {
        let compact = ResolvedCompactIslandLayout.resolve(
            contentHeight: IslandAppearanceConstraints.defaultCompactHeight,
            notchPhysicalWidth: 220
        )
        let wide = ResolvedCompactIslandLayout.resolve(
            contentHeight: IslandAppearanceConstraints.defaultCompactHeight,
            notchPhysicalWidth: 220,
            preferredCompactWidth: 330
        )

        // 一档：宽度拉长时耳朵内容槽保持方形，多出的宽度全部变成与物理刘海之间的
        // 内侧间距，外侧间距不变。
        XCTAssertEqual(wide.leadingContentWidth, compact.leadingContentWidth, accuracy: 0.001)
        XCTAssertEqual(wide.leadingContentWidth, 24, accuracy: 0.001)
        XCTAssertEqual(wide.outerInset, compact.outerInset, accuracy: 0.001)
        XCTAssertGreaterThan(wide.innerGap, compact.innerGap)
        XCTAssertGreaterThan(wide.islandWidth, compact.islandWidth)
    }

    func testCompactEarWidthSubtractsConfiguredRestingBodyWidth() {
        let withResting = ResolvedCompactIslandLayout.resolve(
            contentHeight: 24,
            notchPhysicalWidth: 220,
            restingBodyWidth: 280,
            preferredCompactWidth: 520
        )
        let withoutResting = ResolvedCompactIslandLayout.resolve(
            contentHeight: 24,
            notchPhysicalWidth: 220,
            preferredCompactWidth: 520
        )

        // restingBodyWidth 不再参与耳朵尺寸推导。
        XCTAssertEqual(
            withResting.leadingContentWidth,
            withoutResting.leadingContentWidth,
            accuracy: 0.001
        )
    }

    func testTooShortCustomWidthClampsToFixedDynamicMinimum() {
        let layout = ResolvedCompactIslandLayout.resolve(
            contentHeight: 48,
            notchPhysicalWidth: 220,
            preferredCompactOuterInset: 10,
            preferredCompactWidth: 270
        )

        // 过短的自定义宽度会被抬到该刘海宽下的默认主体宽度（刘海 + 2×侧预算）之上。
        let minimumBodyWidth = IslandAppearanceConstraints.defaultCompactBodyWidth(
            physicalNotchWidth: 220
        )
        XCTAssertGreaterThanOrEqual(layout.bodyWidth, minimumBodyWidth)
        XCTAssertGreaterThan(layout.bodyWidth, 270)
        XCTAssertEqual(layout.islandWidth, layout.centerNotchWidth + layout.sideRegionWidth * 2, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(layout.innerGap, IslandAppearanceConstraints.minimumCompactInnerGap)
    }

    func testSecondTierWidthUsesExactRecommendedBodyWidth() {
        let layout = ResolvedCompactIslandLayout.resolve(
            contentHeight: 48,
            notchPhysicalWidth: 220,
            preferredCompactOuterInset: 10,
            preferredCompactWidth: CompactIslandTier.secondTierMinimumWidth
        )

        XCTAssertEqual(
            layout.bodyWidth,
            CompactIslandTier.secondTierMinimumWidth,
            accuracy: 0.001
        )
        XCTAssertEqual(
            layout.islandWidth,
            layout.centerNotchWidth + layout.sideRegionWidth * 2,
            accuracy: 0.001
        )
    }

    func testCompactMetricsKeepWidthStableWhenRestingHeightChanges() {
        let hiddenSize = CGSize(width: 220, height: 38)
        let automaticMetrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: hiddenSize,
            notchPhysicalWidth: 220,
            expandedModuleCount: 1
        )
        let customMetrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: hiddenSize,
            notchPhysicalWidth: 220,
            expandedModuleCount: 1,
            preferredRestingHeight: 40
        )

        XCTAssertEqual(automaticMetrics.hiddenHeight, 38)
        XCTAssertEqual(customMetrics.hiddenHeight, 40)
        // 耳朵自动（默认 24）时，岛高变化只改耳朵上下间距，不改变岛宽。
        XCTAssertEqual(customMetrics.hiddenWidth, automaticMetrics.hiddenWidth, accuracy: 0.001)
    }

    func testRestingMetricsUseTheirOwnHeightAndWidthOverrides() {
        let metrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 220, height: 38),
            notchPhysicalWidth: 220,
            expandedModuleCount: 1,
            showsCompactContent: false,
            preferredRestingHeight: 44,
            preferredRestingWidth: 278
        )

        XCTAssertEqual(metrics.hiddenHeight, 44)
        let restingBodyWidth = IslandAppearanceConstraints.resolvedRestingWidth(
            preferredWidth: 278,
            physicalNotchWidth: 220,
            restingHeight: 44
        )
        let restingShoulder = NotchShapeSpec.restingShoulderWidth(forHeight: 44)
        XCTAssertEqual(metrics.hiddenWidth, restingBodyWidth + restingShoulder * 2, accuracy: 0.001)
        XCTAssertEqual(metrics.collapsedHeight, 78)
        XCTAssertEqual(metrics.collapsedWidth, metrics.hiddenWidth + 72)
    }

    func testCustomRestingWidthDoesNotChangeCompactMetrics() {
        let automaticMetrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 220, height: 38),
            notchPhysicalWidth: 220,
            expandedModuleCount: 1
        )
        let customRestingMetrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 220, height: 38),
            notchPhysicalWidth: 220,
            expandedModuleCount: 1,
            preferredRestingWidth: 420
        )

        XCTAssertEqual(customRestingMetrics.hiddenSize, automaticMetrics.hiddenSize)
    }

    func testCompactWidthCannotExposeThePhysicalNotch() {
        let height: CGFloat = 38
        let minimum = IslandAppearanceConstraints.minimumRestingWidth(
            physicalNotchWidth: 220,
            restingHeight: height
        )
        let resolved = IslandAppearanceConstraints.resolvedRestingWidth(
            preferredWidth: 180,
            physicalNotchWidth: 220,
            restingHeight: height
        )

        XCTAssertEqual(resolved, minimum)
    }

    func testRestingMetricsUseNotchWidthPlusEightBeforeAddingShoulders() {
        let metrics = IslandBackgroundMetrics.resolved(
            hiddenIslandSize: CGSize(width: 220, height: 38),
            notchPhysicalWidth: 220,
            expandedModuleCount: 1,
            showsCompactContent: false
        )

        XCTAssertEqual(metrics.hiddenHeight, 38)
        let shoulderWidth = NotchShapeSpec.restingShoulderWidth(forHeight: metrics.hiddenHeight)
        let expectedBodyWidth = 220 + IslandAppearanceConstraints.defaultRestingHorizontalInsets
        XCTAssertEqual(metrics.hiddenWidth, expectedBodyWidth + shoulderWidth * 2)
        XCTAssertEqual(metrics.hiddenWidth - shoulderWidth * 2, expectedBodyWidth)
    }

    func testRestingWidthUsesConfiguredDefaultWhenNotchWidthIsUnavailable() {
        let height: CGFloat = 38
        let resolved = IslandAppearanceConstraints.automaticRestingWidth(
            physicalNotchWidth: 0,
            restingHeight: height
        )

        XCTAssertEqual(
            resolved,
            IslandAppearanceConstraints.defaultRestingWidth
        )
    }

    func testCompactMaskPathCoversItsFullRequestedBounds() {
        let height: CGFloat = 34
        let topR = NotchShapeSpec.topConcaveRadius(forHeight: height)
        let width = 226 + topR * 2
        let path = makeRestingNotchMaskPath(width: width, height: height)

        XCTAssertFalse(path.isEmpty)
        XCTAssertEqual(path.boundingBoxOfPath, CGRect(x: 0, y: 0, width: width, height: height))
    }

    func testCompactMaskUsesSameConcaveShoulderRadiusAsMediaMask() {
        let height: CGFloat = 34
        let topR = NotchShapeSpec.topConcaveRadius(forHeight: height)
        let compactWidth = 226 + topR * 2
        let compactElements = pathElements(makeRestingNotchMaskPath(width: compactWidth, height: height))
        let mediaElements = pathElements(makeHiddenScreenNotchPath(width: 450, height: height))

        XCTAssertEqual(compactElements.map(\.type), mediaElements.map(\.type))
        XCTAssertEqual(compactElements[2].type, .addQuadCurveToPoint)
        XCTAssertEqual(compactElements[2].points[0].y, 0)
        XCTAssertEqual(compactElements[2].points[1].y, topR)
        XCTAssertEqual(mediaElements[2].points[0].y, 0)
        XCTAssertEqual(mediaElements[2].points[1].y, topR)

        // 隐藏态竖壁间宽度是“物理刘海 + 6 pt”，肩部只向两侧额外展开。
        let rightWallX = compactElements[2].points[1].x
        let leftWallX = compactElements[7].points[0].x
        XCTAssertEqual(rightWallX - leftWallX, 226, accuracy: 0.0001)
    }

    func testCompactShoulderAndBottomCornersUseTheirIndependentRadii() {
        for height: CGFloat in [28, 34, 38, 72, 180, 250] {
            XCTAssertEqual(
                NotchShapeSpec.topConcaveRadius(forHeight: height),
                NotchShapeSpec.compactCornerRadius,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                NotchShapeSpec.bottomConvexRadius(forHeight: height),
                NotchShapeSpec.compactBottomCornerRadius,
                accuracy: 0.0001
            )
        }
    }

    func testNotchPathUsesIndependentShoulderAndBottomRadii() {
        let width: CGFloat = 450
        let height: CGFloat = 72
        let shoulderRadius = NotchShapeSpec.topConcaveRadius(forHeight: height)
        let bottomCornerRadius = NotchShapeSpec.bottomConvexRadius(forHeight: height)
        let wallInset = NotchShapeSpec.shoulderWidth(forOuterWidth: width)
        let rightWallX = width - wallInset
        let elements = pathElements(makeHiddenScreenNotchPath(width: width, height: height))

        let rightShoulder = elements[2]
        let rightWall = elements[3]
        let rightBottomCorner = elements[4]

        XCTAssertEqual(rightShoulder.type, .addQuadCurveToPoint)
        XCTAssertEqual(rightShoulder.points[1], CGPoint(x: rightWallX, y: shoulderRadius))
        XCTAssertEqual(rightWall.points[0], CGPoint(x: rightWallX, y: height - bottomCornerRadius))
        XCTAssertEqual(rightBottomCorner.type, .addQuadCurveToPoint)
        XCTAssertEqual(
            rightBottomCorner.points[1],
            CGPoint(x: rightWallX - bottomCornerRadius, y: height)
        )
    }

    func testDefaultAndDynamicStatesUseExactlyTheSameCompactShoulderCurvature() {
        let defaultRadius = NotchShapeSpec.cornerRadius(
            forHeight: 38,
            expansionProgress: 0
        )
        let dynamicRadius = NotchShapeSpec.cornerRadius(
            forHeight: 44,
            expansionProgress: 0
        )

        XCTAssertEqual(defaultRadius, dynamicRadius, accuracy: 0.0001)
        XCTAssertEqual(defaultRadius, NotchShapeSpec.compactCornerRadius, accuracy: 0.0001)
    }

    func testCompactMorphMovesRightWallMonotonicallyBetweenEndpoints() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 38)
        let progresses: [CGFloat] = [0, 0.25, 0.5, 0.75, 1]
        let wallPositions = progresses.map { progress in
            let path = IslandBackgroundPath.makePath(
                for: .hidden,
                in: rect,
                expansionProgress: 0,
                compactMorphProgress: progress,
                rendersInFullBounds: true
            )
            return pathElements(path)[2].points[1].x
        }

        for (start, end) in zip(wallPositions, wallPositions.dropFirst()) {
            XCTAssertLessThan(end, start)
        }

        let restingWallX = rect.maxX - NotchShapeSpec.compactCornerRadius
        let dynamicWallX = rect.maxX - NotchShapeSpec.shoulderWidth(forOuterWidth: rect.width)
        XCTAssertEqual(wallPositions[0], restingWallX, accuracy: 0.0001)
        XCTAssertEqual(wallPositions[4], dynamicWallX, accuracy: 0.0001)
        XCTAssertLessThan(wallPositions[2], wallPositions[0])
        XCTAssertGreaterThan(wallPositions[2], wallPositions[4])
    }

    func testAdjacentCompactMorphPathsKeepTopologyAndMoveContinuously() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 38)
        let firstPath = IslandBackgroundPath.makePath(
            for: .hidden,
            in: rect,
            expansionProgress: 0,
            compactMorphProgress: 0.49,
            rendersInFullBounds: true
        )
        let secondPath = IslandBackgroundPath.makePath(
            for: .hidden,
            in: rect,
            expansionProgress: 0,
            compactMorphProgress: 0.5,
            rendersInFullBounds: true
        )
        let firstElements = pathElements(firstPath)
        let secondElements = pathElements(secondPath)

        XCTAssertEqual(firstElements.map(\.type), secondElements.map(\.type))
        XCTAssertEqual(firstElements.count, secondElements.count)
        for (firstElement, secondElement) in zip(firstElements, secondElements) {
            XCTAssertEqual(firstElement.points.count, secondElement.points.count)
            for (firstPoint, secondPoint) in zip(firstElement.points, secondElement.points) {
                XCTAssertLessThan(hypot(secondPoint.x - firstPoint.x, secondPoint.y - firstPoint.y), 1)
            }
        }
    }

    func testNotchShapeAnimatesExpansionAndCompactMorphIndependently() {
        var shape = NotchShape(
            state: .hidden,
            expansionProgress: 0.25,
            compactMorphProgress: 0.75
        )

        XCTAssertEqual(shape.animatableData.first, 0.25)
        XCTAssertEqual(shape.animatableData.second, 0.75)

        shape.animatableData = AnimatablePair(0.6, 0.4)
        XCTAssertEqual(shape.expansionProgress, 0.6)
        XCTAssertEqual(shape.compactMorphProgress, 0.4)
    }

    func testShoulderCurvatureTransitionsMonotonicallyFromTightToSmooth() {
        let compactRadius = NotchShapeSpec.cornerRadius(
            forHeight: 250,
            expansionProgress: 0
        )
        let middleRadius = NotchShapeSpec.cornerRadius(
            forHeight: 250,
            expansionProgress: 0.5
        )
        let expandedRadius = NotchShapeSpec.cornerRadius(
            forHeight: 250,
            expansionProgress: 1
        )

        XCTAssertGreaterThan(middleRadius, compactRadius)
        XCTAssertGreaterThan(expandedRadius, middleRadius)
        // 数学曲率为 1 / R：半径越大，肩部越缓。
        XCTAssertLessThan(1 / middleRadius, 1 / compactRadius)
        XCTAssertLessThan(1 / expandedRadius, 1 / middleRadius)
        XCTAssertLessThanOrEqual(
            expandedRadius - compactRadius,
            NotchShapeSpec.expandedCornerRadius - NotchShapeSpec.compactCornerRadius
        )
        XCTAssertEqual(expandedRadius, NotchShapeSpec.expandedCornerRadius, accuracy: 0.0001)
    }

    func testExpandedShoulderVisuallyFlattensInsteadOfGrowingItsOuterCutIn() {
        let metrics = IslandBackgroundMetrics.default

        func rightOuterCutIn(size: CGSize, progress: CGFloat) -> CGFloat {
            let rect = CGRect(origin: .zero, size: size)
            let path = IslandBackgroundPath.makePath(
                for: progress == 0 ? .hidden : .expanded,
                in: rect,
                metrics: metrics,
                expansionProgress: progress,
                rendersInFullBounds: true
            )
            let elements = pathElements(path)
            return rect.maxX - elements[1].points[0].x
        }

        let compactCutIn = rightOuterCutIn(size: metrics.hiddenSize, progress: 0)
        let middleCutIn = rightOuterCutIn(
            size: CGSize(
                width: (metrics.hiddenWidth + metrics.expandedWidth) / 2,
                height: (metrics.hiddenHeight + metrics.expandedHeight) / 2
            ),
            progress: 0.5
        )
        let expandedCutIn = rightOuterCutIn(size: metrics.expandedSize, progress: 1)

        XCTAssertGreaterThan(compactCutIn, middleCutIn)
        XCTAssertGreaterThan(middleCutIn, expandedCutIn)
        XCTAssertEqual(expandedCutIn, 0, accuracy: 0.0001)
    }

    func testBottomCornersRemainSofterThanShouldersAcrossExpansion() {
        var previousGap: CGFloat = 0
        for progress: CGFloat in [0, 0.2, 0.5, 0.8, 1] {
            let shoulderRadius = NotchShapeSpec.topConcaveRadius(
                forHeight: 250,
                expansionProgress: progress
            )
            let bottomCornerRadius = NotchShapeSpec.bottomConvexRadius(
                forHeight: 250,
                expansionProgress: progress
            )
            let gap = bottomCornerRadius - shoulderRadius

            XCTAssertGreaterThanOrEqual(gap, previousGap)
            previousGap = gap
        }

        // 圆角与尺寸共用同一条弹簧原始进度：过冲段（progress > 1）圆角随尺寸
        // 一起冲过头再收敛，最终回到紧凑值。这里顺带验证插值是线性的。
        XCTAssertEqual(
            NotchShapeSpec.bottomConvexRadius(forHeight: 250, expansionProgress: 1.2),
            NotchShapeSpec.compactBottomCornerRadius
                + (NotchShapeSpec.expandedBottomCornerRadius
                    - NotchShapeSpec.compactBottomCornerRadius) * 1.2,
            accuracy: 0.0001
        )
    }

    func testSwitchingDefaultStateToExpandedGeometryDoesNotChangeTheStartPath() {
        let metrics = IslandBackgroundMetrics.default
        let rect = CGRect(origin: .zero, size: metrics.hiddenSize)
        let compactPath = IslandBackgroundPath.makePath(
            for: .hidden,
            in: rect,
            metrics: metrics,
            expansionProgress: 0,
            compactMorphProgress: 0,
            rendersInFullBounds: true
        )
        let expandedGeometryAtStart = IslandBackgroundPath.makePath(
            for: .expanded,
            in: rect,
            metrics: metrics,
            expansionProgress: 0,
            compactMorphProgress: 0,
            rendersInFullBounds: true
        )

        let compactElements = pathElements(compactPath)
        let expandedElements = pathElements(expandedGeometryAtStart)
        XCTAssertEqual(compactElements.map(\.type), expandedElements.map(\.type))
        XCTAssertEqual(compactElements.count, expandedElements.count)
        for (compactElement, expandedElement) in zip(compactElements, expandedElements) {
            XCTAssertEqual(compactElement.points, expandedElement.points)
        }
    }

    func testSwitchingDynamicStateToExpandedGeometryDoesNotChangeTheStartPath() {
        let metrics = IslandBackgroundMetrics.default
        let rect = CGRect(origin: .zero, size: metrics.hiddenSize)
        let compactPath = IslandBackgroundPath.makePath(
            for: .hidden,
            in: rect,
            metrics: metrics,
            expansionProgress: 0,
            compactMorphProgress: 1,
            rendersInFullBounds: true
        )
        let expandedGeometryAtStart = IslandBackgroundPath.makePath(
            for: .expanded,
            in: rect,
            metrics: metrics,
            expansionProgress: 0,
            compactMorphProgress: 1,
            rendersInFullBounds: true
        )

        let compactElements = pathElements(compactPath)
        let expandedElements = pathElements(expandedGeometryAtStart)
        XCTAssertEqual(compactElements.map(\.type), expandedElements.map(\.type))
        XCTAssertEqual(compactElements.count, expandedElements.count)
        for (compactElement, expandedElement) in zip(compactElements, expandedElements) {
            XCTAssertEqual(compactElement.points, expandedElement.points)
        }
    }

    func testFullBoundsRenderingLetsHoverGrowWithoutScalingTheCompactPath() {
        let metrics = IslandBackgroundMetrics.default
        let hoverRect = CGRect(x: 0, y: 0, width: 310, height: 43)
        let hoverPath = IslandBackgroundPath.makePath(
            for: .hidden,
            in: hoverRect,
            metrics: metrics,
            expansionProgress: 0,
            rendersInFullBounds: true
        )

        let compactPath = IslandBackgroundPath.makePath(
            for: .hidden,
            in: CGRect(origin: .zero, size: metrics.hiddenSize),
            metrics: metrics,
            expansionProgress: 0,
            rendersInFullBounds: true
        )
        XCTAssertEqual(
            hoverPath.boundingBoxOfPath.width - compactPath.boundingBoxOfPath.width,
            hoverRect.width - metrics.hiddenWidth,
            accuracy: 0.0001
        )
        XCTAssertEqual(hoverPath.boundingBoxOfPath.maxY, hoverRect.maxY, accuracy: 0.0001)
        let elements = pathElements(hoverPath)
        XCTAssertEqual(
            elements[2].points[1].y,
            NotchShapeSpec.compactCornerRadius,
            accuracy: 0.0001
        )
    }

    private func pathElements(_ path: CGPath) -> [(type: CGPathElementType, points: [CGPoint])] {
        var result: [(type: CGPathElementType, points: [CGPoint])] = []
        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            let pointCount: Int
            switch element.type {
            case .moveToPoint, .addLineToPoint:
                pointCount = 1
            case .addQuadCurveToPoint:
                pointCount = 2
            case .addCurveToPoint:
                pointCount = 3
            case .closeSubpath:
                pointCount = 0
            @unknown default:
                pointCount = 0
            }
            let points = (0..<pointCount).map { element.points[$0] }
            result.append((element.type, points))
        }
        return result
    }

    func testPlainIslandPathMatchesRequestedSize() {
        let path = makePlainIslandPath(width: 220, height: 34)

        XCTAssertFalse(path.isEmpty)
        XCTAssertEqual(path.boundingBoxOfPath, CGRect(x: 0, y: 0, width: 220, height: 34))
    }
}
