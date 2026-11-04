import PocketNotchShared
import SwiftUI

struct NowPlayingCollapsedView: View {
    var viewModel: NowPlayingViewModel

    var body: some View {
        return VStack(spacing: 5) {
            HStack(spacing: 8) {
                ArtworkFlipTransitionView(
                    data: viewModel.displayArtwork,
                    fallbackSystemName: viewModel.info?.isPlaying == true ? "waveform" : "music.note",
                    size: 34,
                    cornerRadius: 7
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.info?.title ?? "未在播放")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 5) {
                    Button(action: viewModel.previous) {
                        Image(systemName: "backward.fill")
                    }
                    .help("上一首")

                    Button(action: viewModel.togglePlay) {
                        Image(systemName: viewModel.info?.isPlaying == true ? "pause.fill" : "play.fill")
                    }
                    .help(viewModel.info?.isPlaying == true ? "暂停" : "播放")

                    Button(action: viewModel.next) {
                        Image(systemName: "forward.fill")
                    }
                    .help("下一首")
                }
                .buttonStyle(MediaControlButtonStyle(size: 28))
            }

            if let info = viewModel.info {
                MediaProgressView(info: info)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 8)
    }

    private var subtitle: String {
        guard let info = viewModel.info else { return viewModel.statusText }
        if !info.artist.isEmpty, let album = info.album, !album.isEmpty {
            return "\(info.artist) - \(album)"
        }
        if !info.artist.isEmpty {
            return info.artist
        }
        return info.isPlaying ? "正在播放" : "已暂停"
    }
}
