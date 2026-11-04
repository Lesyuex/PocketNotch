import AppKit
import PocketNotchShared
import SwiftUI

struct AgentSessionHistoryView: View {
    private struct AgentFilter: Identifiable, Hashable {
        let id: String
        let title: String
        let symbolName: String
    }

    private enum Layout {
        static let sidebarWidth: CGFloat = 112
        static let separatorGap: CGFloat = 16
    }

    @ObservedObject var store: AgentSessionHistoryStore
    @ObservedObject var eventCounter: AgentEventCounter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedAgentID = "all"
    @State private var hoveredAgentID: String?
    @State private var selectedSessionID: String?
    @State private var statusReferenceDate = Date()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Layout.sidebarWidth)

            Rectangle()
                .fill(.white.opacity(0.07))
                .frame(width: 1)
                .padding(.vertical, 8)
                .padding(.horizontal, Layout.separatorGap)

            historyPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            store.reload()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                statusReferenceDate = Date()
            }
        }
        .onChange(of: eventCounter.count) { _, _ in
            store.reload()
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: selectedAgentID
        )
    }

    private var filters: [AgentFilter] {
        let known = [
            AgentFilter(id: "all", title: L10n.tr("agent.filterAll"), symbolName: "square.stack.3d.up.fill"),
            AgentFilter(id: "codex", title: "Codex", symbolName: "terminal.fill"),
            AgentFilter(id: "claude", title: "Claude", symbolName: "text.bubble.fill"),
            AgentFilter(id: "gemini", title: "Gemini", symbolName: "diamond.fill"),
        ]
        let knownIDs = Set(known.map(\.id))
        let discovered = Set(store.sessions.map(\.agentID))
            .subtracting(knownIDs)
            .filter { $0 != "unknown" }
            .sorted()
            .map {
                AgentFilter(id: $0, title: displayName(for: $0), symbolName: "cpu.fill")
            }
        return known + discovered
    }

    private var filteredSessions: [AgentHistorySession] {
        guard selectedAgentID != "all" else { return store.sessions }
        return store.sessions.filter { $0.agentID == selectedAgentID }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AGENT")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.34))
                .padding(.horizontal, 8)
                .frame(height: 24, alignment: .leading)

            ForEach(filters) { filter in
                filterButton(filter)
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func filterButton(_ filter: AgentFilter) -> some View {
        let isSelected = selectedAgentID == filter.id
        let isHovering = hoveredAgentID == filter.id

        return Button {
            selectedAgentID = filter.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: filter.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(agentTint(for: filter.id).opacity(isSelected ? 1 : 0.66))
                    .frame(width: 14)

                Text(filter.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(isSelected ? 0.96 : 0.58))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(sessionCount(for: filter.id))")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(isSelected ? 0.58 : 0.28))
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.09 : (isHovering ? 0.05 : 0)))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: 44)
        .onHover { hovering in
            hoveredAgentID = hovering ? filter.id : (hoveredAgentID == filter.id ? nil : hoveredAgentID)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var historyPanel: some View {
        VStack(spacing: 0) {
            historyHeader

            Group {
                if store.isLoading, store.sessions.isEmpty {
                    loadingState
                } else if let errorMessage = store.errorMessage, store.sessions.isEmpty {
                    errorState(errorMessage)
                } else if filteredSessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .id(selectedAgentID)
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var historyHeader: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedAgentID == "all" ? L10n.tr("agent.statusHistory") : displayName(for: selectedAgentID))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))

                Text(verbatim: String(format: L10n.tr("agent.sessionCount"), filteredSessions.count))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.36))
            }

            Spacer(minLength: 0)

            Button {
                store.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.64))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .help(L10n.tr("agent.refreshSessions"))
            .accessibilityLabel(L10n.tr("agent.refreshSessions"))
        }
        .frame(height: 44)
    }

    private var sessionList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(filteredSessions.enumerated()), id: \.element.id) { index, session in
                    AgentHistorySessionRow(
                        session: session,
                        now: statusReferenceDate,
                        isSelected: selectedSessionID == session.id,
                        onSelect: {
                            selectedSessionID = session.id
                            AgentSessionApplicationLauncher.activateSource(of: session)
                        }
                    )

                    if index < filteredSessions.count - 1 {
                        Rectangle()
                            .fill(.white.opacity(0.06))
                            .frame(height: 1)
                            .padding(.leading, 38)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var loadingState: some View {
        ProgressView()
            .controlSize(.small)
            .tint(.white.opacity(0.62))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.orange.opacity(0.84))
            Text("agent.loadHistoryFailed")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
            Text(message)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.36))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
            Text(verbatim: selectedAgentID == "all" ? L10n.tr("agent.noAISessions") : String(format: L10n.tr("agent.noAgentSession"), displayName(for: selectedAgentID)))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sessionCount(for agentID: String) -> Int {
        agentID == "all"
            ? store.sessions.count
            : store.sessions.filter { $0.agentID == agentID }.count
    }
}

private struct AgentHistorySessionRow: View {
    let session: AgentHistorySession
    let now: Date
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(agentTint(for: session.agentID).opacity(0.12))
                Image(systemName: agentSymbol(for: session.agentID))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(agentTint(for: session.agentID).opacity(0.9))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayName(for: session.agentID))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    Label(statusTitle, systemImage: statusSymbol)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(statusTint.opacity(0.9))
                        .labelStyle(.titleAndIcon)

                    Spacer(minLength: 8)

                    Text(relativeTimestamp)
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.32))
                        .fixedSize()
                }

                HStack(spacing: 8) {
                    Text(summary)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 0)

                    Text(verbatim: String(format: L10n.tr("agent.eventCount"), session.events.count))
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.28))
                        .fixedSize()

                    if canActivateSource {
                        Image(systemName: "arrow.up.forward.app.fill")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(isSelected ? 0.72 : 0.38))
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 52)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.10 : (isHovering ? 0.045 : 0)))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: L10n.tr("agent.sessionAccessibility"), displayName(for: session.agentID), summary))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: L10n.tr("agent.selectAndJumpToSource"), onSelect)
    }

    private var canActivateSource: Bool {
        AgentSessionApplicationLauncher.canActivateSource(of: session)
    }

    private var status: AgentHistorySessionStatus {
        session.status(at: now)
    }

    private var statusTitle: String {
        switch status {
        case .started: L10n.tr("agent.statusStarted")
        case .active: L10n.tr("agent.statusActive")
        case .waitingApproval: L10n.tr("agent.statusWaitingApproval")
        case .completed: L10n.tr("agent.statusCompleted")
        case .failed: L10n.tr("agent.statusFailed")
        case .closed: L10n.tr("agent.statusClosed")
        case .unknown: L10n.tr("agent.statusUnknown")
        }
    }

    private var statusSymbol: String {
        switch status {
        case .started: "play.circle.fill"
        case .active: "circle.fill"
        case .waitingApproval: "hand.raised.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .closed: "stop.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private var statusTint: Color {
        switch status {
        case .completed: .green
        case .failed: .red
        case .waitingApproval: .orange
        case .closed, .unknown: .gray
        default: .cyan
        }
    }

    private var summary: String {
        session.latestPrompt ?? String(format: L10n.tr("agent.sessionFallback"), session.sessionID)
    }

    private var relativeTimestamp: String {
        Self.relativeFormatter.localizedString(for: session.lastTransitionAt, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter
    }()
}

@MainActor
private enum AgentSessionApplicationLauncher {
    static func canActivateSource(of session: AgentHistorySession) -> Bool {
        runningSourceApplication(of: session) != nil
    }

    static func activateSource(of session: AgentHistorySession) {
        guard let application = runningSourceApplication(of: session) else { return }
        application.activate(options: [.activateAllWindows])
    }

    private static func runningSourceApplication(
        of session: AgentHistorySession
    ) -> NSRunningApplication? {
        guard let bundleIdentifier = session.sourceBundleIdentifier,
              !bundleIdentifier.isEmpty,
              bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }
        return NSWorkspace.shared.runningApplications.first {
            !$0.isTerminated
                && $0.activationPolicy == .regular
                && $0.bundleIdentifier == bundleIdentifier
        }
    }
}

private func displayName(for agentID: String) -> String {
    switch agentID {
    case "codex": "Codex"
    case "claude": "Claude"
    case "gemini": "Gemini"
    case "unknown": "未知 Agent"
    default: agentID.prefix(1).uppercased() + agentID.dropFirst()
    }
}

private func agentSymbol(for agentID: String) -> String {
    switch agentID {
    case "codex": "terminal.fill"
    case "claude": "text.bubble.fill"
    case "gemini": "diamond.fill"
    default: "cpu.fill"
    }
}

private func agentTint(for agentID: String) -> Color {
    switch agentID {
    case "codex": .green
    case "claude": .orange
    case "gemini": .blue
    case "all": .white
    default: .cyan
    }
}
