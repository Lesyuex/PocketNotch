import SwiftUI

@MainActor
final class LockScreenIslandPresentationModel: ObservableObject {
    @Published private(set) var entranceGeneration = 0

    func beginEntrance() {
        entranceGeneration &+= 1
    }
}

/// A compact, noninteractive lock-screen surface. The desktop island keeps its
/// own large expansion canvas and never enters the lock-screen Space.
struct LockScreenIslandView: View {
    @ObservedObject var screenLockController: ScreenLockController
    @ObservedObject var presentationModel: LockScreenIslandPresentationModel
    let layout: ResolvedCompactIslandLayout

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentationProgress: CGFloat = 0
    @State private var reboundScaleX: CGFloat = 1
    @State private var showsLockIndicator = false

    private var metrics: IslandBackgroundMetrics {
        var metrics = IslandBackgroundMetrics.default
        metrics.hiddenWidth = layout.islandWidth
        metrics.hiddenHeight = layout.islandHeight
        return metrics
    }

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(state: .hidden, metrics: metrics, rendersInFullBounds: true)
                .fill(PocketNotchTheme.background)
                .frame(width: layout.islandWidth, height: layout.islandHeight)
                .scaleEffect(
                    x: reduceMotion
                        ? 1
                        : (initialHorizontalScale
                            + presentationProgress * (1 - initialHorizontalScale))
                            * reboundScaleX,
                    y: 1,
                    anchor: .top
                )

            CompactIslandLayout(layout: layout) {
                IslandScreenLockIndicator(phase: screenLockController.phase)
                    .opacity(showsLockIndicator ? 1 : 0)
                    .scaleEffect(showsLockIndicator ? 1 : 0.72)
            } right: {
                EmptyView()
            }
            .environment(
                \.islandCompactContentSize,
                layout.leadingContentSize
            )
        }
        .frame(width: layout.islandWidth, height: layout.islandHeight)
        .allowsHitTesting(false)
        .task(id: presentationModel.entranceGeneration) {
            let generation = presentationModel.entranceGeneration
            guard generation > 0, screenLockController.phase == .locked else { return }
            await animateLockEntrance(generation: generation)
        }
    }

    private var initialHorizontalScale: CGFloat {
        min(max(layout.centerNotchWidth / max(layout.islandWidth, 1), 0.45), 0.82)
    }

    private func animateLockEntrance(generation: Int) async {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentationProgress = reduceMotion ? 1 : 0
            reboundScaleX = 1
            showsLockIndicator = false
        }

        do {
            try await Task.sleep(
                nanoseconds: PocketNotchTheme.islandCompactActivationDelayNanoseconds
            )
        } catch {
            return
        }
        guard !Task.isCancelled,
              generation == presentationModel.entranceGeneration,
              screenLockController.phase == .locked else { return }

        if reduceMotion {
            presentationProgress = 1
            withAnimation(PocketNotchTheme.islandReducedMotionAnimation) {
                showsLockIndicator = true
            }
            return
        }

        withAnimation(
            PocketNotchTheme.islandScreenLockPresentationAnimation,
            completionCriteria: .logicallyComplete
        ) {
            presentationProgress = 1
            reboundScaleX = PocketNotchTheme.islandScreenLockOvershootScaleX
        } completion: {
            guard generation == presentationModel.entranceGeneration,
                  screenLockController.phase == .locked else { return }
            withAnimation(
                PocketNotchTheme.islandScreenLockReboundAnimation,
                completionCriteria: .logicallyComplete
            ) {
                reboundScaleX = 1
            } completion: {
                guard generation == presentationModel.entranceGeneration,
                      screenLockController.phase == .locked else { return }
                withAnimation(PocketNotchTheme.islandScreenLockAnimation) {
                    showsLockIndicator = true
                }
            }
        }
    }
}
