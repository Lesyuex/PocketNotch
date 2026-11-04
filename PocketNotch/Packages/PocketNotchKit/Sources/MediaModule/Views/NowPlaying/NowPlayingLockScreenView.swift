import AppKit
import PocketNotchCore
import PocketNotchShared
import SwiftUI

enum LockScreenMusicWidgetDesign {
    static let size = CGSize(width: 350, height: 170)
    static let aspectRatio = size.width / size.height
    static let horizontalContentInset: CGFloat = 15
    static let verticalContentInset: CGFloat = 15
    static let cornerRadius: CGFloat = 24
    static let artworkSize: CGFloat = 56
    static let artworkCornerRadius: CGFloat = 12
    static let progressTopSpacing: CGFloat = 10
    static let progressRowHeight: CGFloat = 28
    static let controlSize: CGFloat = 44
    static let controlVisualSize: CGFloat = 48
    /// 控制按钮到底部的专属间距：按钮自带 44pt 框架与内距，不再叠加全局垂直内边距。
    static let controlBottomInset: CGFloat = 6
    static let playbackStatusSize: CGFloat = 24
    static let accentColor = Color(red: 0, green: 0.78, blue: 0.33)
}

private struct LockScreenMusicContentLayout<
    TrackInformation: View,
    Progress: View,
    Controls: View
>: View {
    let trackInformation: TrackInformation
    let progress: Progress
    let controls: Controls

    init(
        @ViewBuilder trackInformation: () -> TrackInformation,
        @ViewBuilder progress: () -> Progress,
        @ViewBuilder controls: () -> Controls
    ) {
        self.trackInformation = trackInformation()
        self.progress = progress()
        self.controls = controls()
    }

    var body: some View {
        VStack(spacing: 0) {
            trackInformation

            progress
                .frame(height: LockScreenMusicWidgetDesign.progressRowHeight)
                .padding(.top, LockScreenMusicWidgetDesign.progressTopSpacing)

            Spacer(minLength: 0)

            controls
        }
        .padding(.horizontal, LockScreenMusicWidgetDesign.horizontalContentInset)
        .padding(.top, LockScreenMusicWidgetDesign.verticalContentInset)
        .padding(.bottom, LockScreenMusicWidgetDesign.controlBottomInset)
        .frame(
            maxWidth: .infinity,
            minHeight: LockScreenMusicWidgetDesign.size.height,
            maxHeight: LockScreenMusicWidgetDesign.size.height
        )
//        .overlay {
//            Rectangle()
//                .strokeBorder(.red, lineWidth: 1)
//        }
    }
}

private struct LockScreenMusicTrackInformationLayout<
    Artwork: View,
    Metadata: View,
    Status: View
>: View {
    let artwork: Artwork
    let metadata: Metadata
    let status: Status

    init(
        @ViewBuilder artwork: () -> Artwork,
        @ViewBuilder metadata: () -> Metadata,
        @ViewBuilder status: () -> Status
    ) {
        self.artwork = artwork()
        self.metadata = metadata()
        self.status = status()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            artwork
            metadata
                .frame(maxWidth: .infinity, alignment: .leading)
            status
                .padding(.top, LockScreenMusicMetadataDesign.statusTopInset)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: LockScreenMusicWidgetDesign.artworkSize,
            maxHeight: LockScreenMusicWidgetDesign.artworkSize,
            alignment: .leading
        )
    }
}

private enum LockScreenMusicMetadataDesign {
    static let titleNSFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
    static let detailNSFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let titleFont = Font(MediaMetadataStyle.expandedTitleNSFont)
    static let detailFont = Font(MediaMetadataStyle.detailNSFont)
    static let lineSpacing: CGFloat = 8

    private static let titleLineHeight = ceil(
        titleNSFont.ascender - titleNSFont.descender + titleNSFont.leading
    )
    private static let detailLineHeight = ceil(
        detailNSFont.ascender - detailNSFont.descender + detailNSFont.leading
    )
    private static let metadataHeight = titleLineHeight + lineSpacing + detailLineHeight

    static let statusTopInset = max(
        (LockScreenMusicWidgetDesign.artworkSize - metadataHeight) / 2
            + (titleLineHeight - LockScreenMusicWidgetDesign.playbackStatusSize) / 2,
        0
    )
}

private struct LockScreenMusicMetadataContent: View {
    let title: String
    let detail: String
    let titleColor: Color
    let detailColor: Color

    init(
        title: String,
        detail: String,
        titleColor: Color,
        detailColor: Color
    ) {
        self.title = title
        self.detail = detail
        self.titleColor = titleColor
        self.detailColor = detailColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LockScreenMusicMetadataDesign.lineSpacing) {
            MediaMetadataMarqueeText(
                text: title,
                font: LockScreenMusicMetadataDesign.titleFont,
                nsFont: LockScreenMusicMetadataDesign.titleNSFont,
                foregroundColor: titleColor
            )
            .help(title)

            MediaMetadataMarqueeText(
                text: detail,
                font: LockScreenMusicMetadataDesign.detailFont,
                nsFont: LockScreenMusicMetadataDesign.detailNSFont,
                foregroundColor: detailColor
            )
            .help(detail)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: LockScreenMusicWidgetDesign.artworkSize,
            maxHeight: LockScreenMusicWidgetDesign.artworkSize,
            alignment: .center
        )
    }
}

private struct LockScreenMusicMetadataView: View {
    var viewModel: NowPlayingViewModel
    let titleColor: Color
    let detailColor: Color

    init(
        viewModel: NowPlayingViewModel,
        titleColor: Color,
        detailColor: Color
    ) {
        self.viewModel = viewModel
        self.titleColor = titleColor
        self.detailColor = detailColor
    }

    var body: some View {
        LockScreenMusicMetadataContent(
            title: viewModel.info?.title ?? L10n.tr("media.nothingPlaying"),
            detail: detailText,
            titleColor: titleColor,
            detailColor: detailColor
        )
    }

    private var detailText: String {
        guard let info = viewModel.info else { return L10n.tr("media.waitingForMedia") }
        if !info.artist.isEmpty { return info.artist }
        return info.isPlaying ? L10n.tr("media.playing") : L10n.tr("media.paused")
    }
}

private struct LockScreenMusicMelodyStatus: View {
    var viewModel: NowPlayingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SpectrumBarsView(
            source: viewModel.spectrumBuffer,
            colors: viewModel.spectrumColors,
            isActive: viewModel.info?.isPlaying == true,
            reduceMotion: reduceMotion,
            configuration: viewModel.musicSpectrumConfiguration,
            barGradientsByBarCount: viewModel.spectrumBarGradientsByBarCount,
            isLockScreenPresentation: true
        )
        .frame(
            width: LockScreenMusicWidgetDesign.playbackStatusSize,
            height: LockScreenMusicWidgetDesign.playbackStatusSize
        )
    }
}

private struct LockScreenMusicControlLayout<
    Shuffle: View,
    Previous: View,
    Playback: View,
    Next: View,
    Output: View
>: View {
    let shuffle: Shuffle
    let previous: Previous
    let playback: Playback
    let next: Next
    let output: Output

    init(
        @ViewBuilder shuffle: () -> Shuffle,
        @ViewBuilder previous: () -> Previous,
        @ViewBuilder playback: () -> Playback,
        @ViewBuilder next: () -> Next,
        @ViewBuilder output: () -> Output
    ) {
        self.shuffle = shuffle()
        self.previous = previous()
        self.playback = playback()
        self.next = next()
        self.output = output()
    }

    var body: some View {
        HStack(spacing: 0) {
            shuffle
            Spacer(minLength: 0)
            previous
            Spacer(minLength: 0)
            playback
            Spacer(minLength: 0)
            next
            Spacer(minLength: 0)
            output
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct LockScreenMusicPlayerContent: View {
    var viewModel: NowPlayingViewModel
    let songTextColor: Color
    let progressTextColor: Color
    let controlIconColor: Color
    let selectedControlColor: Color?

    init(
        viewModel: NowPlayingViewModel,
        songTextColor: Color = MediaMetadataStyle.titleColor,
        progressTextColor: Color = .white.opacity(0.5),
        controlIconColor: Color = .white,
        selectedControlColor: Color? = nil
    ) {
        self.viewModel = viewModel
        self.songTextColor = songTextColor
        self.progressTextColor = progressTextColor
        self.controlIconColor = controlIconColor
        self.selectedControlColor = selectedControlColor
    }

    var body: some View {
        LockScreenMusicContentLayout {
            trackInformation
        } progress: {
            progressSection
        } controls: {
            LockScreenPlaybackControls(
                viewModel: viewModel,
                foregroundColor: controlIconColor,
                selectedColorOverride: selectedControlColor
            )
        }
    }

    private var trackInformation: some View {
        LockScreenMusicTrackInformationLayout {
            MediaLaunchableArtwork(
                viewModel: viewModel,
                fallbackSystemName: viewModel.info?.isPlaying == true
                    ? "waveform.circle.fill"
                    : "music.note",
                size: LockScreenMusicWidgetDesign.artworkSize,
                cornerRadius: LockScreenMusicWidgetDesign.artworkCornerRadius,
                applicationBadgeOffset: 3,
                applicationBadgeSize: 18
            )
        } metadata: {
            LockScreenMusicMetadataView(
                viewModel: viewModel,
                titleColor: songTextColor,
                detailColor: songTextColor.opacity(0.66)
            )
        } status: {
            LockScreenMusicMelodyStatus(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        if let info = viewModel.info {
            ExpandedMediaProgressView(
                info: info,
                colors: viewModel.spectrumColors,
                timeColor: progressTextColor,
                labelPosition: .above,
                style: .lockScreen,
                onSeek: viewModel.seek
            )
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.12))
                    .frame(height: 4)

                Text("media.waitingForMedia")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(progressTextColor)
                    .lineLimit(1)
            }
        }
    }
}

struct NowPlayingLockScreenView: View {
    var viewModel: NowPlayingViewModel
    @ObservedObject var presenter: LockScreenMusicWidgetPresenter
    @ObservedObject var settings: MediaMonitoringSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        glassCard
            .frame(
                width: LockScreenMusicWidgetDesign.size.width,
                height: LockScreenMusicWidgetDesign.size.height
            )
            .clipShape(cardShape)
            .scaleEffect(presenter.isPresented || reduceMotion ? 1 : 0.985)
            .offset(y: presenter.isPresented || reduceMotion ? 0 : -6)
            .opacity(presenter.isPresented ? 1 : 0)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.16)
                    : .spring(response: 0.34, dampingFraction: 1),
                value: presenter.isPresented
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("media.dynamicIsland")
    }

    @ViewBuilder
    private var glassCard: some View {
        LockScreenMusicBackdrop(
            backdropStyle: settings.lockScreenMusicBackdropStyle,
            glassBlur: settings.lockScreenMusicGlassBlur,
            glassMaterial: settings.lockScreenMusicGlassMaterial,
            solidColor: settings.lockScreenMusicSolidColor,
            usesArtworkGradient: settings.isLockScreenArtworkGradientEnabled,
            paletteColors: viewModel.spectrumColors
        ) {
            LockScreenMusicPlayerContent(
                viewModel: viewModel,
                songTextColor: songTextColor,
                progressTextColor: progressTextColor,
                controlIconColor: controlIconColor,
                selectedControlColor: controlIconColorOverride
            )
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: LockScreenMusicWidgetDesign.cornerRadius,
            style: .continuous
        )
    }

    private var songTextColor: Color {
        guard settings.lockScreenMusicBackdropStyle == .solidColor else {
            return MediaMetadataStyle.titleColor
        }
        return settings.lockScreenMusicSolidTextColor.color
    }

    private var progressTextColor: Color {
        guard settings.lockScreenMusicBackdropStyle == .solidColor else {
            return .white.opacity(0.9)
        }
        return settings.lockScreenMusicSolidTextColor.color
    }

    private var controlIconColor: Color {
        controlIconColorOverride ?? .white
    }

    private var controlIconColorOverride: Color? {
        settings.lockScreenMusicBackdropStyle == .solidColor
            ? settings.lockScreenMusicSolidTextColor.color
            : nil
    }
}

private struct LockScreenMusicBackdrop<Content: View>: View {
    let backdropStyle: LockScreenMusicBackdropStyle
    let glassBlur: Double
    let glassMaterial: LiquidGlassMaterial
    let solidColor: LockScreenMusicSolidColor
    let usesArtworkGradient: Bool
    let paletteColors: [Color]
    let content: Content

    init(
        backdropStyle: LockScreenMusicBackdropStyle,
        glassBlur: Double = 0.5,
        glassMaterial: LiquidGlassMaterial = .bubbles,
        solidColor: LockScreenMusicSolidColor,
        usesArtworkGradient: Bool,
        paletteColors: [Color],
        @ViewBuilder content: () -> Content
    ) {
        self.backdropStyle = backdropStyle
        self.glassBlur = min(max(glassBlur, 0), 1)
        self.glassMaterial = glassMaterial
        self.solidColor = solidColor
        self.usesArtworkGradient = usesArtworkGradient
        self.paletteColors = paletteColors
        self.content = content()
    }

    var body: some View {
        switch backdropStyle {
        case .glass, .clear:
            liquidGlassLayer
        case .solidColor, .artworkTheme:
            ZStack {
                baseLayer
                content
            }
        }
    }

    @ViewBuilder
    private var baseLayer: some View {
        switch backdropStyle {
        case .glass, .clear:
            EmptyView()
        case .solidColor:
            cardShape
                .fill(solidColor.color)
                .overlay {
                    cardShape.strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
        case .artworkTheme:
            ZStack {
                if usesArtworkGradient {
                    cardShape.fill(
                        LinearGradient(
                            colors: MediaPaletteStyle.backgroundColors(from: paletteColors),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                } else {
                    cardShape.fill(accentColor)
                }

                cardShape.fill(.black.opacity(0.24))
            }
            .overlay {
                cardShape.strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
        }
    }

    /// True liquid glass backed by the private `NSGlassEffectView`.
    ///
    /// Glass always uses Regular (`material: .regular`, variant 0) and follows
    /// the user-controlled transparency value. Clear (液态玻璃) uses the
    /// user-selected `glassMaterial` at opacity 1 so its refraction and
    /// highlights stay at native strength. Content sits ON TOP of the glass and
    /// stays fully opaque in both modes.
    @ViewBuilder
    private var liquidGlassLayer: some View {
        ZStack {
            LiquidGlassBackdrop(
                material: backdropStyle == .glass ? .regular : glassMaterial,
                cornerRadius: LockScreenMusicWidgetDesign.cornerRadius,
                tintColor: NSColor.white.withAlphaComponent(0.08),
                // 磨砂程度值越高越不透明（越磨砂），直接映射到 opacity。
                opacity: backdropStyle == .clear ? 1 : glassBlur
            )
            .clipShape(cardShape)

            content
        }
        .overlay {
            cardShape.strokeBorder(
                backdropStyle == .glass
                    ? .white.opacity(0.24)
                    : Color(
                        nsColor: NSColor.white.withAlphaComponent(0.42)
                    ),
                lineWidth: 1
            )
        }
        .overlay {
            if backdropStyle == .clear {
                cardShape
                    .inset(by: 1.5)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.75)
            }
        }
    }

    private var accentColor: Color {
        paletteColors.first ?? .white
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: LockScreenMusicWidgetDesign.cornerRadius,
            style: .continuous
        )
    }
}

private struct G2RoundedRectangle: InsettableShape {
    var cornerRadius: CGFloat
    private var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard bounds.width > 0, bounds.height > 0 else { return Path() }

        let radius = min(
            max(cornerRadius - insetAmount, 0),
            min(bounds.width, bounds.height) / 2
        )
        guard radius > 0 else { return Path(bounds) }

        var path = Path()
        path.move(to: CGPoint(x: bounds.minX + radius, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.maxX - radius, y: bounds.minY))
        addCorner(
            to: &path,
            center: CGPoint(x: bounds.maxX - radius, y: bounds.minY + radius),
            radius: radius,
            from: -.pi / 2,
            to: 0
        )
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - radius))
        addCorner(
            to: &path,
            center: CGPoint(x: bounds.maxX - radius, y: bounds.maxY - radius),
            radius: radius,
            from: 0,
            to: .pi / 2
        )
        path.addLine(to: CGPoint(x: bounds.minX + radius, y: bounds.maxY))
        addCorner(
            to: &path,
            center: CGPoint(x: bounds.minX + radius, y: bounds.maxY - radius),
            radius: radius,
            from: .pi / 2,
            to: .pi
        )
        path.addLine(to: CGPoint(x: bounds.minX, y: bounds.minY + radius))
        addCorner(
            to: &path,
            center: CGPoint(x: bounds.minX + radius, y: bounds.minY + radius),
            radius: radius,
            from: .pi,
            to: .pi * 1.5
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> G2RoundedRectangle {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    private func addCorner(
        to path: inout Path,
        center: CGPoint,
        radius: CGFloat,
        from startAngle: CGFloat,
        to endAngle: CGFloat
    ) {
        // A fourth-order superellipse meets each straight edge with zero curvature.
        let exponent: CGFloat = 4
        let steps = 24

        for step in 1...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let angle = startAngle + (endAngle - startAngle) * progress
            let cosine = signedPower(cos(angle), exponent: exponent)
            let sine = signedPower(sin(angle), exponent: exponent)
            path.addLine(
                to: CGPoint(
                    x: center.x + radius * cosine,
                    y: center.y + radius * sine
                )
            )
        }
    }

    private func signedPower(_ value: CGFloat, exponent: CGFloat) -> CGFloat {
        guard value != 0 else { return 0 }
        let magnitude = CGFloat(pow(Double(abs(value)), Double(2 / exponent)))
        return value < 0 ? -magnitude : magnitude
    }
}

public struct LockScreenMusicMaterialComponentThumbnail: View {
    private static let paletteColors: [Color] = [
        Color(red: 0.20, green: 0.74, blue: 0.96),
        Color(red: 0.52, green: 0.38, blue: 0.94),
        Color(red: 0.95, green: 0.38, blue: 0.58),
    ]

    private let backdropStyle: LockScreenMusicBackdropStyle
    private let glassBlur: Double
    private let glassMaterial: LiquidGlassMaterial
    private let solidColor: LockScreenMusicSolidColor
    private let usesArtworkGradient: Bool

    public init(
        backdropStyle: LockScreenMusicBackdropStyle,
        glassBlur: Double,
        glassMaterial: LiquidGlassMaterial = .bubbles,
        solidColor: LockScreenMusicSolidColor,
        usesArtworkGradient: Bool
    ) {
        self.backdropStyle = backdropStyle
        self.glassBlur = glassBlur
        self.glassMaterial = glassMaterial
        self.solidColor = solidColor
        self.usesArtworkGradient = usesArtworkGradient
    }

    public var body: some View {
        GeometryReader { proxy in
            let scale = min(
                proxy.size.width / LockScreenMusicWidgetDesign.size.width,
                proxy.size.height / LockScreenMusicWidgetDesign.size.height
            )
            let componentSize = CGSize(
                width: LockScreenMusicWidgetDesign.size.width * scale,
                height: LockScreenMusicWidgetDesign.size.height * scale
            )
            let componentShape = RoundedRectangle(
                cornerRadius: LockScreenMusicWidgetDesign.cornerRadius * scale,
                style: .continuous
            )

            LockScreenMusicBackdrop(
                backdropStyle: backdropStyle,
                glassBlur: glassBlur,
                glassMaterial: glassMaterial,
                solidColor: solidColor,
                usesArtworkGradient: usesArtworkGradient,
                paletteColors: Self.paletteColors
            ) {
                Color.clear
            }
            .frame(
                width: LockScreenMusicWidgetDesign.size.width,
                height: LockScreenMusicWidgetDesign.size.height
            )
            .scaleEffect(scale)
            .frame(width: componentSize.width, height: componentSize.height)
            .clipShape(componentShape)
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LockScreenMusicPreviewContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isActive: Bool
    let backdropStyle: LockScreenMusicBackdropStyle
    let solidTextColor: LockScreenMusicSolidColor
    let paletteColors: [Color]
    let spectrumConfiguration: MusicSpectrumConfiguration

    private let previewInfo = NowPlayingInfo(
        title: "Midnight City",
        artist: "M83",
        album: "Hurry Up, We're Dreaming",
        elapsedTime: 102,
        duration: 243,
        isPlaying: true
    )

    var body: some View {
        LockScreenMusicContentLayout {
            trackInformation
        } progress: {
            progress
        } controls: {
            controls
        }
        .allowsHitTesting(false)
    }

    private var trackInformation: some View {
        LockScreenMusicTrackInformationLayout {
            artwork
        } metadata: {
            LockScreenMusicMetadataContent(
                title: previewInfo.title,
                detail: previewInfo.artist,
                titleColor: songTextColor,
                detailColor: songTextColor.opacity(0.66)
            )
        } status: {
            melody
        }
    }

    private var melody: some View {
        SpectrumBarsView(
            source: PreviewSpectrumSource(),
            colors: paletteColors,
            isActive: isActive,
            reduceMotion: reduceMotion,
            configuration: spectrumConfiguration
        )
        .frame(
            width: LockScreenMusicWidgetDesign.playbackStatusSize,
            height: LockScreenMusicWidgetDesign.playbackStatusSize
        )
    }

    private var artwork: some View {
        RoundedRectangle(
            cornerRadius: LockScreenMusicWidgetDesign.artworkCornerRadius,
            style: .continuous
        )
        .fill(
            LinearGradient(
                colors: paletteColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            Image(systemName: "waveform")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(.black.opacity(0.78))
                .frame(width: 18, height: 18)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .offset(x: 3, y: 3)
        }
        .frame(
            width: LockScreenMusicWidgetDesign.artworkSize,
            height: LockScreenMusicWidgetDesign.artworkSize
        )
    }

    private var progress: some View {
        ExpandedMediaProgressView(
            info: previewInfo,
            colors: paletteColors,
            timeColor: progressTextColor,
            labelPosition: .above,
            style: .lockScreen,
            onSeek: { _ in }
        )
    }

    private var controls: some View {
        LockScreenMusicControlLayout {
            control(systemName: "shuffle")
        } previous: {
            control(systemName: "backward.fill")
        } playback: {
            control(systemName: "pause.fill", isPrimary: true)
        } next: {
            control(systemName: "forward.fill")
        } output: {
            control(systemName: "airplayaudio")
        }
    }

    private func control(
        systemName: String,
        isPrimary: Bool = false
    ) -> some View {
        Button(action: {}) {
            Image(systemName: systemName)
        }
        .buttonStyle(
            MediaBorderlessControlButtonStyle(
                size: LockScreenMusicWidgetDesign.controlSize,
                visualSize: LockScreenMusicWidgetDesign.controlVisualSize,
                isPrimary: isPrimary,
                foregroundColor: controlIconColor
            )
        )
    }

    private var songTextColor: Color {
        backdropStyle == .solidColor
            ? solidTextColor.color
            : MediaMetadataStyle.titleColor
    }

    private var progressTextColor: Color {
        backdropStyle == .solidColor
            ? solidTextColor.color
            : .white.opacity(0.9)
    }

    private var controlIconColor: Color {
        backdropStyle == .solidColor
            ? solidTextColor.color
            : .white
    }
}

public struct LockScreenMusicMaterialThumbnail: View {
    private static let paletteColors: [Color] = [
        Color(red: 0.20, green: 0.74, blue: 0.96),
        Color(red: 0.52, green: 0.38, blue: 0.94),
        Color(red: 0.95, green: 0.38, blue: 0.58),
    ]

    private let wallpaperImage: NSImage?
    private let backdropStyle: LockScreenMusicBackdropStyle
    private let glassBlur: Double
    private let glassMaterial: LiquidGlassMaterial
    private let solidColor: LockScreenMusicSolidColor
    private let solidTextColor: LockScreenMusicSolidColor
    private let usesArtworkGradient: Bool
    private let isActive: Bool
    private let musicSpectrumBarStyle: MusicSpectrumBarStyle
    private let musicSpectrumSensitivity: Double
    private let musicSpectrumAttackTime: Double
    private let musicSpectrumReleaseTime: Double
    private let musicSpectrumBarWidthScale: Double
    private let musicSpectrumBarSpacingScale: Double
    private let musicSpectrumBarCornerRadiusScale: Double

    public init(
        wallpaperImage: NSImage?,
        backdropStyle: LockScreenMusicBackdropStyle,
        glassBlur: Double,
        glassMaterial: LiquidGlassMaterial = .bubbles,
        solidColor: LockScreenMusicSolidColor,
        solidTextColor: LockScreenMusicSolidColor,
        usesArtworkGradient: Bool,
        isActive: Bool,
        musicSpectrumBarStyle: MusicSpectrumBarStyle = .five,
        musicSpectrumSensitivity: Double = 0.5,
        musicSpectrumAttackTime: Double = 0.5,
        musicSpectrumReleaseTime: Double = 0.5,
        musicSpectrumBarWidthScale: Double = 2.5,
        musicSpectrumBarSpacingScale: Double = 1.6,
        musicSpectrumBarCornerRadiusScale: Double = 1
    ) {
        self.wallpaperImage = wallpaperImage
        self.backdropStyle = backdropStyle
        self.glassBlur = glassBlur
        self.glassMaterial = glassMaterial
        self.solidColor = solidColor
        self.solidTextColor = solidTextColor
        self.usesArtworkGradient = usesArtworkGradient
        self.isActive = isActive
        self.musicSpectrumBarStyle = musicSpectrumBarStyle
        self.musicSpectrumSensitivity = musicSpectrumSensitivity
        self.musicSpectrumAttackTime = musicSpectrumAttackTime
        self.musicSpectrumReleaseTime = musicSpectrumReleaseTime
        self.musicSpectrumBarWidthScale = musicSpectrumBarWidthScale
        self.musicSpectrumBarSpacingScale = musicSpectrumBarSpacingScale
        self.musicSpectrumBarCornerRadiusScale = musicSpectrumBarCornerRadiusScale
    }

    public var body: some View {
        GeometryReader { proxy in
            // 组件四周留白：左右各 16pt，上下各 8pt。
            let componentInsets = CGSize(width: 32, height: 16)
            let componentArea = CGSize(
                width: max(proxy.size.width - componentInsets.width, 0),
                height: max(proxy.size.height - componentInsets.height, 0)
            )
            let scale = min(
                componentArea.width / LockScreenMusicWidgetDesign.size.width,
                componentArea.height / LockScreenMusicWidgetDesign.size.height
            )
            let componentSize = CGSize(
                width: LockScreenMusicWidgetDesign.size.width * scale,
                height: LockScreenMusicWidgetDesign.size.height * scale
            )
            let componentShape = RoundedRectangle(
                cornerRadius: max(4, LockScreenMusicWidgetDesign.cornerRadius * scale),
                style: .continuous
            )
            let canvasShape = G2RoundedRectangle(cornerRadius: 30)

            ZStack {
                thumbnailWallpaper
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                LockScreenMusicBackdrop(
                    backdropStyle: backdropStyle,
                    glassBlur: glassBlur,
                    glassMaterial: glassMaterial,
                    solidColor: solidColor,
                    usesArtworkGradient: usesArtworkGradient,
                    paletteColors: Self.paletteColors
                ) {
                    LockScreenMusicPreviewContent(
                        isActive: isActive,
                        backdropStyle: backdropStyle,
                        solidTextColor: solidTextColor,
                        paletteColors: Self.paletteColors,
                        spectrumConfiguration: spectrumConfiguration
                    )
                }
                .frame(
                    width: LockScreenMusicWidgetDesign.size.width,
                    height: LockScreenMusicWidgetDesign.size.height
                )
                .scaleEffect(scale)
                .frame(width: componentSize.width, height: componentSize.height)
                .clipShape(componentShape)
                .shadow(color: .black.opacity(0.24), radius: 8, y: 4)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(canvasShape)
            .overlay {
                canvasShape.strokeBorder(.white.opacity(0.10), lineWidth: 0.75)
            }
            .contentShape(canvasShape)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var spectrumConfiguration: MusicSpectrumConfiguration {
        MusicSpectrumConfiguration(
            style: musicSpectrumBarStyle,
            sensitivity: musicSpectrumSensitivity,
            attackTime: musicSpectrumAttackTime,
            releaseTime: musicSpectrumReleaseTime,
            barWidthScale: musicSpectrumBarWidthScale,
            barSpacingScale: musicSpectrumBarSpacingScale,
            barCornerRadiusScale: musicSpectrumBarCornerRadiusScale
        )
    }

    @ViewBuilder
    private var thumbnailWallpaper: some View {
        if let wallpaperImage {
            Image(nsImage: wallpaperImage)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }
}

public struct LockScreenMusicWidgetSettingsPreview: View {
    private let wallpaperImage: NSImage?
    private let isEnabled: Bool
    private let backdropStyle: LockScreenMusicBackdropStyle
    private let glassBlur: Double
    private let glassMaterial: LiquidGlassMaterial
    private let solidColor: LockScreenMusicSolidColor
    private let solidTextColor: LockScreenMusicSolidColor
    private let usesArtworkGradient: Bool
    private let musicSpectrumBarStyle: MusicSpectrumBarStyle
    private let musicSpectrumSensitivity: Double
    private let musicSpectrumAttackTime: Double
    private let musicSpectrumReleaseTime: Double
    private let musicSpectrumBarWidthScale: Double
    private let musicSpectrumBarSpacingScale: Double
    private let musicSpectrumBarCornerRadiusScale: Double

    private let paletteColors: [Color] = [
        Color(red: 0.20, green: 0.74, blue: 0.96),
        Color(red: 0.52, green: 0.38, blue: 0.94),
        Color(red: 0.95, green: 0.38, blue: 0.58),
    ]

    public init(
        wallpaperImage: NSImage?,
        isEnabled: Bool,
        backdropStyle: LockScreenMusicBackdropStyle,
        glassBlur: Double = 0.5,
        glassMaterial: LiquidGlassMaterial = .bubbles,
        solidColor: LockScreenMusicSolidColor,
        solidTextColor: LockScreenMusicSolidColor,
        usesArtworkGradient: Bool,
        musicSpectrumBarStyle: MusicSpectrumBarStyle = .five,
        musicSpectrumSensitivity: Double = 0.5,
        musicSpectrumAttackTime: Double = 0.5,
        musicSpectrumReleaseTime: Double = 0.5,
        musicSpectrumBarWidthScale: Double = 2.5,
        musicSpectrumBarSpacingScale: Double = 1.6,
        musicSpectrumBarCornerRadiusScale: Double = 1
    ) {
        self.wallpaperImage = wallpaperImage
        self.isEnabled = isEnabled
        self.backdropStyle = backdropStyle
        self.glassBlur = min(max(glassBlur, 0), 1)
        self.glassMaterial = glassMaterial
        self.solidColor = solidColor
        self.solidTextColor = solidTextColor
        self.usesArtworkGradient = usesArtworkGradient
        self.musicSpectrumBarStyle = musicSpectrumBarStyle
        self.musicSpectrumSensitivity = musicSpectrumSensitivity
        self.musicSpectrumAttackTime = musicSpectrumAttackTime
        self.musicSpectrumReleaseTime = musicSpectrumReleaseTime
        self.musicSpectrumBarWidthScale = musicSpectrumBarWidthScale
        self.musicSpectrumBarSpacingScale = musicSpectrumBarSpacingScale
        self.musicSpectrumBarCornerRadiusScale = musicSpectrumBarCornerRadiusScale
    }

    public var body: some View {
        ZStack {
            wallpaper

            LockScreenMusicBackdrop(
                backdropStyle: backdropStyle,
                glassBlur: glassBlur,
                glassMaterial: glassMaterial,
                solidColor: solidColor,
                usesArtworkGradient: usesArtworkGradient,
                paletteColors: paletteColors
            ) {
                previewContent
            }
            .frame(
                width: LockScreenMusicWidgetDesign.size.width,
                height: LockScreenMusicWidgetDesign.size.height
            )
            .clipShape(cardShape)
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(isEnabled ? 1 : 0.985)

            if !isEnabled {
                Label("media.lockScreenMusicOff", systemImage: "lock.slash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.58)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 264)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
        .animation(.easeOut(duration: 0.18), value: isEnabled)
        .animation(.easeOut(duration: 0.18), value: backdropStyle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("media.lockScreenMusicPreview")
        .accessibilityValue(isEnabled ? backdropStyle.title : L10n.tr("media.off"))
    }

    @ViewBuilder
    private var wallpaper: some View {
        ZStack {
            Color(red: 0.12, green: 0.14, blue: 0.17)

            if let wallpaperImage {
                Image(nsImage: wallpaperImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            }
        }
        .allowsHitTesting(false)
    }

    private var previewContent: some View {
        LockScreenMusicPreviewContent(
            isActive: isEnabled,
            backdropStyle: backdropStyle,
            solidTextColor: solidTextColor,
            paletteColors: paletteColors,
            spectrumConfiguration: MusicSpectrumConfiguration(
                style: musicSpectrumBarStyle,
                sensitivity: musicSpectrumSensitivity,
                attackTime: musicSpectrumAttackTime,
                releaseTime: musicSpectrumReleaseTime,
                barWidthScale: musicSpectrumBarWidthScale,
                barSpacingScale: musicSpectrumBarSpacingScale,
                barCornerRadiusScale: musicSpectrumBarCornerRadiusScale
            )
        )
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: LockScreenMusicWidgetDesign.cornerRadius,
            style: .continuous
        )
    }

}

private struct LockScreenPlaybackControls: View {
    var viewModel: NowPlayingViewModel
    let foregroundColor: Color
    let selectedColorOverride: Color?

    var body: some View {
        LockScreenMusicControlLayout {
            controlButton(
                systemName: "shuffle",
                help: viewModel.isShuffleEnabled ? L10n.tr("media.turnOffShuffle") : L10n.tr("media.turnOnShuffle"),
                isEnabled: viewModel.playbackCapabilities.canShuffle,
                isSelected: viewModel.isShuffleEnabled,
                selectedColor: LockScreenMusicWidgetDesign.accentColor
            ) {
                Task { await viewModel.toggleShuffle() }
            }
        } previous: {
            controlButton(
                systemName: "backward.fill",
                help: L10n.tr("media.previous"),
                action: viewModel.previous
            )
        } playback: {
            controlButton(
                systemName: viewModel.info?.isPlaying == true ? "pause.fill" : "play.fill",
                help: viewModel.info?.isPlaying == true ? L10n.tr("media.pause") : L10n.tr("media.play"),
                isPrimary: true,
                action: viewModel.togglePlay
            )
        } next: {
            controlButton(
                systemName: "forward.fill",
                help: L10n.tr("media.next"),
                action: viewModel.next
            )
        } output: {
            MediaOutputPickerButton(
                viewModel: viewModel,
                size: LockScreenMusicWidgetDesign.controlSize,
                visualSize: LockScreenMusicWidgetDesign.controlVisualSize,
                usesBorderlessStyle: true,
                borderlessForegroundColor: foregroundColor,
                borderlessSelectedColor: selectedColorOverride ?? .accentColor
            )
        }
        .disabled(viewModel.info == nil)
        .opacity(viewModel.info == nil ? 0.42 : 1)
    }

    private func controlButton(
        systemName: String,
        help: String,
        isEnabled: Bool = true,
        isPrimary: Bool = false,
        isSelected: Bool = false,
        selectedColor: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(
            MediaBorderlessControlButtonStyle(
                size: LockScreenMusicWidgetDesign.controlSize,
                visualSize: LockScreenMusicWidgetDesign.controlVisualSize,
                isPrimary: isPrimary,
                isSelected: isSelected,
                foregroundColor: foregroundColor,
                selectedColor: selectedColorOverride ?? selectedColor
            )
        )
        .help(help)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }
}
