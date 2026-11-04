import AgentEventModule
import PocketNotchCore
import SwiftUI

/// Agent 选择弹层：开启启 AfterAgent 感知后选择要感知的 Agent。
struct AgentSelectionView: View {
    @ObservedObject var coordinator: PermissionCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private enum Layout {
        static let width: CGFloat = 335
        static let height: CGFloat = 460
        static let cornerRadius: CGFloat = 24
        static let horizontalPadding: CGFloat = 30
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.top, 30)
                .padding(.bottom, 24)

            Group {
                if coordinator.detectedAgentStatuses.isEmpty {
                    emptyState
                } else {
                    agentList
                }
            }
            .padding(.horizontal, Layout.horizontalPadding)

            Spacer(minLength: 12)

            HStack(spacing: 0) {
                Spacer()
                Button("settings.common.done") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(minWidth: 54, minHeight: 26)
                .contentShape(Rectangle())
                .background { glassButtonBackground(cornerRadius: 9) }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, 30)
        }
        .frame(width: Layout.width, height: Layout.height)
        .background { panelBackground }
        .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(red: 0.42, green: 0.72, blue: 1.0))
                .frame(width: 44, height: 44)
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color(red: 0.16, green: 0.31, blue: 0.56).opacity(0.85))
                }

            VStack(spacing: 4) {
                Text("permissions.selectAgent")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)

                Text("permissions.selectAgent.description")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var agentList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(coordinator.detectedAgentStatuses) { status in
                    agentRow(status)
                }
            }
        }
        .frame(maxHeight: 210)
    }

    private func agentRow(_ status: AgentHookStatus) -> some View {
        HStack(spacing: 12) {
            AnimatedAgentInstallerIcon(
                symbolName: agentSymbol(for: status.agent),
                foreground: iconPalette(for: status.agent).foreground,
                background: iconPalette(for: status.agent).background,
                isActive: true
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(status.agent.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)

                Text(agentStatusText(status))
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            agentToggle(status)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.10))
        }
    }

    @ViewBuilder
    private func agentToggle(_ status: AgentHookStatus) -> some View {
        Toggle(LocalizedStringKey(String(format: NSLocalizedString("permissions.senseAgentFormat", comment: ""), status.agent.displayName)), isOn: Binding(
            get: { status.isInstalled && !status.needsAuthorization },
            set: { coordinator.setAgentEnabled($0, for: status.agent) }
        ))
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.mini)
        .frame(minWidth: 44, minHeight: 44)
        .disabled(coordinator.isInstallingAgentPlugin)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            Text("permissions.noAgentDetected")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)

            Text("permissions.noAgentDetected.description")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.10))
        }
    }

    private func agentStatusText(_ status: AgentHookStatus) -> String {
        if status.agent == .codex, status.needsAuthorization {
            return NSLocalizedString("permissions.needsReauth", comment: "")
        }
        if status.isInstalled {
            return NSLocalizedString("permissions.agentEnabled", comment: "")
        }
        return status.agent.isStableSupport ? NSLocalizedString("permissions.agentDisabledStable", comment: "") : NSLocalizedString("permissions.agentDisabledBeta", comment: "")
    }

    private func agentSymbol(for agent: AgentHookAgent) -> String {
        switch agent {
        case .claude: "terminal"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .gemini: "sparkles"
        }
    }

    private func iconPalette(for agent: AgentHookAgent) -> (foreground: Color, background: Color) {
        switch agent {
        case .claude:
            return (
                Color(red: 0.82, green: 0.35, blue: 0.15),
                Color(red: 1.0, green: 0.94, blue: 0.90)
            )
        case .codex:
            return (
                Color(red: 0.17, green: 0.43, blue: 0.84),
                Color(red: 0.91, green: 0.95, blue: 1.0)
            )
        case .gemini:
            return (
                Color(red: 0.43, green: 0.32, blue: 0.82),
                Color(red: 0.95, green: 0.93, blue: 1.0)
            )
        }
    }

    @ViewBuilder
    private var panelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
        if reduceTransparency {
            shape.fill(.ultraThinMaterial)
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.92), lineWidth: 1)
                }
        } else if #available(macOS 26.0, *), SystemVersionService.shared.isMacOS26OrLater {
            ZStack {
                shape.fill(.clear)
                shape.glassEffect(.regular, in: shape)
                shape.fill(.black.opacity(0.30))
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            }
        } else {
            ZStack {
                SystemMaterialBackdrop(material: .underWindowBackground)
                shape.fill(.black.opacity(0.30))
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func glassButtonBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            shape.fill(.white.opacity(0.2))
        } else if #available(macOS 26.0, *), SystemVersionService.shared.isMacOS26OrLater {
            shape.fill(.clear)
            shape.glassEffect(.regular, in: shape)
        } else {
            SystemMaterialBackdrop(material: .underWindowBackground)
                .clipShape(shape)
        }
    }
}

private struct AnimatedAgentInstallerIcon: View {
    let symbolName: String
    let foreground: Color
    let background: Color
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var float = false
    @State private var glow = false
    @State private var scan = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(background)

            if isActive {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(foreground.opacity(0.26), lineWidth: 1.2)
                    .scaleEffect(pulse ? 1.16 : 0.9)
                    .opacity(pulse ? 0 : 0.72)
            }

            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.white.opacity(0.72))
                .padding(4)

            if showsScanBeam {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    foreground.opacity(0.08),
                                    foreground.opacity(0.34),
                                    foreground.opacity(0.08),
                                    .clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 12, height: 34)
                        .blur(radius: 0.3)
                        .offset(x: scan ? 13 : -13)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .mask {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .padding(4)
                        }
                }
                .allowsHitTesting(false)
            }

            Image(systemName: symbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(foreground)
                .offset(y: reduceMotion ? 0 : (float ? -1.4 : 1.4))
                .scaleEffect(glow ? 1.06 : 0.97)
                .shadow(color: foreground.opacity(glow ? 0.22 : 0.08), radius: glow ? 8 : 3)

            Circle()
                .fill(foreground)
                .frame(width: 7, height: 7)
                .overlay {
                    Circle()
                        .fill(foreground.opacity(0.24))
                        .scaleEffect(glow ? 2.45 : 0.9)
                }
                .offset(x: 14, y: -14)
                .opacity(isActive ? (glow ? 1 : 0.72) : 0.35)
        }
        .frame(width: 46, height: 46)
        .shadow(color: foreground.opacity(0.2), radius: 12, y: 5)
        .onAppear {
            guard isActive, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                pulse = true
            }
            withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
                float = true
            }
            withAnimation(.easeInOut(duration: 0.92).repeatForever(autoreverses: true)) {
                glow = true
            }
            if showsScanBeam {
                withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                    scan = true
                }
            }
        }
    }

    private var showsScanBeam: Bool {
        symbolName == "chevron.left.forwardslash.chevron.right"
    }
}