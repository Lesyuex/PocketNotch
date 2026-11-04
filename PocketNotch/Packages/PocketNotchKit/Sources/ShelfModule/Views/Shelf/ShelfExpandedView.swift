import AppKit
import PocketNotchShared
import PocketNotchCore
import SwiftUI

enum ShelfDropLayout {
    static let airDropWidth: CGFloat = 152
    static let airDropNormalizedBoundary: CGFloat = 0.34
}

struct ShelfExpandedView: View {
    let store: ShelfStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandFileDragLocation) private var fileDragLocation
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var statusMessage: String?
    @State private var hoveredToolbarHelp: String?

    private let clipboardService = ShelfClipboardService()
    private let airDropService = ShelfAirDropService()

    private var selectedItems: [ShelfItem] {
        store.items.filter { selectedItemIDs.contains($0.id) }
    }

    private var isAirDropTargeted: Bool {
        guard let fileDragLocation else { return false }
        return fileDragLocation.x <= ShelfDropLayout.airDropNormalizedBoundary
    }

    private var isTransferTargeted: Bool {
        guard let fileDragLocation else { return false }
        return fileDragLocation.x > ShelfDropLayout.airDropNormalizedBoundary
    }

    var body: some View {
        HStack(spacing: 16) {
            airDropZone

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 4)

            fileBrowser
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, IslandLayoutToken.expandedNowPageHorizontalInset)
        .padding(.bottom, -IslandLayoutToken.expandedContentVerticalInset)
        .onChange(of: store.items) { _, items in
            selectedItemIDs.formIntersection(Set(items.map(\.id)))
        }
    }

    private var airDropZone: some View {
        VStack(spacing: 8) {
            ShelfAirDropIcon(size: 32)
                .opacity(isAirDropTargeted ? 1 : 0.72)

            Text("shelf.airDrop")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            Text(
                isAirDropTargeted
                    ? L10n.tr("shelf.releaseToSend")
                    : L10n.tr("shelf.dropToSend")
            )
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(isAirDropTargeted ? 0.72 : 0.42))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 22)

            Button(action: airDropSelection) {
                Label {
                    Text("shelf.sendSelectedFiles")
                } icon: {
                    ShelfAirDropIcon(size: 11)
                }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background {
                        Capsule()
                            .fill(.white.opacity(0.09))
                    }
            }
            .buttonStyle(ShelfPasteButtonStyle())
            .disabled(selectedItems.isEmpty)
        }
        .frame(width: ShelfDropLayout.airDropWidth)
        .frame(maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(isAirDropTargeted ? 0.1 : 0.035))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    .white.opacity(isAirDropTargeted ? 0.92 : 0.1),
                    style: StrokeStyle(
                        lineWidth: isAirDropTargeted ? 1.25 : 1,
                        dash: [4, 4]
                    )
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.14),
            value: isAirDropTargeted
        )
        .accessibilityLabel("shelf.airDropZone")
    }

    private var fileBrowser: some View {
        VStack(spacing: 8) {
            browserToolbar

            if store.items.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(store.items) { item in
                            fileTile(item)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(isTransferTargeted ? 0.08 : 0.025))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    .white.opacity(isTransferTargeted ? 0.92 : 0.06),
                    style: StrokeStyle(
                        lineWidth: isTransferTargeted ? 1.25 : 1,
                        dash: [4, 4]
                    )
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.14),
            value: isTransferTargeted
        )
        .accessibilityLabel("shelf.transferZone")
    }

    private var browserToolbar: some View {
        HStack(spacing: 2) {
            VStack(alignment: .leading, spacing: 1) {
                Text("shelf.fileTransfer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))

                Text(hoveredToolbarHelp ?? statusMessage ?? String(format: L10n.tr("shelf.fileCountFormat"), store.items.count))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            toolbarButton(
                systemName: "doc.on.clipboard",
                help: L10n.tr("shelf.addFromClipboard"),
                isDisabled: false,
                action: addFilesFromClipboard
            )
            toolbarButton(
                systemName: "doc.on.doc",
                help: L10n.tr("shelf.copySelected"),
                isDisabled: selectedItems.isEmpty,
                action: copySelection
            )
            toolbarButton(
                systemName: "folder",
                help: L10n.tr("shelf.revealInFinder"),
                isDisabled: selectedItems.isEmpty,
                action: revealSelection
            )
            toolbarButton(
                systemName: "trash",
                help: L10n.tr("shelf.removeSelected"),
                isDisabled: selectedItems.isEmpty,
                action: removeSelection
            )
        }
        .frame(height: 32)
    }

    private func toolbarButton(
        systemName: String,
        help: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(ShelfActionButtonStyle())
        .disabled(isDisabled)
        .onHover { isHovering in
            if isHovering {
                hoveredToolbarHelp = help
            } else if hoveredToolbarHelp == help {
                hoveredToolbarHelp = nil
            }
        }
        .help(help)
        .accessibilityLabel(help)
    }

    private func fileTile(_ item: ShelfItem) -> some View {
        Button {
            toggleSelection(of: item)
        } label: {
            VStack(spacing: 4) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)

                Text(item.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(fileKind(for: item.url))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(width: 76, height: 88)
        }
        .buttonStyle(
            ShelfFileButtonStyle(isSelected: selectedItemIDs.contains(item.id))
        )
        .contextMenu {
            Button("shelf.revealInFinder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("shelf.remove", role: .destructive) {
                selectedItemIDs.remove(item.id)
                store.remove(item)
            }
        }
        .help(item.name)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(selectedItemIDs.contains(item.id) ? .isSelected : [])
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.26))

            Text("shelf.empty")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.36))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addFilesFromClipboard() {
        let addedCount = store.add(contentsOf: clipboardService.readFileURLs())
        updateStatusAfterAdding(addedCount)
    }

    private func updateStatusAfterAdding(_ count: Int) {
        statusMessage = count > 0 ? String(format: L10n.tr("shelf.addedCountFormat"), count) : L10n.tr("shelf.noNewFiles")
    }

    private func copySelection() {
        let didCopy = clipboardService.writeFileURLs(selectedItems.map(\.url))
        statusMessage = didCopy ? L10n.tr("shelf.copiedSelected") : L10n.tr("shelf.copyFailed")
    }

    private func airDropSelection() {
        let didSend = airDropService.send(selectedItems.map(\.url))
        statusMessage = didSend ? L10n.tr("shelf.airDropOpened") : L10n.tr("shelf.airDropUnavailable")
    }

    private func revealSelection() {
        NSWorkspace.shared.activateFileViewerSelecting(selectedItems.map(\.url))
    }

    private func removeSelection() {
        store.remove(ids: selectedItemIDs)
        selectedItemIDs.removeAll()
        statusMessage = L10n.tr("shelf.removedSelected")
    }

    private func toggleSelection(of item: ShelfItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
        statusMessage = nil
    }

    private func fileKind(for url: URL) -> String {
        let resourceValues = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .isPackageKey]
        )
        if resourceValues?.isDirectory == true, resourceValues?.isPackage != true {
            return L10n.tr("shelf.folder")
        }
        let fileExtension = url.pathExtension.uppercased()
        return fileExtension.isEmpty ? L10n.tr("shelf.file") : fileExtension
    }
}

private struct ShelfAirDropIcon: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: ShelfSystemImages.airDrop)
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

private enum ShelfSystemImages {
    static let airDrop: NSImage = {
        let coreTypesBundle = Bundle(path: "/System/Library/CoreServices/CoreTypes.bundle")
        return coreTypesBundle?.image(forResource: "AirDrop")
            ?? NSImage(
                systemSymbolName: "antenna.radiowaves.left.and.right",
                accessibilityDescription: L10n.tr("shelf.airDrop")
            )
            ?? NSImage()
    }()
}

private struct ShelfPasteButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(
                isEnabled
                    ? (configuration.isPressed ? 0.76 : (isHovering ? 1 : 0.88))
                    : 0.32
            )
            .scaleEffect(
                reduceMotion || !isEnabled
                    ? 1
                    : (configuration.isPressed ? 0.96 : (isHovering ? 1.02 : 1))
            )
            .contentShape(Capsule())
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isHovering = isEnabled
                case .ended:
                    isHovering = false
                }
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.92),
                value: isHovering
            )
            .animation(
                reduceMotion ? nil : .spring(response: 0.14, dampingFraction: 0.94),
                value: configuration.isPressed
            )
    }
}

private struct ShelfActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(isEnabled ? 0.76 : 0.24))
            .frame(width: 28, height: 28)
            .background {
                Circle()
                    .fill(.white.opacity(configuration.isPressed ? 0.14 : (isHovering ? 0.09 : 0)))
            }
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.94)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isHovering = isEnabled
                case .ended:
                    isHovering = false
                }
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: isHovering
            )
    }
}

private struct ShelfFileButtonStyle: ButtonStyle {
    let isSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)

        configuration.label
            .background {
                shape.fill(
                    .white.opacity(
                        configuration.isPressed ? 0.14 : (isSelected ? 0.1 : (isHovering ? 0.06 : 0.025))
                    )
                )
            }
            .overlay {
                shape.stroke(
                    .white.opacity(isSelected ? 0.24 : (isHovering ? 0.12 : 0.06)),
                    lineWidth: 0.8
                )
            }
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.97)
            .contentShape(shape)
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isHovering = true
                case .ended:
                    isHovering = false
                }
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.14),
                value: isHovering
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.14),
                value: isSelected
            )
    }
}
