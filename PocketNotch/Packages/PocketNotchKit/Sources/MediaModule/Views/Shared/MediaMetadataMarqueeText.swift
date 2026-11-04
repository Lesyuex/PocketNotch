import AppKit
import PocketNotchCore
import SwiftUI

struct SongNotificationMarqueeMetrics {
    let distance: CGFloat
    let duration: Double
}

enum SongNotificationMarquee {
    static let edgeFade: CGFloat = 8
    static let initialHold: Double = 1.2
    static let endingHold: Double = 0.8

    private static let pointsPerSecond: CGFloat = 32
    private static let minimumDuration: Double = 1.5

    static func metrics(contentWidth: CGFloat, availableWidth: CGFloat) -> SongNotificationMarqueeMetrics {
        let overflow = max(contentWidth - availableWidth, 0)
        guard overflow > 4 else {
            return SongNotificationMarqueeMetrics(distance: 0, duration: 0)
        }

        // 必须滚过完整溢出宽度；限制移动距离会让长歌名尚未展示完就触发通知退场。
        let distance = overflow + IslandNotificationDesign.grid
        let duration = max(Double(distance / pointsPerSecond), minimumDuration)
        return SongNotificationMarqueeMetrics(distance: distance, duration: duration)
    }

    static func oneShotOffset(
        elapsed: Double,
        metrics: SongNotificationMarqueeMetrics,
        initialHold: Double = initialHold,
        endingHold: Double = endingHold
    ) -> CGFloat {
        guard metrics.distance > 0, metrics.duration > 0 else { return 0 }

        guard elapsed >= initialHold else { return 0 }

        let scrollElapsed = elapsed - initialHold
        guard scrollElapsed < metrics.duration + endingHold else {
            return 0
        }
        guard scrollElapsed < metrics.duration else {
            return -metrics.distance
        }

        return -metrics.distance * CGFloat(scrollElapsed / metrics.duration)
    }

    static func mask(
        availableWidth: CGFloat,
        contentWidth: CGFloat,
        offset: CGFloat
    ) -> LinearGradient {
        guard availableWidth > 0 else {
            return LinearGradient(
                colors: [.white, .white],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        let distance = metrics(contentWidth: contentWidth, availableWidth: availableWidth).distance
        let remainingOverflow = max(contentWidth - availableWidth, 0) + offset
        let showsLeadingFade = distance > 0 && offset < -1
        let showsTrailingFade = distance > 0 && remainingOverflow > 1
        let fadeFraction = min(edgeFade / availableWidth, 0.08)

        return LinearGradient(
            stops: [
                .init(color: showsLeadingFade ? .clear : .white, location: 0),
                .init(color: .white, location: fadeFraction),
                .init(color: .white, location: 1 - fadeFraction),
                .init(color: showsTrailingFade ? .clear : .white, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct MediaMetadataMarqueeText: View {
    let text: String
    let font: Font
    let nsFont: NSFont
    let foregroundColor: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0

    private var contentWidth: CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: nsFont]).width)
    }

    private var lineHeight: CGFloat {
        ceil(nsFont.ascender - nsFont.descender + nsFont.leading)
    }

    var body: some View {
        GeometryReader { proxy in
            line(availableWidth: proxy.size.width)
        }
        .frame(height: lineHeight)
    }

    @ViewBuilder
    private func line(availableWidth: CGFloat) -> some View {
        let metrics = SongNotificationMarquee.metrics(
            contentWidth: contentWidth,
            availableWidth: availableWidth
        )
        let shouldAnimate = metrics.distance > 0 && !reduceMotion

        if shouldAnimate {
            scrollingText(offset: offset, availableWidth: availableWidth)
                .mask {
                    SongNotificationMarquee.mask(
                        availableWidth: availableWidth,
                        contentWidth: contentWidth,
                        offset: offset
                    )
                }
                .task(id: taskID(availableWidth: availableWidth)) {
                    await runOneShotMarquee(metrics: metrics)
                }
        } else {
            Text(text)
                .font(font)
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: availableWidth, height: lineHeight, alignment: .leading)
                .task(id: taskID(availableWidth: availableWidth)) {
                    await MainActor.run {
                        offset = 0
                    }
                }
        }
    }

    private func taskID(availableWidth: CGFloat) -> String {
        "\(text)|\(Int(availableWidth.rounded()))|\(reduceMotion)"
    }

    private func runOneShotMarquee(metrics: SongNotificationMarqueeMetrics) async {
        await MainActor.run {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                offset = 0
            }
        }

        do {
            try await Task.sleep(for: .seconds(SongNotificationMarquee.initialHold))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        await MainActor.run {
            withAnimation(.linear(duration: metrics.duration)) {
                offset = -metrics.distance
            }
        }

        do {
            try await Task.sleep(for: .seconds(metrics.duration + SongNotificationMarquee.endingHold))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        await MainActor.run {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                offset = 0
            }
        }
    }

    private func scrollingText(offset: CGFloat, availableWidth: CGFloat) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: offset)
            .frame(width: availableWidth, height: lineHeight, alignment: .leading)
            .clipped()
    }
}
