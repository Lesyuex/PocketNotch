import SwiftUI

/// 「此刻」页右侧系统统计区容器：磁盘小卡 + CPU/内存双栏卡，纵向堆叠。
struct NowPageSystemStatsContainerView: View {
    let viewModel: NowPageSystemStatusViewModel

    var body: some View {
        VStack(spacing: NowPageSystemStatsContainerView.Design.stackSpacing) {
            NowPageDiskCardView(viewModel: viewModel)
            NowPageCPUAndMemoryCardView(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private enum Design {
        static let stackSpacing: CGFloat = 10
    }
}