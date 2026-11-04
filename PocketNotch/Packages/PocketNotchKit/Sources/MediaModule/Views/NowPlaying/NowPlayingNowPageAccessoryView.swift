import AppKit
import PocketNotchCore
import SwiftUI

/// 「此刻」页的媒体播放卡片：封面 + 信息 + 进度 + 控制。
struct NowPlayingNowPageAccessoryView: View {
    var viewModel: NowPlayingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        nowPageCard
    }

    /// 「此刻」页的媒体播放卡片。
    /// 卡片本身不铺玻璃材质，直接浮在岛体上，保持页内连续。
    private var nowPageCard: some View {
        cardContent
            .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 13) {
                MediaLaunchableArtwork(
                    viewModel: viewModel,
                    fallbackSystemName: "music.note",
                    size: LeftCoverCardDesign.coverSize,
                    cornerRadius: LeftCoverCardDesign.coverCornerRadius,
                    showsApplicationBadge: false
                )
                .islandHandoffDestination(id: "media")
                .islandHandoffGate(.destination)
                .focusEffectDisabled()

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 6) {
                        MediaMetadataMarqueeText(
                            text: viewModel.info?.title ?? "未在播放",
                            font: .system(size: 12, weight: .semibold),
                            nsFont: .systemFont(ofSize: 12, weight: .semibold),
                            foregroundColor: .white.opacity(0.92)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offset(y: -1)
                        .help(viewModel.info?.title ?? "未在播放")

                        statsMelodyStatus
                    }
                    .frame(maxWidth: .infinity)

                    MediaMetadataMarqueeText(
                        text: statsPlayerSubtext,
                        font: .system(size: 10.5, weight: .medium),
                        nsFont: .systemFont(ofSize: 10.5, weight: .medium),
                        foregroundColor: .white.opacity(0.52)
                    )
                    .offset(y: 1)
                    .help(statsPlayerSubtext)
                }
                .frame(maxWidth: .infinity)
            }

            statsProgressRow

            HStack(spacing: 0) {
                    statsShuffleButton
                    Spacer(minLength: 0)
                    statsPreviousButton
                    Spacer(minLength: 0)
                    statsPlayButton
                    Spacer(minLength: 0)
                    statsNextButton
                    Spacer(minLength: 0)
                    statsOutputDeviceIcon
                }
                .frame(maxWidth: .infinity)
                    .padding(.leading, 2 - Self.statsEdgeControlInset)
                    .padding(.trailing, -Self.statsEdgeControlInset)
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .padding(.top, LeftCoverCardDesign.contentTopInset)
        .frame(width: LeftCoverCardDesign.cardWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var statsProgressRow: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            HStack(alignment: .center, spacing: 8) {
                Text(statsTimeStrings(at: context.date).elapsed)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.leading, 2)

                CompactProgressTrack(
                    progress: statsPlaybackProgress(at: context.date),
                    colors: viewModel.spectrumColors,
                    onSeek: { ratio in
                        guard let info = viewModel.info,
                              let duration = info.duration,
                              duration > 0 else { return }
                        viewModel.seek(to: duration * ratio)
                    }
                )

                Text(statsTimeStrings(at: context.date).remaining)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(minWidth: 26, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .medium))
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func statsTimeStrings(at date: Date) -> (elapsed: String, remaining: String) {
        guard let info = viewModel.info,
              let elapsed = info.elapsedTime,
              let duration = info.duration,
              duration > 0 else { return ("0:00", "--:--") }
        let advanced = info.isPlaying ? max(date.timeIntervalSince(info.updatedAt), 0) : 0
        let current = min(max(elapsed + advanced, 0), duration)
        let remain = duration - current
        return (Self.simpleTime(current), "-" + Self.simpleTime(remain))
    }

    private static func simpleTime(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded(.down)), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var statsMelodyStatus: some View {
        SpectrumBarsView(
            source: viewModel.spectrumBuffer,
            colors: viewModel.spectrumColors,
            isActive: viewModel.info?.isPlaying == true,
            reduceMotion: reduceMotion,
            configuration: viewModel.musicSpectrumConfiguration,
            barGradientsByBarCount: viewModel.spectrumBarGradientsByBarCount
        )
        .frame(width: 18, height: 18)
       // .border(.red, width: 1)
        .opacity(viewModel.info == nil ? 0 : 1)
        .accessibilityHidden(true)
    }

    private var statsPlayerSubtext: String {
        guard let info = viewModel.info else { return "等待播放" }
        let artist = info.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !artist.isEmpty else { return "未知歌手" }
        return artist
    }

    /// 边侧控制按钮（34pt 命中框、38pt 视觉框）的图标字形居中绘制，
    /// 相对框缘的光学内缩；进度行时间文本贴行边，
    /// 因此按钮行需按内缩量做负内距，让最左/最右两个图标字形能与时间文本对齐。
    private static let statsEdgeControlInset: CGFloat = 8

    private var statsShuffleButton: some View {
        Button(action: {
            Task { await viewModel.toggleShuffle() }
        }) {
            Image(systemName: "shuffle")
        }
        .buttonStyle(
            MediaBorderlessControlButtonStyle(
                size: 36,
                visualSize: 36,
                isSelected: viewModel.isShuffleEnabled,
                foregroundColor: .white
            )
        )
        .help(viewModel.isShuffleEnabled ? "关闭随机播放" : "开启随机播放")
        .accessibilityLabel("随机播放")
    }

    private var statsPlayButton: some View {
        Button(action: viewModel.togglePlay) {
            Image(systemName: viewModel.info?.isPlaying == true ? "pause.fill" : "play.fill")
        }
        .buttonStyle(
            MediaBorderlessControlButtonStyle(
                size: 36,
                visualSize: 36,
                isPrimary: true,
                foregroundColor: .white,
                iconSize: 17
            )
        )
        .help(viewModel.info?.isPlaying == true ? "暂停" : "播放")
    }

    private var statsNextButton: some View {
        Button(action: viewModel.next) {
            Image(systemName: "forward.end.fill")
        }
        .buttonStyle(
            MediaBorderlessControlButtonStyle(
                size: 36,
                visualSize: 36,
                foregroundColor: .white,
                iconSize: 16
            )
        )
        .help("下一首")
    }

    /// 当前播放设备图标，点击打开设备选择（效果同主页）。
    private var statsOutputDeviceIcon: some View {
        MediaOutputPickerButton(
            viewModel: viewModel,
            size: 36,
            visualSize: 36,
            usesBorderlessStyle: true,
            borderlessForegroundColor: .white.opacity(0.55)
        )
    }

    private var statsPreviousButton: some View {
        Button(action: viewModel.previous) {
            Image(systemName: "backward.end.fill")
        }
        .buttonStyle(
            MediaBorderlessControlButtonStyle(
                size: 36,
                visualSize: 36,
                foregroundColor: .white,
                iconSize: 16
            )
        )
        .help("上一首")
    }

    private func statsPlaybackProgress(at date: Date) -> CGFloat {
        guard let info = viewModel.info,
              let elapsed = info.elapsedTime,
              let duration = info.duration,
              duration > 0 else { return 0 }
        let advanced = info.isPlaying ? max(date.timeIntervalSince(info.updatedAt), 0) : 0
        return min(max((elapsed + advanced) / duration, 0), 1)
    }
}

/// 左侧音乐卡的设计尺寸与样式参数；封面卡（音乐卡片 2）等比例复用其高度。
/// 置于文件作用域，供封面卡与音乐卡共享同一处尺寸来源。
enum LeftCoverCardDesign {
    static let cardWidth: CGFloat = IslandLayoutToken.expandedNowPageLeadingCardWidth
    static let cardHeight: CGFloat = IslandLayoutToken.expandedNowPageCardHeight
    static let cardCornerRadius: CGFloat = 16
    static let coverSize: CGFloat = 48
    static let coverCornerRadius: CGFloat = 8
    static let contentTopInset: CGFloat = 14
}

/// 紧凑版主页进度条：细胶囊轨道 + 频谱色渐变填充 + 悬停浮现白色圆点，支持拖动跳转。
private struct CompactProgressTrack: View {
    let progress: Double
    let colors: [Color]
    let onSeek: (Double) -> Void

    @State private var scrubRatio: Double?
    @State private var isHovering = false

    private var displayedRatio: Double {
        min(max(scrubRatio ?? progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(MediaPaletteStyle.trackColor(from: colors))

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: Array(MediaPaletteStyle.foregroundColors(from: colors).reversed()),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: w * displayedRatio)

                    Circle()
                        .fill(.white.opacity(0.96))
                        .frame(width: 6, height: 6)
                        .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)
                        .offset(x: min(max(w * displayedRatio - 3, 0), max(w - 6, 0)))
                        .opacity(isHovering || scrubRatio != nil ? 1 : 0)
                        .animation(.easeOut(duration: 0.12), value: isHovering)
                }
                .frame(height: 6)
                Spacer(minLength: 0)
            }
            .contentShape(Capsule())
            .onHover { isHovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        scrubRatio = min(max(value.location.x / w, 0), 1)
                    }
                    .onEnded { value in
                        onSeek(min(max(value.location.x / w, 0), 1))
                        scrubRatio = nil
                    }
            )
        }
        .frame(height: 11)
        .help("拖动以调整播放进度")
    }
}
