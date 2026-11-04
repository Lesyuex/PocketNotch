import SwiftUI
import PocketNotchCore

struct StockCompactNameContent: View {
    let name: String

    var body: some View {
        ZStack(alignment: .leading) {
            Text(name)
                .font(.system(size: PocketNotchTheme.islandCompactFontSize, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct StockCompactChangeContent: View {
    let change: String
    let isPositive: Bool

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(change)
                .font(.system(
                    size: PocketNotchTheme.islandCompactFontSize,
                    weight: .semibold,
                    design: .monospaced
                ))
                .foregroundStyle(isPositive ? .red : .green)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

struct StockHiddenLeadingView: View {
    @ObservedObject var viewModel: StockNotificationViewModel

    var body: some View {
        StockCompactNameContent(name: viewModel.selectedQuote.name)
        .compactIslandContentVisible(true)
        .transition(.opacity)
        .id(viewModel.selectedQuote.id)
    }
}

struct StockHiddenTrailingView: View {
    @ObservedObject var viewModel: StockNotificationViewModel

    var body: some View {
        let quote = viewModel.selectedQuote
        StockCompactChangeContent(change: quote.change, isPositive: quote.isPositive)
        .compactIslandContentVisible(true)
        .transition(.opacity)
        .id(quote.id)
    }
}
