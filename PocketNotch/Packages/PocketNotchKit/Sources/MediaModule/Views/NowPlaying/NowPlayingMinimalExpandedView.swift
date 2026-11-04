import SwiftUI

/// 简约模式复用锁屏音乐内容，仅由 Island 提供背景材质。
struct NowPlayingMinimalExpandedView: View {
    var viewModel: NowPlayingViewModel

    var body: some View {
        LockScreenMusicPlayerContent(viewModel: viewModel)
            .background(Color.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
