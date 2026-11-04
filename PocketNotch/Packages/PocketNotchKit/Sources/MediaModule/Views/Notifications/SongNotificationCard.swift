import AppKit
import PocketNotchCore
import SwiftUI

struct SongNotificationCard: View {
    let note: SongNotification
    let artwork: Data?
    let palette: [Color]
    let width: CGFloat
    let height: CGFloat
    var dismissalEffect: IslandNotificationDismissalEffect = .standard
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var titleOffset: CGFloat = 0
    @State private var detailOffset: CGFloat = 0
    @State private var appeared = false
    @State private var isDismissing = false

    private var textAvailable: CGFloat {
        max(
            width
                - IslandNotificationDesign.contentLeadingInset
                - IslandNotificationDesign.contentTrailingInset
                - IslandNotificationDesign.leadingVisualSize
                - IslandNotificationDesign.contentGap,
            64
        )
    }

    private var detailText: String {
        [note.artist, note.album]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " - ")
    }

    private var artworkShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: IslandNotificationDesign.leadingVisualCorner, style: .continuous)
    }

    private var accentColor: Color {
        palette.first ?? .white
    }

    private var tintColors: [Color] {
        guard let primary = palette.first else {
            return [.white.opacity(0.055), .clear]
        }
        let secondary = palette.dropFirst().first ?? primary
        return [primary.opacity(0.16), secondary.opacity(0.07), .clear]
    }

    var body: some View {
        IslandNotificationCard(
            width: width,
            height: height,
            accentColor: accentColor,
            tintColors: tintColors,
            dismissalEffect: dismissalEffect,
            isDismissing: isDismissing
        ) {
            HStack(spacing: IslandNotificationDesign.contentGap) {
                artworkView

                VStack(alignment: .leading, spacing: MediaMetadataStyle.lineGap) {
                    scrollingLine(
                        contentWidth: titleWidth,
                        offset: titleOffset
                    ) {
                        titleLine
                    }

                    if !detailText.isEmpty {
                        scrollingLine(
                            contentWidth: detailWidth,
                            offset: detailOffset
                        ) {
                            Text(detailText)
                                .font(MediaMetadataStyle.detailFont)
                                .foregroundStyle(MediaMetadataStyle.detailColor)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
                .frame(width: textAvailable, alignment: .leading)
            }
            .padding(.leading, IslandNotificationDesign.contentLeadingInset)
            .padding(.trailing, IslandNotificationDesign.contentTrailingInset)
            .frame(width: width, height: height)
            // 只有内容换歌重播，材质不换：旧内容淡出、新内容淡入在同一张卡里交叠。
            .id(note.id)
            .transition(.opacity)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.22),
            value: note.id
        )
        .opacity(appeared ? 1 : 0)
        .blur(radius: appeared || reduceMotion ? 0 : 1.5)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.985, anchor: .top)
        .offset(y: appeared || reduceMotion ? 0 : -4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .onAppear {
            // 出现动画只跟随卡片生命周期。原先放在 runShow 里每首歌重播一次，
            // 换歌就等于整卡从全透明重来一遍。
            withAnimation(
                reduceMotion ? .easeOut(duration: 0.16) : IslandNotificationDesign.insertionAnimation
            ) {
                appeared = true
            }
        }
        .task(id: note.id) { await runShow() }
    }

    private var artworkView: some View {
        ArtworkView(
            data: artwork,
            fallbackSystemName: "music.note",
            size: IslandNotificationDesign.leadingVisualSize,
            cornerRadius: IslandNotificationDesign.leadingVisualCorner
        )
        .overlay {
            artworkShape
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.24), .white.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: accentColor.opacity(0.16), radius: 5)
        .shadow(color: .black.opacity(0.38), radius: 4, y: 2)
    }

    private var titleLine: some View {
        Text(note.title)
            .font(MediaMetadataStyle.titleFont)
            .foregroundStyle(MediaMetadataStyle.titleColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func scrollingLine<Content: View>(
        contentWidth: CGFloat,
        offset: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .offset(x: offset)
            .frame(width: textAvailable, alignment: .leading)
            .clipped()
            .mask {
                marqueeMask(contentWidth: contentWidth, offset: offset)
            }
    }

    private func marqueeMask(contentWidth: CGFloat, offset: CGFloat) -> some View {
        SongNotificationMarquee.mask(
            availableWidth: textAvailable,
            contentWidth: contentWidth,
            offset: offset
        )
    }

    private var titleWidth: CGFloat {
        ceil((note.title as NSString).size(withAttributes: [.font: MediaMetadataStyle.titleNSFont]).width)
    }

    private var detailWidth: CGFloat {
        ceil((detailText as NSString).size(withAttributes: [.font: MediaMetadataStyle.detailNSFont]).width)
    }

    private var accessibilityText: String {
        detailText.isEmpty ? note.title : "\(note.title)，\(detailText)"
    }

    private func runShow() async {
        // 新歌打断退场：反向动画回到定格，而不是瞬切。
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.2)) {
            titleOffset = 0
            detailOffset = 0
            isDismissing = false
        }
        guard await sleep(milliseconds: reduceMotion ? 180 : 400) else { return }

        let titleScroll = scrollMetrics(for: titleWidth)
        let detailScroll = scrollMetrics(for: detailWidth)
        let scrollDuration = max(titleScroll.duration, detailScroll.duration)

        if scrollDuration > 0, !reduceMotion {
            guard await sleep(seconds: SongNotificationMarquee.initialHold) else { return }

            if titleScroll.distance > 0 {
                withAnimation(.linear(duration: titleScroll.duration)) {
                    titleOffset = -titleScroll.distance
                }
            }
            if detailScroll.distance > 0 {
                withAnimation(.linear(duration: detailScroll.duration)) {
                    detailOffset = -detailScroll.distance
                }
            }

            guard await sleep(seconds: scrollDuration + SongNotificationMarquee.endingHold) else { return }
        } else {
            guard await sleep(seconds: 3.2) else { return }
        }

        isDismissing = true
        guard await sleep(for: dismissalEffect.completionDelay(reduceMotion: reduceMotion)) else { return }
        onFinished()
    }

    private func scrollMetrics(for contentWidth: CGFloat) -> SongNotificationMarqueeMetrics {
        SongNotificationMarquee.metrics(
            contentWidth: contentWidth,
            availableWidth: textAvailable
        )
    }

    private func sleep(milliseconds: Int) async -> Bool {
        do {
            try await Task.sleep(for: .milliseconds(milliseconds))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func sleep(seconds: Double) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(seconds))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func sleep(for duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}
