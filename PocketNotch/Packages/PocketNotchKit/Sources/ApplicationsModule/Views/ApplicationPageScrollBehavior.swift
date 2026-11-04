import AppKit
import SwiftUI

struct ApplicationPageScrollBehavior: ScrollTargetBehavior {
    let pageCount: Int

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let width = context.containerSize.width
        guard width > 0 else { return }
        let page = ApplicationPageLayout.destination(
            originalOffset: context.originalTarget.rect.minX,
            proposedOffset: target.rect.minX,
            velocity: context.velocity.dx,
            pageWidth: width,
            pageCount: pageCount
        )
        target.rect.origin.x = CGFloat(page) * width
        target.rect.size.width = width
        target.anchor = .leading
    }
}

struct ApplicationPageSwipeReceiver: NSViewRepresentable {
    var onSwipe: (Int) -> Bool

    func makeNSView(context: Context) -> SwipeView {
        let view = SwipeView()
        view.onSwipe = onSwipe
        return view
    }

    func updateNSView(_ nsView: SwipeView, context: Context) {
        nsView.onSwipe = onSwipe
    }

    static func dismantleNSView(_ nsView: SwipeView, coordinator: ()) {
        nsView.removeMonitor()
        nsView.onSwipe = nil
    }

    final class SwipeView: NSView {
        var onSwipe: ((Int) -> Bool)?
        private var monitor: Any?
        private var accumulatedHorizontal: CGFloat = 0
        private var didTriggerDuringGesture = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.swipe, .scrollWheel]) { [weak self] event in
                guard let self, let window = self.window,
                      event.window === window, window.isVisible,
                      !self.isHiddenOrHasHiddenAncestor,
                      self.visibleRect.contains(self.convert(event.locationInWindow, from: nil))
                else { return event }

                switch event.type {
                case .swipe:
                    guard let direction = ApplicationPageLayout.swipeDirection(
                        horizontal: event.deltaX,
                        vertical: event.deltaY
                    ) else { return event }
                    self.resetScrollGesture()
                    return self.onSwipe?(direction) == true ? nil : event

                case .scrollWheel:
                    return self.handleScrollWheel(event)

                default:
                    return event
                }
            }
        }

        private func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
            guard event.momentumPhase.isEmpty else { return nil }

            if event.phase == .began || event.phase == .mayBegin {
                resetScrollGesture()
            }

            guard event.phase == .began || event.phase == .changed || event.phase == .mayBegin else {
                if event.phase == .ended || event.phase == .cancelled {
                    resetScrollGesture()
                }
                return event
            }

            let horizontal = event.scrollingDeltaX
            guard abs(horizontal) > abs(event.scrollingDeltaY), horizontal != 0 else {
                return event
            }

            accumulatedHorizontal += horizontal
            guard !didTriggerDuringGesture else { return nil }

            let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 24 : 1
            guard abs(accumulatedHorizontal) >= threshold else { return nil }

            let direction = accumulatedHorizontal < 0 ? 1 : -1
            accumulatedHorizontal = 0
            didTriggerDuringGesture = true
            _ = onSwipe?(direction)
            return nil
        }

        private func resetScrollGesture() {
            accumulatedHorizontal = 0
            didTriggerDuringGesture = false
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
