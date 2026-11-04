import AppKit
import SwiftUI

public extension View {
    /// 岛内统一的 popover 呈现方式：原生材质 + 展开态交互占用。
    func islandPopover<Content: View>(
        isPresented: Binding<Bool>,
        arrowEdge: Edge = .top,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        IslandPopoverContainer(
            base: self,
            isPresented: isPresented,
            arrowEdge: arrowEdge,
            content: content
        )
    }
}

private enum IslandPopoverDismissHold {
    static let pointerExitMargin: CGFloat = 8
    static let pollInterval: Duration = .milliseconds(100)
    static let maximumPollCount = 50
}

private struct IslandPopoverContainer<Base: View, Content: View>: View {
    let base: Base
    let isPresented: Binding<Bool>
    let arrowEdge: Edge
    let content: () -> Content

    @Environment(\.islandExpandedContentInteraction) private var expandedContentInteraction
    @State private var holdsExpandedContent = false
    @State private var popoverFrame: CGRect?
    @State private var releaseTask: Task<Void, Never>?

    var body: some View {
        base
            .popover(isPresented: isPresented, arrowEdge: arrowEdge) {
                content()
                    .background {
                        PopoverWindowFrameReader { popoverFrame = $0 }
                    }
            }
            .onChange(of: isPresented.wrappedValue) { _, presented in
                if presented {
                    setHeld(true)
                } else {
                    holdUntilPointerLeavesPopover()
                }
            }
            .onDisappear {
                releaseTask?.cancel()
                releaseTask = nil
                setHeld(false)
            }
    }

    private func setHeld(_ held: Bool) {
        if held {
            releaseTask?.cancel()
            releaseTask = nil
            guard !holdsExpandedContent else { return }
            holdsExpandedContent = true
            expandedContentInteraction?.begin()
        } else {
            guard holdsExpandedContent else { return }
            holdsExpandedContent = false
            expandedContentInteraction?.end()
        }
    }

    /// 弹层关闭后指针通常还停在原区域（可能已超出 Island 背板），此时若立即
    /// 释放占用会被 hover 判定为移出而收起；持续占用到指针离开该区域为止。
    private func holdUntilPointerLeavesPopover() {
        guard holdsExpandedContent else { return }
        guard let frame = popoverFrame else {
            releaseHold()
            return
        }

        let releaseFrame = frame.insetBy(
            dx: -IslandPopoverDismissHold.pointerExitMargin,
            dy: -IslandPopoverDismissHold.pointerExitMargin
        )
        guard releaseFrame.contains(NSEvent.mouseLocation) else {
            releaseHold()
            return
        }

        releaseTask?.cancel()
        releaseTask = Task { @MainActor in
            for _ in 0..<IslandPopoverDismissHold.maximumPollCount {
                do {
                    try await Task.sleep(for: IslandPopoverDismissHold.pollInterval)
                } catch {
                    return
                }
                if Task.isCancelled { return }
                guard releaseFrame.contains(NSEvent.mouseLocation) else {
                    releaseHold()
                    return
                }
            }
            releaseHold()
        }
    }

    private func releaseHold() {
        releaseTask?.cancel()
        releaseTask = nil
        setHeld(false)
    }
}

private struct PopoverWindowFrameReader: NSViewRepresentable {
    let onFrameChange: (CGRect) -> Void

    func makeNSView(context: Context) -> PopoverWindowFrameTrackingView {
        let view = PopoverWindowFrameTrackingView()
        view.onFrameChange = onFrameChange
        return view
    }

    func updateNSView(_ nsView: PopoverWindowFrameTrackingView, context: Context) {
        nsView.onFrameChange = onFrameChange
        nsView.reportFrameIfNeeded()
    }

    static func dismantleNSView(_ nsView: PopoverWindowFrameTrackingView, coordinator: ()) {
        nsView.onFrameChange = nil
    }
}

private final class PopoverWindowFrameTrackingView: NSView {
    var onFrameChange: ((CGRect) -> Void)?
    private var lastReportedFrame: CGRect?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportFrameIfNeeded()
    }

    override func layout() {
        super.layout()
        reportFrameIfNeeded()
    }

    func reportFrameIfNeeded() {
        guard let window else { return }
        let contentFrame = window.convertToScreen(convert(bounds, to: nil))
        let frame = contentFrame.isEmpty ? window.frame : contentFrame
        guard frame != lastReportedFrame else { return }
        lastReportedFrame = frame
        DispatchQueue.main.async { [weak self] in
            self?.onFrameChange?(frame)
        }
    }
}
