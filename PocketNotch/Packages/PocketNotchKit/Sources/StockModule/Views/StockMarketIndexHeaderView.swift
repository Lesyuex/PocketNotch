import SwiftUI
import PocketNotchShared

struct StockMarketIndexHeaderView: View {
    @ObservedObject var viewModel: StockMarketIndexViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            indexItem(title: L10n.tr("stock.indexShanghai"), quote: viewModel.quote(for: "000001"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(Rectangle().stroke(.red, lineWidth: 1))

            indexItem(title: L10n.tr("stock.indexChiNext"), quote: viewModel.quote(for: "399006"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(Rectangle().stroke(.orange, lineWidth: 1))
        }
        .frame(maxHeight: .infinity)
        .overlay {
            Rectangle()
                .fill(.white.opacity(0.09))
                .frame(width: 1, height: 22)
        }
        .overlay(Rectangle().stroke(.purple, lineWidth: 1))
        .task {
            await viewModel.observe()
        }
    }

    private func indexItem(title: String, quote: StockMarketIndexQuote?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))

                Text(valueText(for: quote))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .monospacedDigit()
                    .stockNumericTransition(
                        value: quote?.value ?? 0,
                        reduceMotion: reduceMotion
                    )
            }
            .lineLimit(1)

            HStack(spacing: 5) {
                Text(changeAmountText(for: quote))
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(changeColor(for: quote))
                    .monospacedDigit()
                    .stockNumericTransition(
                        value: quote?.changeAmount ?? 0,
                        reduceMotion: reduceMotion
                    )

                Text(changePercentText(for: quote))
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(changeColor(for: quote))
                    .monospacedDigit()
                    .stockNumericTransition(
                        value: quote?.changePercent ?? 0,
                        reduceMotion: reduceMotion
                    )
            }
            .lineLimit(1)
        }
        .frame(height: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(title: title, quote: quote))
    }

    private func valueText(for quote: StockMarketIndexQuote?) -> String {
        guard let quote else { return "--" }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), quote.value)
    }

    private func changeAmountText(for quote: StockMarketIndexQuote?) -> String {
        guard let quote else { return "--" }
        return signedText(quote.changeAmount)
    }

    private func changePercentText(for quote: StockMarketIndexQuote?) -> String {
        guard let quote else { return "--" }
        return "\(signedText(quote.changePercent))%"
    }

    private func signedText(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return String(
            format: "%@%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            sign,
            value
        )
    }

    private func changeColor(for quote: StockMarketIndexQuote?) -> Color {
        guard let quote else { return .white.opacity(0.32) }
        if quote.changePercent > 0 { return .red.opacity(0.86) }
        if quote.changePercent < 0 { return .green.opacity(0.86) }
        return .white.opacity(0.52)
    }

    private func accessibilityText(title: String, quote: StockMarketIndexQuote?) -> String {
        guard let quote else { return String(format: L10n.tr("stock.indexFetchingFormat"), title) }
        return String(format: L10n.tr("stock.indexQuoteFormat"), title, valueText(for: quote), changeAmountText(for: quote), changePercentText(for: quote))
    }
}
