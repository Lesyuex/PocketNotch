import AppKit
import PocketNotchShared
import PocketNotchCore
import SwiftUI

struct ApplicationLauncherView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandCollapseAction) private var collapseIsland
    @Environment(ExpandedIslandSearchModel.self) private var searchModel
    @State private var applications: [ApplicationItem] = []
    @State private var hasLoaded = false
    @State private var currentPage: Int? = 0
    @State private var pageDirection = 1
    @State private var icons: [ApplicationItem.ID: NSImage] = [:]
    @State private var revealedIDs: Set<ApplicationItem.ID> = []

    private let columns = Array(
        repeating: GridItem(
            .flexible(minimum: ApplicationPageLayout.iconSize + 8),
            spacing: ApplicationPageLayout.columnSpacing,
            alignment: .top
        ),
        count: ApplicationPageLayout.columnCount
    )

    private var filteredApplications: [ApplicationItem] {
        ApplicationSearchFilter.filter(applications, query: searchModel.text)
    }

    private var searchQuery: String {
        searchModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if !hasLoaded {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.78))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if applications.isEmpty {
                emptyState
            } else if filteredApplications.isEmpty {
                searchEmptyState
            } else {
                applicationGrid
            }
        }
        .padding(.top, ApplicationPageLayout.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            if !hasLoaded {
                let loadedApplications = await Task.detached(priority: .utility) {
                    ApplicationCatalogLoader.load()
                }.value
                guard !Task.isCancelled else { return }
                applications = loadedApplications
                hasLoaded = true
            }
            syncSearchSubmitTarget()
        }
        .onDisappear {
            searchModel.onSubmit = nil
        }
        .onChange(of: searchModel.text) { _, _ in
            syncSearchSubmitTarget()
            currentPage = 0
        }
    }

    private var applicationGrid: some View {
        let pages = ApplicationPageLayout.pages(for: filteredApplications)
        let page = min(currentPage ?? 0, max(pages.count - 1, 0))
        let apps = pages.indices.contains(page) ? pages[page] : []

        return VStack(spacing: ApplicationPageLayout.footerSpacing) {
            ZStack {
                tileGrid(apps)
                    .id(page)
                    .transition(pageTransition)
            }
            .frame(height: ApplicationPageLayout.gridHeight, alignment: .top)
            .clipped()
            .background {
                ApplicationPageSwipeReceiver { direction in
                    selectPage(page + direction, pageCount: pages.count)
                }
            }
            .task(id: apps) {
                await loadIcons(for: apps)
            }

            pageControls(pageCount: pages.count)
        }
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: CGFloat(pageDirection) * 22)),
            removal: .opacity.combined(with: .offset(x: CGFloat(-pageDirection) * 22))
        )
    }

    private func tileGrid(_ apps: [ApplicationItem]) -> some View {
        LazyVGrid(columns: columns, spacing: ApplicationPageLayout.rowSpacing) {
            ForEach(apps) { app in
                ApplicationTile(
                    application: app,
                    icon: revealedIDs.contains(app.id) ? icons[app.id] : nil,
                    launch: launch
                )
            }
        }
        .padding(.horizontal, 4)
        .frame(height: ApplicationPageLayout.gridHeight, alignment: .top)
    }

    @MainActor
    private func loadIcons(for apps: [ApplicationItem]) async {
        revealedIDs.subtract(apps.map(\.id))

        for (index, app) in apps.enumerated() {
            guard !Task.isCancelled else { return }

            let image = await ApplicationIconProvider.icon(
                for: app,
                renderedSize: ApplicationPageLayout.iconSize
            )
            guard !Task.isCancelled else { return }

            icons[app.id] = image
            revealedIDs.insert(app.id)

            guard index < apps.count - 1 else { return }
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                return
            }
        }
    }

    private func pageControls(pageCount: Int) -> some View {
        let selectedPage = min(currentPage ?? 0, max(pageCount - 1, 0))
        let firstDot = max(0, min(selectedPage - 3, pageCount - 7))

        return Group {
            if pageCount > 1 {
                HStack(spacing: 0) {
                    ForEach(firstDot..<min(firstDot + 7, pageCount), id: \.self) { index in
                        Button {
                            selectPage(index, pageCount: pageCount)
                        } label: {
                            Circle()
                                .fill(.white.opacity(index == selectedPage ? 0.9 : 0.3))
                                .frame(width: 7, height: 7)
                                .frame(width: 24, height: ApplicationPageLayout.footerHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(format: L10n.tr("apps.pageIndicator"), index + 1, pageCount))
                        .accessibilityAddTraits(index == selectedPage ? .isSelected : [])
                        .help(String(format: L10n.tr("apps.pageIndicator"), index + 1, pageCount))
                    }
                }
            } else {
                Color.clear
            }
        }
        .frame(height: ApplicationPageLayout.footerHeight)
    }

    @discardableResult
    private func selectPage(_ page: Int, pageCount: Int) -> Bool {
        let current = currentPage ?? 0
        guard (0..<pageCount).contains(page), page != current else { return false }
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.92)) {
            pageDirection = page > current ? 1 : -1
            currentPage = page
        }
        return true
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))

            Text("apps.noApplications")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))

            Text(verbatim: String(format: L10n.tr("apps.searchNotFound"), searchQuery))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func syncSearchSubmitTarget() {
        searchModel.onSubmit = filteredApplications.first.map { app in
            { launch(app) }
        }
    }

    private func launch(_ application: ApplicationItem) {
        collapseIsland?()
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(
            at: application.url,
            configuration: configuration
        )
    }
}

private struct ApplicationTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let application: ApplicationItem
    let icon: NSImage?
    let launch: (ApplicationItem) -> Void

    @State private var isHovering = false
    @State private var isPresented = false

    var body: some View {
        Button {
            launch(application)
        } label: {
            VStack(spacing: ApplicationPageLayout.iconLabelSpacing) {
                tileIcon

                Text(application.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(isHovering ? 1 : 0.82))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
                    .frame(height: ApplicationPageLayout.labelHeight)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: ApplicationPageLayout.tileHeight)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(ApplicationLaunchButtonStyle())
        .onHover { isHovering = $0 }
        .help(String(format: L10n.tr("apps.openApp"), application.name))
        .accessibilityLabel(String(format: L10n.tr("apps.openApp"), application.name))
        .accessibilityHidden(!isPresented)
        .scaleEffect(reduceMotion || isPresented ? 1 : 0.72)
        .opacity(isPresented ? 1 : 0)
        .offset(y: reduceMotion || isPresented ? 0 : 8)
        .allowsHitTesting(isPresented)
        .onChange(of: icon != nil, initial: true) { _, hasIcon in
            if hasIcon {
                present()
            } else {
                isPresented = false
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
    }

    private func present() {
        guard icon != nil, !isPresented else { return }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.12)) {
                isPresented = true
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isPresented = true
            }
        }
    }

    private var tileIcon: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.white.opacity(0.08))
            }
        }
        .frame(width: ApplicationPageLayout.iconSize, height: ApplicationPageLayout.iconSize)
    }
}

private struct ApplicationLaunchButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.96)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 1),
                value: configuration.isPressed
            )
    }
}
