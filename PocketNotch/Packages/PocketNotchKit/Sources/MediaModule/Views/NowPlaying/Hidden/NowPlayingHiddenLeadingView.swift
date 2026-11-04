import PocketNotchCore
import PocketNotchShared
import SwiftUI

enum CompactMediaContentRole: Equatable {
    case resident
    case notification
}

/// compact 前导区域：新蓝牙外设连接时展示对应设备图标，否则展示旋转歌曲封面。
/// 尺寸由背板动态高度推导（CompactIslandContentSpec）。
struct NowPlayingHiddenLeadingView: View {
    private enum CoverDesign {
        // 旋转模式封面铺满耳朵槽位；非旋转模式按耳朵的 96% 渲染，并在槽位内左右上下居中。
        static let staticArtworkScale: CGFloat = 0.96
        static let playingGlowOpacity: CGFloat = 0.22
        static let pausedGlowOpacity: CGFloat = 0.10
        static let glowRadius: CGFloat = 3
        static let rotationDuration: Double = 10
        static let stateTransitionDuration: Double = 0.24
    }

    var viewModel: NowPlayingViewModel
    @ObservedObject var settings: MediaMonitoringSettings
    let role: CompactMediaContentRole
    @Environment(\.notchHiddenIslandSize) private var hiddenIslandSize
    @Environment(\.islandCompactContentSize) private var islandCompactContentSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    private var coverSize: CGFloat {
        islandCompactContentSize?.height
            ?? CompactIslandContentSpec.resolvedContentHeight(for: hiddenIslandSize.height)
    }
    private var contentWidth: CGFloat {
        islandCompactContentSize?.width
            ?? CompactIslandContentSpec.leadingContentWidth(forHeight: hiddenIslandSize.height)
    }
    /// 旋转模式封面铺满耳朵槽；非旋转模式取耳朵的 96%，并在槽内左右上下居中。
    private var artworkSide: CGFloat {
        settings.isCompactArtworkRotationEnabled
            ? coverSize
            : coverSize * CoverDesign.staticArtworkScale
    }
    private var showsVolumeLabel: Bool {
        role == .notification
            && viewModel.volumePresentation != nil
            && CompactIslandTier.resolved(
                forWidth: hiddenIslandSize.width,
                stockDisplayActive: false
            ) == .second
    }

    private var hasMedia: Bool {
        viewModel.isCompactMediaDisplayActive
    }
    private var isPlaying: Bool { viewModel.info?.isPlaying == true }
    /// 只有真实媒体封面才旋转；App 图标兜底始终保持系统默认静态外观。
    private var isRotationActive: Bool {
        isPlaying
            && viewModel.isMediaArtworkReady
            && settings.isCompactArtworkRotationEnabled
            && !reduceMotion
    }
    private var artworkCornerRadius: CGFloat {
        let percentage = settings.isCompactArtworkRotationEnabled
            ? settings.compactRotatingArtworkCornerRadiusPercentage
            : settings.compactStaticArtworkCornerRadiusPercentage
        let normalizedPercentage = min(
            max(percentage / 100, 0),
            1
        )
        return artworkSide * 0.5 * CGFloat(normalizedPercentage)
    }
    private var artworkShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous)
    }
    private var glowColor: Color? {
        guard viewModel.isMediaArtworkReady else { return nil }
        return viewModel.spectrumColors.first
    }
    private var activeGlowColor: Color? {
        switch role {
        case .resident: glowColor
        case .notification: isCompactContentVisible ? .white : nil
        }
    }
    // 歌曲标识：切歌时角度归零，从初始位置重转。
    private var songKey: String {
        guard let info = viewModel.info else { return "" }
        return info.title + "\u{1}" + info.artist
    }

    /// 旋转相位归零令牌：切歌或关闭旋转时变化，驱动旋转层从 0° 重新开始。
    private var rotationResetToken: String {
        "\(settings.isCompactArtworkRotationEnabled)-\(songKey)"
    }

    private var isCompactContentVisible: Bool {
        switch role {
        case .resident:
            hasMedia
        case .notification:
            if viewModel.headphoneConnectionPresentation != nil {
                !viewModel.isHeadphoneConnectionDismissing
            } else {
                viewModel.volumePresentation != nil
            }
        }
    }

    /// 瞬时通知占据常驻区域时，通知层自行上报隐藏常驻内容；
    /// 覆盖阶段持续到展示数据完全清空（含退场），避免常驻内容在通知淡出前抢先回弹。
    private var suppressesResidentContent: Bool {
        role == .notification
            && (viewModel.volumePresentation != nil || viewModel.headphoneConnectionPresentation != nil)
    }

    var body: some View {
        return Group {
            if role == .notification, let volume = viewModel.volumePresentation {
                AudioVolumeIcon(
                    systemName: viewModel.volumeIconSymbolName ?? volume.volumeSymbolName,
                    percentage: volume.displayedPercentage,
                    diameter: coverSize,
                    showsLabel: showsVolumeLabel
                )
            } else if role == .notification,
                      let headphones = viewModel.headphoneConnectionPresentation {
                HeadphoneIcon(
                    systemName: headphones.deviceSymbolName,
                    deviceName: headphones.deviceName,
                    diameter: coverSize,
                    isDismissing: viewModel.isHeadphoneConnectionDismissing
                )
            } else if role == .resident, hasMedia {
                cover
                    .transition(.islandCompactModule(reduceMotion: reduceMotion))
            } else {
                Color.clear.frame(width: coverSize, height: coverSize)
            }
        }
        .frame(
            width: showsVolumeLabel ? nil : contentWidth,
            height: coverSize,
            alignment: .center
        )
        .frame(
            maxWidth: role == .notification ? .infinity : nil,
            maxHeight: .infinity,
            alignment: .leading
        )
        .islandGlowColor(isCompactContentVisible ? activeGlowColor : nil)
        .compactIslandContentVisible(isCompactContentVisible)
        .compactIslandPreferredWidth(preferredIslandWidth)
        .compactIslandSuppressesResidentContent(suppressesResidentContent)
        .animation(
            PocketNotchTheme.islandCompactModuleAnimation(
                isVisible: isCompactContentVisible,
                reduceMotion: reduceMotion
            ),
            value: viewModel.compactPresentationIdentity
        )
    }

    private var preferredIslandWidth: CGFloat? {
        guard role == .notification else { return nil }
        return viewModel.compactPresentationIdentity.preferredIslandWidth
    }

    // 封面旋转交给 Core Animation 常驻驱动；暂停冻结当前相位，恢复继续，
    // 切歌 / 关闭旋转时经 resetToken 归零。
    // 让位门控用独立叶子修饰器（islandHandoffGate）读取逐帧接力进度：
    // 本视图 body 不读该环境值，接力逐帧失效不会连带旋转封面的光栅化重绘。
    private var cover: some View {
        RotatingCoverView(
            content: AnyView(coverContent.environment(\.displayScale, displayScale)),
            isRotating: isRotationActive,
            resetToken: rotationResetToken,
            songKey: songKey,
            rotationDuration: CoverDesign.rotationDuration,
            isFlipTransitionEnabled: !reduceMotion,
            isFallbackArtwork: viewModel.isUsingAppIconFallback,
            // 取设置中心开关（稳定用户意图）而非瞬态 isRotationActive：切歌瞬间
            // isPlaying / artwork 会短暂为 false，按瞬态判断会在旋转模式里冒出翻转。
            isRotationEnabledForChanges: settings.isCompactArtworkRotationEnabled && !reduceMotion
        )
        .frame(width: artworkSide, height: artworkSide)
        .islandHandoffGate(.source)
        .islandHandoffSource(id: "media", isActive: role == .resident && hasMedia)
        .frame(width: coverSize, height: coverSize)
        .shadow(
            color: coverAccentColor.opacity(
                isPlaying
                    ? CoverDesign.playingGlowOpacity
                    : CoverDesign.pausedGlowOpacity
            ),
            radius: CoverDesign.glowRadius
        )
        .animation(.easeOut(duration: CoverDesign.stateTransitionDuration), value: isPlaying)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(artworkAccessibilityLabel)
        .accessibilityValue(isPlaying ? "正在播放" : "已暂停")
    }

    private var coverContent: some View {
        ZStack {
            if !viewModel.isUsingAppIconFallback {
                artworkShape
                    .fill(.black.opacity(0.92))
            }

            artwork
        }
        .frame(width: artworkSide, height: artworkSide)
    }

    private var artwork: some View {
        ArtworkView(
            data: viewModel.displayArtwork,
            fallbackSystemName: "music.note",
            size: artworkSide,
            cornerRadius: viewModel.isUsingAppIconFallback ? 0 : artworkCornerRadius
        )
        .frame(width: artworkSide, height: artworkSide)
    }

    private var coverAccentColor: Color {
        glowColor ?? .white
    }

    private var artworkAccessibilityLabel: String {
        guard let info = viewModel.info else { return "媒体封面" }
        let artist = info.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return artist.isEmpty ? info.title : "\(info.title)，\(artist)"
    }
}
