import PocketNotchShared
import SwiftUI

/// 极简媒体缩略图：旋转小封面由 Core Animation 常驻驱动（GPU，无 TimelineView）。
/// 暂停冻结当前相位，恢复继续；切歌角度归零。
struct NowPlayingMinimalView: View {
    private static let rotationDuration: TimeInterval = 4

    var viewModel: NowPlayingViewModel
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isPlaying: Bool {
        viewModel.info?.isPlaying == true
    }

    private var songKey: String {
        guard let info = viewModel.info else { return "" }
        return info.title + "\u{1}" + info.artist
    }

    var body: some View {
        return RotatingCoverView(
            content: AnyView(artworkContent.environment(\.displayScale, displayScale)),
            isRotating: isPlaying,
            resetToken: songKey,
            songKey: songKey,
            rotationDuration: Self.rotationDuration,
            isFlipTransitionEnabled: !reduceMotion,
            isFallbackArtwork: viewModel.isUsingAppIconFallback,
            isRotationEnabledForChanges: isPlaying
        )
        .frame(width: 20, height: 20)
    }

    private var artworkContent: some View {
        ArtworkView(
            data: viewModel.displayArtwork,
            fallbackSystemName: "music.note",
            size: 20,
            cornerRadius: 10
        )
    }
}
