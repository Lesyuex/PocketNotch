import AppKit
import PocketNotchCore
import PocketNotchShared
import SwiftUI

enum ExpandedMediaMetadataDesign {
    static let height: CGFloat = 40
    static let accessoryWidth: CGFloat = 28
    static let accessoryDiameter: CGFloat = 22
    static let accessoryHeight: CGFloat = 34
}

private enum ExpandedMediaLayout {
    static let artworkSize: CGFloat = 128
    static let panelSpacing: CGFloat = 12
    static let remainingTimeWidth: CGFloat = 44
    static let progressLabelHeight: CGFloat = 18
    static let progressSectionHeight: CGFloat = 30
    static let controlBarHeight: CGFloat = 40
    static let secondaryControlSize: CGFloat = 44
    static let controlVisualSize: CGFloat = 40
    static let metadataHeight = ExpandedMediaMetadataDesign.height
    static let playerPanelHeight = artworkSize
    static let availableModuleSpacing = max(
        playerPanelHeight - metadataHeight - progressSectionHeight - controlBarHeight,
        0
    )
    static let controlBackgroundUpperHalfHeight = controlVisualSize / 2
    static let progressToControlsSpacing = max(
        (availableModuleSpacing - controlBackgroundUpperHalfHeight) / 2,
        0
    ) + 2
    static let metadataToProgressSpacing = availableModuleSpacing - progressToControlsSpacing
}

struct NowPlayingExpandedView: View {
    var viewModel: NowPlayingViewModel

    var body: some View {
        return HStack(spacing: ExpandedMediaLayout.panelSpacing) {
            artworkPanel
            playerPanel
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var artworkPanel: some View {
        MediaLaunchableArtwork(
            viewModel: viewModel,
            fallbackSystemName: viewModel.info?.isPlaying == true ? "waveform.circle.fill" : "music.note",
            size: ExpandedMediaLayout.artworkSize,
            cornerRadius: 16,
            applicationBadgeOffset: 5
        )
        .shadow(color: accentColor.opacity(0.18), radius: 16, y: 8)
    }

    private var playerPanel: some View {
        // Reserve the controls' upper half before splitting any excess space.
        VStack(alignment: .leading, spacing: 0) {
            metadata
            Spacer(minLength: 0)
                .frame(height: ExpandedMediaLayout.metadataToProgressSpacing)
            progressSection
                .frame(
                    maxWidth: .infinity,
                    minHeight: ExpandedMediaLayout.progressSectionHeight,
                    maxHeight: ExpandedMediaLayout.progressSectionHeight
                )
            Spacer(minLength: 0)
                .frame(height: ExpandedMediaLayout.progressToControlsSpacing)
            playbackControls
        }
        .frame(
            maxWidth: .infinity,
            minHeight: ExpandedMediaLayout.playerPanelHeight,
            maxHeight: ExpandedMediaLayout.playerPanelHeight,
            alignment: .topLeading
        )
    }

    private var metadata: some View {
        ExpandedMediaMetadataView(viewModel: viewModel)
    }

    @ViewBuilder
    private var progressSection: some View {
        if let info = viewModel.info {
            ExpandedMediaProgressView(
                info: info,
                colors: viewModel.spectrumColors,
                onSeek: viewModel.seek
            )
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.12))
                    .frame(height: 4)

                Text("media.waitingForMedia")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }
        }
    }

    private var playbackControls: some View {
        MediaPlaybackControls(
            viewModel: viewModel,
            height: ExpandedMediaLayout.controlBarHeight,
            controlSize: ExpandedMediaLayout.secondaryControlSize,
            visualControlSize: ExpandedMediaLayout.controlVisualSize,
            showsOutputPicker: true
        )
    }

    private var accentColor: Color {
        viewModel.spectrumColors.first ?? .white
    }
}

struct ExpandedMediaMetadataContent<Accessory: View>: View {
    let title: String
    let detail: String
    let titleColor: Color
    let detailColor: Color
    let titleFont: Font
    let titleNSFont: NSFont
    let detailFont: Font
    let detailNSFont: NSFont
    let showsAccessory: Bool
    let accessory: Accessory

    init(
        title: String,
        detail: String,
        titleColor: Color = MediaMetadataStyle.titleColor,
        detailColor: Color = MediaMetadataStyle.detailColor,
        titleFont: Font = MediaMetadataStyle.expandedTitleFont,
        titleNSFont: NSFont = MediaMetadataStyle.expandedTitleNSFont,
        detailFont: Font = MediaMetadataStyle.detailFont,
        detailNSFont: NSFont = MediaMetadataStyle.detailNSFont,
        showsAccessory: Bool = true,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.detail = detail
        self.titleColor = titleColor
        self.detailColor = detailColor
        self.titleFont = titleFont
        self.titleNSFont = titleNSFont
        self.detailFont = detailFont
        self.detailNSFont = detailNSFont
        self.showsAccessory = showsAccessory
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MediaMetadataStyle.lineGap) {
            HStack(spacing: 8) {
                MediaMetadataMarqueeText(
                    text: title,
                    font: titleFont,
                    nsFont: titleNSFont,
                    foregroundColor: titleColor
                )
                    .help(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                if showsAccessory {
                    accessory
                        .frame(
                            width: ExpandedMediaMetadataDesign.accessoryWidth,
                            height: ExpandedMediaMetadataDesign.accessoryDiameter,
                            alignment: .trailing
                        )
                        .accessibilityHidden(true)
                }
            }

            MediaMetadataMarqueeText(
                text: detail,
                font: detailFont,
                nsFont: detailNSFont,
                foregroundColor: detailColor
            )
                .help(detail)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: ExpandedMediaLayout.metadataHeight,
            maxHeight: ExpandedMediaLayout.metadataHeight,
            alignment: .leading
        )
    }
}

struct ExpandedMediaMetadataView: View {
    var viewModel: NowPlayingViewModel
    let titleColor: Color
    let detailColor: Color
    let titleFont: Font
    let titleNSFont: NSFont
    let detailFont: Font
    let detailNSFont: NSFont
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        viewModel: NowPlayingViewModel,
        titleColor: Color = MediaMetadataStyle.titleColor,
        detailColor: Color = MediaMetadataStyle.detailColor,
        titleFont: Font = MediaMetadataStyle.expandedTitleFont,
        titleNSFont: NSFont = MediaMetadataStyle.expandedTitleNSFont,
        detailFont: Font = MediaMetadataStyle.detailFont,
        detailNSFont: NSFont = MediaMetadataStyle.detailNSFont
    ) {
        self.viewModel = viewModel
        self.titleColor = titleColor
        self.detailColor = detailColor
        self.titleFont = titleFont
        self.titleNSFont = titleNSFont
        self.detailFont = detailFont
        self.detailNSFont = detailNSFont
    }

    var body: some View {
        ExpandedMediaMetadataContent(
            title: titleText,
            detail: detailText,
            titleColor: titleColor,
            detailColor: detailColor,
            titleFont: titleFont,
            titleNSFont: titleNSFont,
            detailFont: detailFont,
            detailNSFont: detailNSFont,
            showsAccessory: viewModel.info != nil
        ) {
            if let info = viewModel.info {
                SpectrumBarsView(
                    source: viewModel.spectrumBuffer,
                    colors: viewModel.spectrumColors,
                    isActive: info.isPlaying,
                    reduceMotion: reduceMotion,
                    configuration: viewModel.musicSpectrumConfiguration,
                    barGradientsByBarCount: viewModel.spectrumBarGradientsByBarCount,
                    virtualSide: 46
                )
                .frame(
                    width: ExpandedMediaMetadataDesign.accessoryDiameter,
                    height: ExpandedMediaMetadataDesign.accessoryHeight
                )
            }
        }
    }

    private var titleText: String {
        viewModel.info?.title ?? L10n.tr("media.nothingPlaying")
    }

    private var detailText: String {
        guard let info = viewModel.info else {
            return L10n.tr("media.noArtistAlbum")
        }
        if !info.artist.isEmpty, let album = info.album, !album.isEmpty {
            return "\(info.artist) - \(album)"
        }
        if !info.artist.isEmpty {
            return info.artist
        }
        return info.isPlaying ? L10n.tr("media.playing") : L10n.tr("media.paused")
    }
}

private struct NativeScrubOverlay: NSViewRepresentable {
    let duration: TimeInterval
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat) -> Void
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ScrubNSView {
        let view = ScrubNSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: ScrubNSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: ScrubNSView) {
        view.duration = duration
        view.onChanged = onChanged
        view.onEnded = onEnded
        view.onHoverChanged = onHoverChanged
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.slider)
        view.setAccessibilityLabel(L10n.tr("media.playbackProgress"))
    }
}

private final class ScrubNSView: NSView {
    var duration: TimeInterval = 0
    var onChanged: ((CGFloat) -> Void)?
    var onEnded: ((CGFloat) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .activeAlways,
                .inVisibleRect,
                .enabledDuringMouseDrag,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        onChanged?(ratio(for: event))
    }

    override func mouseDragged(with event: NSEvent) {
        onChanged?(ratio(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        onEnded?(ratio(for: event))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func ratio(for event: NSEvent) -> CGFloat {
        guard bounds.width > 0 else { return 0 }
        let x = convert(event.locationInWindow, from: nil).x
        return min(max(x / bounds.width, 0), 1)
    }
}

enum ExpandedMediaProgressLabelPosition {
    case above
    case below
    case hidden
}

enum ExpandedMediaProgressStyle: Equatable {
    case standard
    case lockScreen
}

struct ExpandedMediaProgressView: View {
    let info: NowPlayingInfo
    let colors: [Color]
    let timeColor: Color
    let labelPosition: ExpandedMediaProgressLabelPosition
    let style: ExpandedMediaProgressStyle
    let onSeek: (TimeInterval) -> Void

    @State private var scrubRatio: CGFloat?
    @State private var isHoveringTrack = false

    init(
        info: NowPlayingInfo,
        colors: [Color],
        timeColor: Color = .white.opacity(0.5),
        labelPosition: ExpandedMediaProgressLabelPosition = .below,
        style: ExpandedMediaProgressStyle = .standard,
        onSeek: @escaping (TimeInterval) -> Void
    ) {
        self.info = info
        self.colors = colors
        self.timeColor = timeColor
        self.labelPosition = labelPosition
        self.style = style
        self.onSeek = onSeek
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let progress = progress(at: context.date) {
                let displayedRatio = scrubRatio ?? progress.ratio
                let displayedElapsed = scrubRatio.map { progress.duration * $0 }
                    ?? progress.elapsed

                VStack(spacing: style == .lockScreen ? 2 : 6) {
                    if labelPosition == .above {
                        timeLabels(
                            elapsed: displayedElapsed,
                            duration: progress.duration
                        )
                    }

                    progressTrack(
                        displayedRatio: displayedRatio,
                        displayedElapsed: displayedElapsed,
                        duration: progress.duration
                    )

                    if labelPosition == .below {
                        timeLabels(
                            elapsed: displayedElapsed,
                            duration: progress.duration
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func progressTrack(
        displayedRatio: CGFloat,
        displayedElapsed: TimeInterval,
        duration: TimeInterval
    ) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(trackColor)

                Capsule(style: .continuous)
                    .fill(foregroundStyle)
                    .frame(width: proxy.size.width * displayedRatio)

                Circle()
                    .fill(.white.opacity(0.96))
                    .frame(width: 8, height: 8)
                    .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                    .offset(
                        x: thumbOffset(
                            for: displayedRatio,
                            in: proxy.size.width
                        )
                    )
                    .opacity(style == .lockScreen || isHoveringTrack || scrubRatio != nil ? 1 : 0)
                    .animation(
                        .easeOut(duration: 0.12),
                        value: isHoveringTrack
                    )
            }
            .frame(height: trackHeight)
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(
                .spring(response: 0.2, dampingFraction: 0.9),
                value: isTrackEmphasized
            )
            .overlay {
                NativeScrubOverlay(
                    duration: duration,
                    onChanged: { ratio in
                        scrubRatio = ratio
                    },
                    onEnded: { ratio in
                        onSeek(duration * ratio)
                        scrubRatio = nil
                    },
                    onHoverChanged: { isHovering in
                        isHoveringTrack = isHovering
                    }
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .help("media.dragToSeek")
                    .accessibilityLabel("media.playbackProgress")
                    .accessibilityValue(
                        String(format: L10n.tr("media.progressValueFormat"), timeText(displayedElapsed), timeText(duration - displayedElapsed))
                    )
                    .accessibilityAdjustableAction { direction in
                        adjustProgress(
                            direction,
                            elapsed: displayedElapsed,
                            duration: duration
                        )
                    }
            }
        }
        .frame(height: style == .lockScreen ? 8 : 6)
    }

    private func timeLabels(
        elapsed: TimeInterval,
        duration: TimeInterval
    ) -> some View {
        HStack(spacing: 8) {
            Text(timeText(elapsed))
                .monospacedDigit()

            Spacer(minLength: 8)

            Text("-\(timeText(duration - elapsed))")
                .monospacedDigit()
                .frame(
                    width: ExpandedMediaLayout.remainingTimeWidth,
                    height: ExpandedMediaLayout.progressLabelHeight,
                    alignment: .trailing
                )
        }
        .frame(
            maxWidth: .infinity,
            minHeight: ExpandedMediaLayout.progressLabelHeight,
            maxHeight: ExpandedMediaLayout.progressLabelHeight
        )
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(timeColor)
    }

    private var isTrackEmphasized: Bool {
        isHoveringTrack || scrubRatio != nil
    }

    private var trackHeight: CGFloat {
        if style == .lockScreen {
            return isTrackEmphasized ? 8 : 6
        }
        return isTrackEmphasized ? 6 : 4
    }

    private var trackColor: Color {
        style == .lockScreen ? .white.opacity(0.30) : MediaPaletteStyle.trackColor(from: colors)
    }

    private var foregroundStyle: AnyShapeStyle {
        if style == .lockScreen {
            return AnyShapeStyle(.white.opacity(0.90))
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: MediaPaletteStyle.foregroundColors(from: colors),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private func thumbOffset(for ratio: CGFloat, in width: CGFloat) -> CGFloat {
        min(max(width * ratio - 4, 0), max(width - 8, 0))
    }

    private func adjustProgress(
        _ direction: AccessibilityAdjustmentDirection,
        elapsed: TimeInterval,
        duration: TimeInterval
    ) {
        let step = max(duration * 0.05, 5)
        switch direction {
        case .increment:
            onSeek(min(elapsed + step, duration))
        case .decrement:
            onSeek(max(elapsed - step, 0))
        @unknown default:
            break
        }
    }

    private func progress(at date: Date) -> (elapsed: TimeInterval, duration: TimeInterval, ratio: CGFloat)? {
        guard let elapsedTime = info.elapsedTime,
              let duration = info.duration,
              duration > 0 else {
            return nil
        }

        let advanced = info.isPlaying ? date.timeIntervalSince(info.updatedAt) : 0
        let elapsed = max(0, min(elapsedTime + advanced, duration))
        return (elapsed, duration, CGFloat(elapsed / duration))
    }

    private func timeText(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
