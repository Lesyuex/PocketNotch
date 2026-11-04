import AppKit
import PocketNotchShared
import Foundation
import SwiftUI

struct AgentSessionsView: View {
    @StateObject private var viewModel = AgentSessionsViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedFilter: SessionFilter = .running
    @State private var isBreathing = false


    private var visibleSessions: [AgentSessionInfo] {
        selectedFilter == .running ? viewModel.sessions : []
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            content
        }

        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            viewModel.refresh()
            if !reduceMotion { isBreathing = true }
        }
    }


    private var filterBar: some View {
        HStack(spacing: 8) {
            Picker("agent.sessionFilter", selection: $selectedFilter) {
                ForEach(SessionFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .labelsHidden()
            .fixedSize()

            Spacer(minLength: 0)

            Text(verbatim: String(format: L10n.tr("agent.processCount"), visibleSessions.count))
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.34))
                .fixedSize()

            Button { viewModel.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.035), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.07), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help(L10n.tr("agent.refresh"))
            .accessibilityLabel(L10n.tr("agent.refreshAgentSessions"))
        }
        .padding(.top, 5.5)
        .padding(.bottom, 11)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading, viewModel.sessions.isEmpty {
            ProgressView().controlSize(.small).tint(.white.opacity(0.6)).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage, viewModel.sessions.isEmpty {
            stateView(icon: "exclamationmark.triangle.fill", title: L10n.tr("agent.loadAgentProcessesFailed"), detail: error, tint: .orange)
        } else if visibleSessions.isEmpty {
            stateView(icon: selectedFilter == .history ? "clock.arrow.circlepath" : "cpu", title: selectedFilter == .history ? L10n.tr("agent.noHistorySessions") : L10n.tr("agent.noAgentProcesses"), detail: selectedFilter == .history ? L10n.tr("agent.historySessionsHint") : L10n.tr("agent.agentProcessesHint"), tint: .white.opacity(0.42))
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    ForEach(visibleSessions) { session in
                        AgentSessionCard(session: session, isBreathing: isBreathing, reduceMotion: reduceMotion)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.never)
        }
    }

    private func stateView(icon: String, title: String, detail: String, tint: Color) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundStyle(tint)
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
            Text(detail).font(.system(size: 8.5, weight: .medium)).foregroundStyle(.white.opacity(0.34)).multilineTextAlignment(.center).lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }


}

private enum SessionFilter: String, CaseIterable, Identifiable {
    case running, history
    var id: Self { self }
    var title: String { self == .running ? L10n.tr("agent.statusRunning") : L10n.tr("agent.statusHistory") }
}

private struct AgentSessionCard: View {
    let session: AgentSessionInfo
    let isBreathing: Bool
    let reduceMotion: Bool
    @State private var isHovering = false
    private var meta: AgentMeta { AgentMetaRegistry.meta(for: session.agentName) }
    
    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(meta.displayName).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                    Circle().fill(.white.opacity(0.28)).frame(width: 3, height: 3)
                    HStack(spacing: 3) {
                        Image(systemName: "branch")
                            .font(.system(size: 8, weight: .medium))
                        Text("main")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.white.opacity(0.43))
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(sessionSummary).font(.system(size: 10, weight: .regular)).foregroundStyle(.white.opacity(0.55)).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                parentAppButton
                statusBadge
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.white.opacity(isHovering ? 0.045 : 0))
        }
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { isHovering = hovering } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: L10n.tr("agent.sessionCardAccessibility"), meta.displayName, sessionSummary))
    }
    
    private var avatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.045))
            RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(red: 0.922, green: 0.529, blue: 0.204).opacity(0.275), lineWidth: 0.6)
            Text(meta.initials).font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.9))
            if !reduceMotion {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(red: 0.922, green: 0.529, blue: 0.204).opacity(0.19), lineWidth: 0.8)
                    .scaleEffect(1.1)
                    .opacity(isBreathing ? 0.8 : 0.2)
                    .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: isBreathing)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
    
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.indigo).frame(width: 5.5, height: 5.5).shadow(color: Color.indigo.opacity(0.65), radius: 3)
            Text("agent.statusRunning").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.84))
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.white.opacity(0.045), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.indigo.opacity(0.32), lineWidth: 0.7))
        .fixedSize()
    }
    
    private var sessionSummary: String {
        let name = session.sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? L10n.tr("agent.sessionNameUnavailable") : name
    }
    
    private var parentDisplayName: String {
        let raw = session.parentName
        guard !raw.isEmpty else { return L10n.tr("agent.unknown") }
        if let range = raw.range(of: ".app/") {
            let before = raw[..<range.lowerBound]
            if let slash = before.lastIndex(of: "/") { return String(before[before.index(after: slash)...]) }
            return String(before)
        }
        return (raw as NSString).lastPathComponent
    }
    
    /// 从 parentName（comm 路径）提取 .app 包路径，用于跳转。
    private var parentAppURL: URL? {
        let raw = session.parentName
        guard !raw.isEmpty,
              let range = raw.range(of: ".app/") else { return nil }
        return URL(fileURLWithPath: String(raw[..<range.lowerBound]) + ".app")
    }
    
    /// 读取 .app 包的本地化显示名（如 "Visual Studio Code"），读不到时回退到目录名。
    private var parentAppDisplayName: String {
        if let url = parentAppURL,
           let values = try? url.resourceValues(forKeys: [.localizedNameKey]),
           let name = values.localizedName, !name.isEmpty {
            return name
        }
        return parentDisplayName
    }
    
    private var parentAppButton: some View {
        Button {
            guard let url = parentAppURL else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "app.fill")
                    .font(.system(size: 8, weight: .medium))
                Text(parentAppDisplayName)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.white.opacity(0.045), in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(parentAppURL != nil ? String(format: L10n.tr("agent.showInApp"), parentAppDisplayName) : L10n.tr("agent.parentAppNotFound"))
        .disabled(parentAppURL == nil)
    }
}

private struct AgentMeta {
        let displayName: String
        let initials: String
        let tint: Color
    }
    
    private enum AgentMetaRegistry {
        static func meta(for name: String) -> AgentMeta {
            switch name.lowercased() {
            case "codex": AgentMeta(displayName: "Codex", initials: "CO", tint: Color(red: 0.31, green: 0.85, blue: 0.55))
            case "claude": AgentMeta(displayName: "Claude", initials: "CL", tint: Color(red: 0.95, green: 0.62, blue: 0.35))
            case "gemini": AgentMeta(displayName: "Gemini", initials: "GE", tint: Color(red: 0.40, green: 0.66, blue: 0.95))
            case "grok": AgentMeta(displayName: "Grok", initials: "GR", tint: Color(red: 0.72, green: 0.48, blue: 0.95))
            case "opencode": AgentMeta(displayName: "OpenCode", initials: "OC", tint: Color(red: 0.36, green: 0.82, blue: 0.88))
            case "hermes": AgentMeta(displayName: "Hermes", initials: "HE", tint: Color(red: 0.94, green: 0.45, blue: 0.62))
            case "pi": AgentMeta(displayName: "PI", initials: "PI", tint: Color(red: 0.58, green: 0.55, blue: 0.95))
            default: AgentMeta(displayName: name.capitalized, initials: String(name.prefix(2)).uppercased(), tint: .gray)
            }
        }
    }

