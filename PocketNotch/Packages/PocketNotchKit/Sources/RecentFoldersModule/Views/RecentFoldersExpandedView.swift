import AppKit
import PocketNotchShared
import SwiftUI

enum RecentFoldersLayout {
    static let topInset: CGFloat = 8
    static let headerHeight: CGFloat = 28
    static let rowSpacing: CGFloat = 8
    static let columnSpacing: CGFloat = 12
    static let iconSize: CGFloat = 40
    static let iconLabelSpacing: CGFloat = 4
    static let labelHeight: CGFloat = 11
    static let tileHeight = iconSize + iconLabelSpacing + labelHeight
    static let cornerRadius: CGFloat = 10
}

struct RecentFoldersExpandedView: View {
    let viewModel: RecentFoldersViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: RecentFoldersLayout.rowSpacing) {
            header

            if viewModel.folders.isEmpty {
                emptyState
            } else {
                folderGrid
            }
        }
        .padding(.top, RecentFoldersLayout.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            Text("folders.title")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            Text("\(viewModel.folders.count)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background {
                    Capsule()
                        .fill(.white.opacity(0.08))
                }

            Spacer(minLength: 8)

            Text("folders.clickToOpen")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.38))

            Button(action: { viewModel.reload() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(RecentFoldersActionButtonStyle())
            .onHover { hovered in
                _ = hovered
            }
            .help("folders.refresh")
            .accessibilityLabel("folders.refresh")
        }
        .frame(height: RecentFoldersLayout.headerHeight)
    }

    private var folderGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: 72),
                        spacing: RecentFoldersLayout.columnSpacing
                    )
                ],
                alignment: .center,
                spacing: RecentFoldersLayout.rowSpacing
            ) {
                ForEach(viewModel.folders) { folder in
                    RecentFolderTile(folder: folder, viewModel: viewModel)
                }
            }
            .padding(.horizontal, 1)
            .padding(.bottom, RecentFoldersLayout.rowSpacing)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.42))

            Text("folders.empty")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.66))

            Text("folders.emptyDetail")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RecentFolderTile: View {
    let folder: RecentFolder
    let viewModel: RecentFoldersViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button {
            openInFinder()
        } label: {
            VStack(spacing: RecentFoldersLayout.iconLabelSpacing) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: folder.url.path))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(
                        width: RecentFoldersLayout.iconSize,
                        height: RecentFoldersLayout.iconSize
                    )
                    .overlay(alignment: .topTrailing) {
                        if viewModel.isLocked(folder) {
                            lockBadge
                        }
                    }

                Text(folder.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(isHovering ? 1 : 0.82))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: RecentFoldersLayout.labelHeight)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: RecentFoldersLayout.tileHeight)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(RecentFoldersTileButtonStyle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("folders.openInFinder") { openInFinder() }
            Divider()
            Button(viewModel.isLocked(folder) ? "folders.unlock" : "folders.lock") {
                viewModel.toggleLocked(folder)
            }
        }
        .help(String(format: L10n.tr("folders.openInFinderHelp"), folder.name))
        .accessibilityLabel(String(format: L10n.tr("folders.openInFinderHelp"), folder.name))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
    }

    private func openInFinder() {
        NSWorkspace.shared.open(folder.url)
    }

    private var lockBadge: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(3)
            .background {
                Circle().fill(.black.opacity(0.3))
            }
            .padding(.top, -2)
            .padding(.trailing, -2)
    }
}

private struct RecentFoldersTileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: RecentFoldersLayout.cornerRadius, style: .continuous)

        configuration.label
            .background {
                shape.fill(
                    .white.opacity(
                        configuration.isPressed ? 0.12 : (isHovering ? 0.06 : 0.02)
                    )
                )
            }
            .overlay {
                shape.stroke(
                    .white.opacity(isHovering ? 0.1 : 0.05),
                    lineWidth: 0.5
                )
            }
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.96)
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
                reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 1),
                value: configuration.isPressed
            )
    }
}

private struct RecentFoldersActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(isEnabled ? 0.72 : 0.24))
            .background {
                Circle()
                    .fill(.white.opacity(configuration.isPressed ? 0.14 : (isHovering ? 0.09 : 0)))
            }
            .scaleEffect(reduceMotion || !isEnabled ? 1 : (configuration.isPressed ? 0.94 : (isHovering ? 1.04 : 1)))
            .contentShape(Circle())
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