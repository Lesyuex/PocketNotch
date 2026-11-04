import PocketNotchShared
import SwiftUI
import PocketNotchCore

/// compact 尾随区域：有媒体时展示动态旋律条，新蓝牙外设连接时临时切为环形电量。
/// 暂停仍属于有媒体，保留 compact 内容但停止频谱采样（守耗电铁律）。
struct NowPlayingHiddenTrailingView: View {
    var viewModel: NowPlayingViewModel
    @ObservedObject var settings: IslandNotificationSettings
    let role: CompactMediaContentRole
    @Environment(\.notchHiddenIslandSize) private var hiddenIslandSize
    @Environment(\.islandCompactContentSize) private var islandCompactContentSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var diameter: CGFloat {
        islandCompactContentSize?.height
            ?? CompactIslandContentSpec.resolvedContentHeight(for: hiddenIslandSize.height)
    }

    private var contentWidth: CGFloat {
        CompactIslandContentSpec.defaultSideContentWidth
    }

    /// 音量通知只保留横条，让横条占满拓宽后的耳区；其余角色维持 26pt 窄槽。
    private var usesWideVolumeBar: Bool {
        role == .notification && viewModel.volumePresentation != nil
    }

    private var hasMedia: Bool {
        viewModel.isCompactMediaDisplayActive
    }

    private var isPlaying: Bool {
        viewModel.info?.isPlaying == true
    }

    private var isMelodyActive: Bool {
        isPlaying
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
                AudioVolumePercentage(
                    percentage: volume.displayedPercentage,
                    height: diameter,
                    fill: volumeBarFill,
                    showsPercentage: settings.isRightEarBatteryEnabled
                )
            } else if role == .notification,
                      let headphones = viewModel.headphoneConnectionPresentation {
                HeadphoneBatteryRing(
                    percentage: headphones.batteryPercentage,
                    deviceName: headphones.deviceName,
                    diameter: diameter
                )
                .scaleEffect(
                    reduceMotion || !viewModel.isHeadphoneConnectionDismissing ? 1 : 0.97
                )
                .offset(
                    y: reduceMotion || !viewModel.isHeadphoneConnectionDismissing ? 0 : 1
                )
                .opacity(viewModel.isHeadphoneConnectionDismissing ? 0 : 1)
                .animation(
                    PocketNotchTheme.islandCompactModuleAnimation(
                        isVisible: !viewModel.isHeadphoneConnectionDismissing,
                        reduceMotion: reduceMotion
                    ),
                    value: viewModel.isHeadphoneConnectionDismissing
                )
            } else if role == .resident, hasMedia {
                SpectrumBarsView(
                    source: viewModel.spectrumBuffer,
                    colors: viewModel.spectrumColors,
                    isActive: isMelodyActive && !reduceMotion,
                    reduceMotion: reduceMotion,
                    configuration: viewModel.musicSpectrumConfiguration,
                    barGradientsByBarCount: viewModel.spectrumBarGradientsByBarCount
                )
                // 展开态收回时，compact 内容层已经负责整体入场。旋律自身若再执行
                // transition，SwiftUI 会同时保留旧快照和新实例，表现为右耳两份频谱重叠。
                .id("compact-media-melody")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(isPlaying ? "正在播放" : "已暂停")
            } else {
                Color.clear.frame(width: diameter, height: diameter)
            }
        }
        // 频谱固定使用最短灵动模式也能保证的 26pt 右耳宽度；更长模式只增加留白，
        // 避免用户先调大柱宽/间距、再缩短灵动模式时裁掉柱子。
        .frame(
            width: usesWideVolumeBar ? nil : contentWidth,
            height: diameter,
            alignment: .trailing
        )
        .frame(
            maxWidth: role == .notification ? .infinity : nil,
            maxHeight: .infinity,
            alignment: .trailing
        )
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

    private var volumeBarFill: VolumeBarFillStyle {
        VolumeBarFillResolver.resolve(
            style: settings.volumeBarColorStyle,
            palette: viewModel.spectrumColors,
            hasActiveMedia: hasMedia && isPlaying,
            customColor: settings.volumeBarCustomColor,
            usesCustomGradient: settings.isVolumeBarCustomGradientEnabled,
            customGradientEndColor: settings.volumeBarCustomGradientEndColor
        )
    }
}
