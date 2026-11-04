import PocketNotchCore
import PocketNotchShared
import SwiftUI

struct MediaPlaybackControls: View {
    var viewModel: NowPlayingViewModel
    var height: CGFloat = 48
    var controlSize: CGFloat = 44
    var visualControlSize: CGFloat?
    var showsOutputPicker = false

    var body: some View {
        HStack(spacing: showsOutputPicker ? 0 : 8) {
            controlSlot {
                capabilityButton(
                    systemName: "shuffle",
                    help: viewModel.isShuffleEnabled ? L10n.tr("media.turnOffShuffle") : L10n.tr("media.turnOnShuffle"),
                    unsupportedHelp: L10n.tr("media.shuffleUnsupported"),
                    isEnabled: viewModel.playbackCapabilities.canShuffle,
                    isSelected: viewModel.isShuffleEnabled,
                    selectedColor: .green,
                    action: {
                        Task { await viewModel.toggleShuffle() }
                    }
                )
            }

            controlSlot {
                previousButton
            }

            controlSlot {
                playButton
            }

            controlSlot {
                controlButton(
                    systemName: "forward.fill",
                    help: L10n.tr("media.next"),
                    action: viewModel.next
                )
            }

            if showsOutputPicker {
                controlSlot {
                    MediaOutputPickerButton(
                        viewModel: viewModel,
                        size: controlSize,
                        visualSize: visualControlSize
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .disabled(viewModel.info == nil)
        .opacity(viewModel.info == nil ? 0.42 : 1)
    }

    private var previousButton: some View {
        controlButton(
            systemName: "backward.fill",
            help: L10n.tr("media.previous"),
            action: viewModel.previous
        )
    }

    private var playButton: some View {
        Button(action: viewModel.togglePlay) {
            Image(systemName: viewModel.info?.isPlaying == true ? "pause.fill" : "play.fill")
        }
        .buttonStyle(
            MediaControlButtonStyle(
                size: controlSize,
                visualSize: visualControlSize,
                isPrimary: true
            )
        )
        .help(viewModel.info?.isPlaying == true ? L10n.tr("media.pause") : L10n.tr("media.play"))
    }

    private func controlButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(
            MediaControlButtonStyle(
                size: controlSize,
                visualSize: visualControlSize
            )
        )
        .help(help)
    }

    private func capabilityButton(
        systemName: String,
        help: String,
        unsupportedHelp: String,
        isEnabled: Bool,
        isSelected: Bool = false,
        selectedColor: Color = .red,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(
            MediaControlButtonStyle(
                size: controlSize,
                visualSize: visualControlSize,
                isSelected: isSelected,
                selectedColor: selectedColor
            )
        )
        .accessibilityLabel(help)
        .accessibilityValue(isSelected ? L10n.tr("media.on") : L10n.tr("media.off"))
        .help(isEnabled ? help : unsupportedHelp)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.56)
    }

    private func controlSlot<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: showsOutputPicker ? .infinity : nil)
    }
}

struct MediaOutputPickerButton: View {
    var viewModel: NowPlayingViewModel
    @State private var isPickerPresented = false
    var size: CGFloat = 44
    var visualSize: CGFloat?
    var usesBorderlessStyle = false
    var borderlessForegroundColor: Color = .white
    var borderlessSelectedColor: Color = .accentColor

    var body: some View {
        styledButton
            .accessibilityLabel("media.selectOutputDevice")
            .accessibilityValue(currentPlaybackDeviceName)
            .help(currentPlaybackDeviceName)
            .popover(isPresented: $isPickerPresented, arrowEdge: .top) {
                MediaOutputPickerPopover(viewModel: viewModel)
            }
            .onChange(of: isPickerPresented) { _, isPresented in
                viewModel.setAudioOutputPickerPresented(isPresented)
            }
            .onAppear(perform: viewModel.refreshAudioOutputDevices)
            .onDisappear {
                if isPickerPresented {
                    isPickerPresented = false
                }
            }
    }

    @ViewBuilder
    private var styledButton: some View {
        if usesBorderlessStyle {
            pickerButton
                .buttonStyle(
                    MediaBorderlessControlButtonStyle(
                        size: size,
                        visualSize: visualSize,
                        isSelected: isPickerPresented,
                        foregroundColor: borderlessForegroundColor,
                        selectedColor: borderlessSelectedColor
                    )
                )
        } else {
            pickerButton
                .buttonStyle(
                    MediaControlButtonStyle(
                        size: size,
                        visualSize: visualSize,
                        isSelected: isPickerPresented,
                        selectedColor: .accentColor
                    )
                )
        }
    }

    private var pickerButton: some View {
        Button {
            viewModel.refreshAudioOutputDevices()
            viewModel.refreshAudioOutputVolume()
            isPickerPresented = true
        } label: {
            Image(systemName: currentPlaybackDeviceSymbolName)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var currentPlaybackDeviceName: String {
        viewModel.currentAudioOutput?.deviceName ?? L10n.tr("media.selectOutputDevice")
    }

    private var currentPlaybackDeviceSymbolName: String {
        viewModel.currentAudioOutput?.deviceSymbolName ?? "airplayaudio"
    }
}

private struct MediaOutputPickerPopover: View {
    var viewModel: NowPlayingViewModel
    @Environment(\.dismiss) private var dismiss

    private let panelWidth: CGFloat = 292
    private let rowHeight: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            volumeControl

            divider

            outputSectionHeader
            deviceList
        }
        .padding(.top, 14)
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.bottom, 14)
        .frame(width: panelWidth)
    }

    // MARK: - 头部

    private var header: some View {
        Text("media.sound")
            .font(.system(size: 12, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
    }

    // MARK: - 音量

    private var volumeControl: some View {
        HStack(spacing: 10) {
            Image(systemName: currentOutputSymbolName)
                .font(.system(size: 12, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)

            Slider(value: volumeBinding, in: 0...1)
                .tint(.white)
                .disabled(viewModel.currentAudioOutputVolume == nil)
                .opacity(viewModel.currentAudioOutputVolume == nil ? 0.45 : 1)
                .accessibilityLabel("media.outputVolume")
                .accessibilityValue(volumeAccessibilityValue)
        }
        .padding(.leading, 6)
        .frame(maxWidth: .infinity, minHeight: 34)
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: {
                guard !viewModel.isCurrentAudioOutputMuted else { return 0 }
                return viewModel.currentAudioOutputVolume ?? 0
            },
            set: viewModel.setAudioOutputVolume
        )
    }

    private var currentOutputSymbolName: String {
        return viewModel.currentAudioOutput?.deviceSymbolName ?? "speaker.wave.2.fill"
    }

    private var volumeAccessibilityValue: String {
        guard let volume = viewModel.currentAudioOutputVolume else { return L10n.tr("media.notAdjustable") }
        if viewModel.isCurrentAudioOutputMuted { return L10n.tr("media.muted") }
        return "\(Int((volume * 100).rounded()))%"
    }

    // MARK: - 分隔与分区

    private var divider: some View {
        IslandPopoverDivider()
            .padding(.leading, 6)
    }

    private var outputSectionHeader: some View {
        Text("media.output")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    // MARK: - 设备列表

    private var deviceList: some View {
        Group {
            if viewModel.availableAudioOutputs.isEmpty {
                Label("media.noOutputDevices", systemImage: "speaker.slash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: rowHeight)
            } else {
                VStack(spacing: 2) {
                    ForEach(viewModel.availableAudioOutputs) { device in
                        deviceRow(for: device)
                    }
                }
            }
        }
    }

    private func deviceRow(for device: AudioOutputDevice) -> some View {
        Button {
            viewModel.selectAudioOutputDevice(device)
            dismiss()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                deviceIcon(for: device)

                Text(device.deviceName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)
            }
            .padding(.leading, 6)
            .frame(maxWidth: .infinity, minHeight: rowHeight)
            .contentShape(Rectangle().inset(by: -2))
        }
        .buttonStyle(MediaOutputDeviceRowStyle())
        .accessibilityValue(device.isCurrent ? L10n.tr("media.currentDevice") : "")
    }

    private func deviceIcon(for device: AudioOutputDevice) -> some View {
        ZStack {
            Circle()
                .fill(device.isCurrent ? Color.white.opacity(0.94) : Color.primary.opacity(0.10))

            Image(systemName: device.deviceSymbolName)
                .font(.system(size: 12, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(device.isCurrent ? Color.accentColor : Color.primary.opacity(0.82))
        }
        .frame(width: 28, height: 28)
    }
}

private struct MediaOutputDeviceRowStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            }
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isHovering = true
                case .ended:
                    isHovering = false
                }
            }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.primary.opacity(0.08)
        }
        if isHovering {
            return Color.primary.opacity(0.05)
        }
        return .clear
    }
}



