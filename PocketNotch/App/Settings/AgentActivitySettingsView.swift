import AgentEventModule
import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct AgentActivitySettingsView: View {
    @ObservedObject var controller: AgentActivityController
    @ObservedObject var eventCounter: AgentEventCounter
    @ObservedObject var petController: AgentPetController
    @State private var petError: String?
    @State private var isShowingCustomPetEditor = false

    init(controller: AgentActivityController) {
        self.controller = controller
        self.eventCounter = controller.eventCounter
        self.petController = controller.petController
    }

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { controller.settings.isEnabled },
            set: { controller.setEnabled($0) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsHeaderLayout.cardSpacing) {
                header
                    .padding(.bottom, SettingsHeaderLayout.surroundingPadding)
                enableCard
                agentCard
                petLibraryCard
                petAssignmentCard
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .settingsDetailScrolling()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { controller.refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshStatus()
        }
        .alert("settings.agent.petOperationFailed", isPresented: Binding(
            get: { petError != nil },
            set: { if !$0 { petError = nil } }
        )) {
            Button("settings.common.ok") { petError = nil }
        } message: {
            Text(petError ?? "")
        }
        .sheet(isPresented: $isShowingCustomPetEditor) {
            CustomPetEditorSheet { name, animations in
                do {
                    _ = try petController.createCustomPet(
                        displayName: name,
                        animationURLs: animations
                    )
                } catch {
                    petError = error.localizedDescription
                }
            }
        }
    }

    private var header: some View {
        Color.clear
            .frame(height: SettingsHeaderLayout.placeholderHeight)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 12) {
                    Button("settings.common.refresh") {
                        controller.refreshStatus()
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.borderless)

                    SettingsResetButton(isDisabled: controller.settings.usesDefaultValues) {
                        controller.settings.resetToDefault()
                        controller.setEnabled(false)
                    }
                }
                .offset(y: SettingsHeaderLayout.resetButtonOffset)
            }
    }

    private var enableCard: some View {
        SettingsCard {
            HStack(spacing: 12) {
                HStack(spacing: AppearanceRowLayout.titleDescriptionSpacing) {
                    Text("settings.agent.enableAgentActivity")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    statusBadge
                }
                Spacer(minLength: 8)
                Toggle("settings.agent.enableAgentActivity", isOn: isEnabled)
                    .labelsHidden()
                    .toggleStyle(SettingsCompactSwitchToggleStyle())
                    .frame(width: 44, height: 44)
                    .accessibilityHint("settings.agent.enableAgentActivity.description")
            }
            .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)

            AppearanceRowDivider()

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("settings.agent.collectedEvents")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("\(eventCounter.count)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)
        }
    }

    private var statusBadge: some View {
        Text(controller.isRunning ? "settings.common.running" : "settings.common.closed")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(controller.isRunning ? Color.green : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(controller.isRunning ? Color.green.opacity(0.14) : Color.secondary.opacity(0.10))
            }
            .animation(.easeOut(duration: 0.16), value: controller.isRunning)
    }

    private var agentCard: some View {
        SettingsCard {
            ForEach(Array(controller.agentStatuses.enumerated()), id: \.element.id) { index, status in
                agentRow(status)
                if index < controller.agentStatuses.count - 1 {
                    AppearanceRowDivider()
                }
            }
        }
    }

    private var petLibraryCard: some View {
        SettingsCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings.agent.petLibrary")
                        .font(.system(size: 12, weight: .semibold))
                    Text("settings.agent.petLibrary.description")
                        .settingsNoteStyle()
                }
                Spacer(minLength: 12)
                Button {
                    importPet()
                } label: {
                    Label("settings.agent.importPetPackage", systemImage: "archivebox")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button {
                    isShowingCustomPetEditor = true
                } label: {
                    Label("settings.agent.customStateGif", systemImage: "film.stack")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            AppearanceRowDivider()

            if petController.pets.isEmpty {
                Text("settings.agent.noPetAvailable")
                    .settingsNoteStyle()
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(petController.pets) { pet in
                        petPreview(pet)
                    }
                }
                .padding(12)
            }

            HStack(spacing: 8) {
                Label(
                    "settings.agent.petLibraryHint",
                    systemImage: "sparkle"
                )
                .settingsNoteStyle()
                Spacer(minLength: 12)
                Button {
                    openPetdex()
                } label: {
                    Label("settings.agent.openPetdex", systemImage: "safari")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("settings.agent.openPetdex.help")
            }
        }
    }

    private func openPetdex() {
        guard let url = URL(string: "https://petdex.dev") else { return }
        NSWorkspace.shared.open(url)
    }

    private var petAssignmentCard: some View {
        SettingsCard {
            Text("settings.agent.petIconSettings")
                .font(.system(size: 12, weight: .semibold))
                .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)

            AppearanceRowDivider()

            ForEach(Array(AgentIdentity.allCases.enumerated()), id: \.element.id) { index, agent in
                petRow(agent)
                if index < AgentIdentity.allCases.count - 1 {
                    AppearanceRowDivider()
                }
            }
        }
    }

    private func petPreview(_ pet: PetDescriptor) -> some View {
        VStack(alignment: .center, spacing: 4) {
            PetPreviewView(pet: pet)
                .frame(maxWidth: .infinity)
                .frame(height: 50)

            Text(pet.manifest.displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .center)

            Text(petCategoryLabel(for: pet))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(format: NSLocalizedString("settings.agent.petAccessibilityLabelFormat", comment: ""), pet.manifest.displayName, petCategoryLabel(for: pet))))
    }

    private func petCategoryLabel(for pet: PetDescriptor) -> String {
        pet.sourceLabel
    }

    private func petRow(_ agent: AgentIdentity) -> some View {
        HStack(spacing: 12) {
            Text(agent.displayName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 120, alignment: .leading)

            Picker(LocalizedStringKey(String(format: NSLocalizedString("settings.agent.petPickerFormat", comment: ""), agent.displayName)), selection: Binding(
                get: { petController.selectedPetID(for: agent) ?? "" },
                set: { petController.selectPet(id: $0.isEmpty ? nil : $0, for: agent) }
            )) {
                Text("settings.agent.defaultPet").tag("")
                ForEach(petController.pets) { pet in
                    Text(petTitle(pet)).tag(pet.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button {
                    petController.applyPetToAll(
                        id: petController.selectedPet(for: agent.rawValue)?.id
                    )
                } label: {
                    Label("settings.agent.applyToAllAgents", systemImage: "person.3")
                }
                if let selectedPet = petController.selectedPet(for: agent.rawValue),
                   selectedPet.source.isAgentExternal {
                    Divider()
                    Button {
                        do {
                            let imported = try petController.importPet(from: selectedPet.packageURL)
                            petController.selectPet(id: imported.id, for: agent)
                        } catch {
                            petError = error.localizedDescription
                        }
                    } label: {
                        Label("settings.agent.importToPocketNotch", systemImage: "square.and.arrow.down")
                    }
                }
                if let selectedPet = petController.selectedPet(for: agent.rawValue),
                   selectedPet.isRemovable {
                    Divider()
                    Button(role: .destructive) {
                        do {
                            try petController.deletePet(selectedPet)
                        } catch {
                            petError = error.localizedDescription
                        }
                    } label: {
                        Label { Text(String(format: NSLocalizedString("settings.agent.deletePetFormat", comment: ""), selectedPet.manifest.displayName)) } icon: { Image(systemName: "trash") }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 44, height: 44)
            }
            .menuStyle(.borderlessButton)
            .help("settings.agent.morePetActions")
        }
        .frame(minHeight: 60)
    }

    private func petTitle(_ pet: PetDescriptor) -> String {
        String(format: NSLocalizedString("settings.agent.petTitleFormat", comment: ""), pet.manifest.displayName, pet.sourceLabel)
    }

    private func importPet() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip]
        panel.prompt = NSLocalizedString("settings.agent.importPrompt", comment: "")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try petController.importPet(from: url)
        } catch {
            petError = error.localizedDescription
        }
    }

    private func agentRow(_ status: AgentHookStatus) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(status.agent.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    agentStabilityBadge(status)
                }
                Text(detailText(for: status))
                    .settingsNoteStyle()
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(LocalizedStringKey(String(format: NSLocalizedString("settings.agent.senseAgentFormat", comment: ""), status.agent.displayName)), isOn: Binding(
                get: { status.isInstalled && !status.needsAuthorization },
                set: { controller.setAgentEnabled($0, for: status.agent) }
            ))
            .labelsHidden()
            .toggleStyle(SettingsCompactSwitchToggleStyle())
            .frame(width: 44, height: 44)
            .disabled(!status.isDetected || controller.isBusy)
        }
        .frame(height: 60, alignment: .center)
    }

    private func agentStabilityBadge(_ status: AgentHookStatus) -> some View {
        if status.agent.isStableSupport {
            Text("settings.agent.stable")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.10)))
        } else {
            Text("settings.agent.beta")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.12)))
        }
    }

    private func detailText(for status: AgentHookStatus) -> String {
        if status.agent == .codex, status.needsAuthorization {
            return NSLocalizedString("settings.agent.needsReauth", comment: "")
        }
        if let note = status.note {
            return note
        }
        if status.isInstalled {
            return status.agent.isStableSupport
                ? NSLocalizedString("settings.agent.enabledRestartTerminal", comment: "")
                : status.agent == .codex
                    ? NSLocalizedString("settings.agent.enabledRestartCodex", comment: "")
                    : NSLocalizedString("settings.agent.enabledEventNameMayVary", comment: "")
        }
        return status.agent.isStableSupport
            ? NSLocalizedString("settings.agent.disabledStable", comment: "")
            : NSLocalizedString("settings.agent.disabledBeta", comment: "")
    }



    private var noticeSymbol: String {
        return (controller.notice?.isError ?? false) ? "exclamationmark.triangle" : "sparkles"
    }

    private var noticeTint: Color {
        return (controller.notice?.isError ?? false) ? Color.red : Color.secondary
    }
}

private struct CustomPetEditorSheet: View {
    let onSave: (String, [PetAnimationState: URL]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = NSLocalizedString("settings.agent.defaultPetName", comment: "")
    @State private var selections: [PetAnimationState: URL] = [:]
    @State private var error: String?

    /// 编辑器展示的状态；空闲与左右移动自动复用「执行工具」动图。
    private let editorStates: [PetAnimationState] = PetAnimationState.allCases.filter {
        $0 != .idle && $0 != .runningRight && $0 != .runningLeft
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings.agent.customStateGif")
                        .font(.title3.weight(.semibold))
                    Text("settings.agent.customStateGif.description")
                        .settingsNoteStyle()
                }
                Spacer()
                Button("settings.common.cancel") { dismiss() }
                    .buttonStyle(.borderless)
            }

            TextField("settings.agent.petName", text: $name)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(editorStates, id: \.self) { state in
                        HStack(spacing: 12) {
                            Text(state.displayName)
                                .frame(width: 90, alignment: .leading)
                            Text(selections[state]?.lastPathComponent ?? NSLocalizedString("settings.common.notSelected", comment: ""))
                                .foregroundStyle(selections[state] == nil ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("settings.common.choose") { chooseFile(for: state) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        .frame(minHeight: 44)
                        if state != editorStates.last {
                            AppearanceRowDivider()
                        }
                    }
                }
            }
            .frame(maxHeight: 390)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("settings.agent.createPet") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selections.count != editorStates.count)
            }
        }
        .padding(24)
        .frame(width: 540, height: 610)
    }

    private func chooseFile(for state: PetAnimationState) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.gif, .webP, .png]
        panel.prompt = NSLocalizedString("settings.common.choose", comment: "")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selections[state] = url
        error = nil
    }

    private func save() {
        guard selections.count == editorStates.count else {
            error = NSLocalizedString("settings.agent.selectGifForState", comment: "")
            return
        }
        var animations = selections
        if let running = animations[.running] {
            animations[.idle] = running
            animations[.runningRight] = running
            animations[.runningLeft] = running
        }
        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), animations)
        dismiss()
    }
}
