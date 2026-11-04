import Charts
import PocketNotchShared
import Foundation
import SwiftUI

private enum StockWatchlistLayout {
    static let rowHeight: CGFloat = 44
    static let headerHeight: CGFloat = 28
    static let columnSpacing: CGFloat = 8
    static let horizontalPadding: CGFloat = 0
    static let rankWidth: CGFloat = 20
    static let identityWidth: CGFloat = 88
    static let referencePriceWidth: CGFloat = 52
    static let currentPriceWidth: CGFloat = 58
    static let changeAmountWidth: CGFloat = 50
    static let volumeWidth: CGFloat = 46
    static let sparklineMinWidth: CGFloat = 64
    static let sparklineHorizontalInset: CGFloat = 4
    static let changePercentWidth: CGFloat = 54
}

struct StockExpandedView: View {
    @ObservedObject var viewModel: StockNotificationViewModel
    @State private var selectedQuoteID: String

    init(viewModel: StockNotificationViewModel) {
        self.viewModel = viewModel
        _selectedQuoteID = State(initialValue: viewModel.selectedQuote.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
                .offset(y: -8)
                .padding(.bottom, -8)

            if viewModel.quotes.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.quotes.enumerated()), id: \.element.id) { index, quote in
                            let series = viewModel.marketSeries(for: quote)
                            StockWatchlistRow(
                                index: index + 1,
                                quote: quote,
                                intraday: series.intraday,
                                openPrice: series.openPrice,
                                previousClose: series.previousClose,
                                showsDivider: index < viewModel.quotes.count - 1,
                                action: { selectedQuoteID = quote.id }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: selectedQuoteID) {
            await viewModel.observeMarketData(for: selectedQuoteID)
        }
    }

    private var headerRow: some View {
        HStack(spacing: StockWatchlistLayout.columnSpacing) {
            Text("#")
                .frame(width: StockWatchlistLayout.rankWidth, alignment: .center)

            Text("stock.headerName")
                .frame(width: StockWatchlistLayout.identityWidth, alignment: .leading)

            Text("")
                .frame(
                    minWidth: StockWatchlistLayout.sparklineMinWidth,
                    maxWidth: .infinity,
                    alignment: .center
                )

            Text("stock.currentPrice")
                .frame(width: StockWatchlistLayout.currentPriceWidth, alignment: .trailing)

            Text("stock.changeAmount")
                .frame(width: StockWatchlistLayout.changeAmountWidth, alignment: .trailing)

            Text("stock.volume")
                .frame(width: StockWatchlistLayout.volumeWidth, alignment: .trailing)

            Text("stock.openPrice")
                .frame(width: StockWatchlistLayout.referencePriceWidth, alignment: .trailing)

            Text("stock.previousClose")
                .frame(width: StockWatchlistLayout.referencePriceWidth, alignment: .trailing)

            Text("stock.changePercent")
                .frame(width: StockWatchlistLayout.changePercentWidth, alignment: .trailing)
        }
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(.white.opacity(0.40))
        .monospacedDigit()
        .padding(.horizontal, StockWatchlistLayout.horizontalPadding)
        .frame(height: StockWatchlistLayout.headerHeight)
        .background(.white.opacity(0.018))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.07))
                .frame(height: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.32))

            Text("stock.empty")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

private struct StockWatchlistRow: View {
    let index: Int
    let quote: StockQuote
    let intraday: [StockIntradayPoint]
    let openPrice: Double
    let previousClose: Double
    let showsDivider: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isChangeBreathing = false
    @State private var changeBreathingTask: Task<Void, Never>?

    private var tint: Color {
        quote.isPositive ? .red : .green
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: StockWatchlistLayout.columnSpacing) {
                Text(index.formatted(.number.precision(.integerLength(2))))
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.34))
                    .frame(width: StockWatchlistLayout.rankWidth, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(quote.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(quote.code)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
                }
                .frame(width: StockWatchlistLayout.identityWidth, alignment: .leading)

                StockMiniSparkline(
                    intraday: intraday,
                    previousClose: previousClose,
                    isPositive: quote.isPositive
                )
                .padding(.horizontal, StockWatchlistLayout.sparklineHorizontalInset)
                .frame(
                    minWidth: StockWatchlistLayout.sparklineMinWidth,
                    maxWidth: .infinity,
                    minHeight: 24,
                    maxHeight: 24
                )

                Text(quote.price)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(width: StockWatchlistLayout.currentPriceWidth, alignment: .trailing)

                Text(quote.changeAmount)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(width: StockWatchlistLayout.changeAmountWidth, alignment: .trailing)

                Text(quote.volume)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(width: StockWatchlistLayout.volumeWidth, alignment: .trailing)

                referencePrice(openPrice)
                referencePrice(previousClose)

                Text(quote.change)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(width: StockWatchlistLayout.changePercentWidth, alignment: .trailing)
            }
            .padding(.horizontal, StockWatchlistLayout.horizontalPadding)
            .frame(maxWidth: .infinity)
            .frame(height: StockWatchlistLayout.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(
            StockWatchlistRowButtonStyle(
                isHovering: isHovering,
                isChangeBreathing: isChangeBreathing,
                pulseColor: tint,
                reduceMotion: reduceMotion
            )
        )
        .onHover { isHovering = $0 }
        .onChange(of: quote.changePercent) { oldValue, newValue in
            guard oldValue != newValue else { return }
            startChangeBreathing()
        }
        .onDisappear {
            changeBreathingTask?.cancel()
            changeBreathingTask = nil
        }
        .accessibilityLabel(
            String(format: L10n.tr("stock.rowAccessibilityFormat"), index, quote.name, priceText(openPrice), priceText(previousClose), quote.price, quote.changeAmount, quote.change, quote.volume)
        )
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(.white.opacity(0.055))
                    .frame(height: 1)
                    .padding(.leading, StockWatchlistLayout.horizontalPadding + StockWatchlistLayout.rankWidth + StockWatchlistLayout.columnSpacing)
                    .padding(.trailing, StockWatchlistLayout.horizontalPadding)
                    .allowsHitTesting(false)
            }
        }
    }

    private func referencePrice(_ price: Double) -> some View {
        Text(priceText(price))
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.46))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: StockWatchlistLayout.referencePriceWidth, alignment: .trailing)
    }

    private func priceText(_ price: Double) -> String {
        String(format: "%.*f", displayedDecimalPlaces, price)
    }

    private var displayedDecimalPlaces: Int {
        guard let decimalSeparator = quote.price.lastIndex(of: ".") else { return 0 }
        return min(quote.price.distance(from: quote.price.index(after: decimalSeparator), to: quote.price.endIndex), 4)
    }

    private func startChangeBreathing() {
        changeBreathingTask?.cancel()
        guard !reduceMotion else { return }

        changeBreathingTask = Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.42)) {
                isChangeBreathing = true
            }
            do {
                try await Task.sleep(for: .milliseconds(720))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.72)) {
                isChangeBreathing = false
            }
        }
    }
}

private struct StockMiniSparkline: View {
    let intraday: [StockIntradayPoint]
    let previousClose: Double
    let isPositive: Bool

    private var lineColor: Color {
        isPositive ? .red : .green
    }

    var body: some View {
        if intraday.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.white.opacity(0.025))

                Rectangle()
                    .fill(.white.opacity(0.10))
                    .frame(height: 1)
                    .padding(.horizontal, 5)
            }
        } else {
            Chart {
                RuleMark(y: .value(L10n.tr("stock.previousClose"), previousClose))
                    .foregroundStyle(.white.opacity(0.12))
                    .lineStyle(StrokeStyle(lineWidth: 0.6, dash: [2, 2]))

                ForEach(intraday) { point in
                    LineMark(
                        x: .value(L10n.tr("stock.minute"), point.minute),
                        y: .value(L10n.tr("stock.price"), point.price),
                        series: .value(L10n.tr("stock.series"), "价格")
                    )
                    .foregroundStyle(lineColor.opacity(0.88))
                    .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)
                }
            }
            .chartXScale(domain: 0.0...240.0)
            .chartYScale(domain: sparklineYDomain)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartPlotStyle { plotArea in
                plotArea
                    .background(.white.opacity(0.025))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
    }

    private var sparklineYDomain: ClosedRange<Double> {
        guard !intraday.isEmpty else { return 0...1 }
        let prices = intraday.map(\.price)
        let minPrice = min(prices.min() ?? previousClose, previousClose)
        let maxPrice = max(prices.max() ?? previousClose, previousClose)
        let padding = max((maxPrice - minPrice) * 0.15, maxPrice * 0.001)
        return (minPrice - padding)...(maxPrice + padding)
    }
}

private struct StockWatchlistRowButtonStyle: ButtonStyle {
    let isHovering: Bool
    let isChangeBreathing: Bool
    let pulseColor: Color
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            .white.opacity(
                                configuration.isPressed
                                    ? 0.10
                                    : (isHovering ? 0.055 : 0)
                            )
                        )
                }
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(pulseColor.opacity(isChangeBreathing ? 0.05 : 0))
            }
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.995)
            .animation(
                reduceMotion ? nil : .spring(response: 0.14, dampingFraction: 1),
                value: configuration.isPressed
            )
            .animation(
                .easeOut(duration: 0.10),
                value: isHovering
            )
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.42),
                value: isChangeBreathing
            )
    }
}
