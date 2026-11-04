import PocketNotchCore
import SwiftUI

struct MediaNotificationHostView: View {
    var viewModel: NowPlayingViewModel
    @ObservedObject var notificationSettings: IslandNotificationSettings
    @Environment(\.notchHiddenIslandSize) private var hiddenIslandSize
    @Environment(\.notchPhysicalWidth) private var notchPhysicalWidth

    private var bannerWidth: CGFloat {
        IslandNotificationDesign.bannerWidth(
            hiddenIslandSize: hiddenIslandSize,
            notchPhysicalWidth: notchPhysicalWidth
        )
    }

    private var isNotificationVisible: Bool {
        viewModel.songNotification != nil || viewModel.audioOutputNotification != nil
    }

    var body: some View {
        Group {
            if isNotificationVisible {
                ZStack {
            // 最新切歌事件优先，避免仍处于音频输出提示周期时把歌曲通知遮住。
            if let note = viewModel.songNotification {
                        SongNotificationCard(
                            note: note,
                            artwork: note.artworkData,
                            palette: viewModel.spectrumColors,
                            width: bannerWidth,
                            height: IslandNotificationDesign.cardHeight,
                            dismissalEffect: notificationSettings.songChangeDismissalEffect,
                            onFinished: { viewModel.dismissSongNotification() }
                        )
                        // 换歌不换卡：材质（背景/模糊/描边）跨歌保持同一实例，
                        // 由卡片内部对内容做交叉渐变。若这里按 note.id 重建，
                        // 旧卡会无退场动画被立即销毁、新卡又从 opacity 0 淡入，
                        // 岛会先空一拍再浮现 —— 这就是切歌通知的「闪」。
                    } else if let output = viewModel.audioOutputNotification {
                        AudioOutputNotificationCard(
                            snapshot: output,
                            width: bannerWidth,
                            isDismissing: viewModel.isAudioOutputNotificationDismissing,
                            dismissalEffect: notificationSettings.audioOutputChangeDismissalEffect
                        )
                        .id("audio-output-\(output.deviceName)-\(output.deviceSymbolName)")
                    }
                }
                .padding(.top, IslandNotificationDesign.outerTopInset)
                .padding(.bottom, IslandNotificationDesign.outerBottomInset)
            }
        }
    }
}
