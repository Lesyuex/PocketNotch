import AppKit
import SwiftUI

/// 贯穿文件拖入刘海后的整次 AppKit 拖拽会话，并把最终文件与落点提交给模块。
struct IslandFileDragController: NSViewRepresentable {
    let isEnabled: Bool
    let isClickEnabled: Bool
    let isDragSessionActive: Bool
    let accessibilityLabel: String
    let onTargetChange: (CGPoint?) -> Void
    let onDrop: ([URL], CGPoint) -> Bool
    let onClick: () -> Void

    func makeNSView(context: Context) -> IslandFileDragNSView {
        let view = IslandFileDragNSView()
        view.onTargetChange = onTargetChange
        view.onDrop = onDrop
        view.onClick = onClick
        view.update(
            isEnabled: isEnabled,
            isClickEnabled: isClickEnabled,
            isDragSessionActive: isDragSessionActive,
            accessibilityLabel: accessibilityLabel
        )
        return view
    }

    func updateNSView(_ nsView: IslandFileDragNSView, context: Context) {
        nsView.onTargetChange = onTargetChange
        nsView.onDrop = onDrop
        nsView.onClick = onClick
        nsView.update(
            isEnabled: isEnabled,
            isClickEnabled: isClickEnabled,
            isDragSessionActive: isDragSessionActive,
            accessibilityLabel: accessibilityLabel
        )
    }

    static func dismantleNSView(_ nsView: IslandFileDragNSView, coordinator: ()) {
        nsView.invalidate()
    }
}

final class IslandFileDragNSView: NSView {
    var onTargetChange: ((CGPoint?) -> Void)?
    var onDrop: (([URL], CGPoint) -> Bool)?
    var onClick: (() -> Void)?

    private var isEnabled = false
    private var isClickEnabled = false
    private var isDragSessionActive = false
    private var targetLocation: CGPoint?
    private var isPressed = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled, bounds.contains(point) else { return nil }
        return isClickEnabled || isDragSessionActive || targetLocation != nil ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard isClickEnabled else { return }
        isPressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isPressed else { return }
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let shouldClick = isPressed
            && isClickEnabled
            && bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        if shouldClick {
            onClick?()
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isClickEnabled else { return false }
        onClick?()
        return true
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard canAccept(sender) else { return [] }
        setTargetLocation(normalizedLocation(for: sender))
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard canAccept(sender) else {
            setTargetLocation(nil)
            return []
        }
        setTargetLocation(normalizedLocation(for: sender))
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        setTargetLocation(nil)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        canAccept(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = readFileURLs(from: sender.draggingPasteboard)
        let location = normalizedLocation(for: sender)
        let didHandle = !urls.isEmpty && onDrop?(urls, location) == true
        setTargetLocation(nil)
        return didHandle
    }

    func update(
        isEnabled: Bool,
        isClickEnabled: Bool,
        isDragSessionActive: Bool,
        accessibilityLabel: String
    ) {
        if isEnabled != self.isEnabled {
            self.isEnabled = isEnabled
            if isEnabled {
                registerForDraggedTypes([.fileURL])
            } else {
                unregisterDraggedTypes()
                setTargetLocation(nil)
            }
        }

        self.isClickEnabled = isClickEnabled
        self.isDragSessionActive = isDragSessionActive
        setAccessibilityElement(isClickEnabled)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityLabel)
    }

    func invalidate() {
        unregisterDraggedTypes()
        setTargetLocation(nil)
        isPressed = false
        onTargetChange = nil
        onDrop = nil
        onClick = nil
    }

    private func canAccept(_ sender: any NSDraggingInfo) -> Bool {
        isEnabled && sender.draggingPasteboard.availableType(from: [.fileURL]) != nil
    }

    private func readFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL]
        return objects?.compactMap { $0 as URL } ?? []
    }

    private func normalizedLocation(for sender: any NSDraggingInfo) -> CGPoint {
        let point = convert(sender.draggingLocation, from: nil)
        return CGPoint(
            x: min(max(point.x / max(bounds.width, 1), 0), 1),
            y: min(max(point.y / max(bounds.height, 1), 0), 1)
        )
    }

    private func setTargetLocation(_ location: CGPoint?) {
        guard location != targetLocation else { return }
        targetLocation = location
        onTargetChange?(location)
    }
}
