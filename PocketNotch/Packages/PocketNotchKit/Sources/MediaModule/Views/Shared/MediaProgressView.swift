import SwiftUI

struct MediaProgressView: View {
    let info: NowPlayingInfo
    var showsTimeLabels = false

    var body: some View {
        if info.isPlaying, let baseline = Self.baseline(from: info) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                progressContent(Self.progress(at: context.date, from: info, baseline: baseline))
            }
        } else {
            progressContent(Self.baseline(from: info))
        }
    }

    @ViewBuilder
    private func progressContent(_ progress: (elapsed: TimeInterval, duration: TimeInterval)?) -> some View {
        if let progress {
            VStack(spacing: showsTimeLabels ? 5 : 0) {
                ProgressView(value: progress.elapsed, total: progress.duration)
                    .tint(.white)
                    .controlSize(.small)

                if showsTimeLabels {
                    HStack {
                        Text(timeText(progress.elapsed))
                        Spacer()
                        Text(timeText(progress.duration))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                }
            }
        }
    }

    private static func progress(at date: Date, from info: NowPlayingInfo, baseline: (elapsed: TimeInterval, duration: TimeInterval)) -> (elapsed: TimeInterval, duration: TimeInterval)? {
        let elapsed = baseline.elapsed + date.timeIntervalSince(info.updatedAt)
        return (clamp(elapsed, to: baseline.duration), baseline.duration)
    }

    private static func baseline(from info: NowPlayingInfo) -> (elapsed: TimeInterval, duration: TimeInterval)? {
        guard let elapsedTime = info.elapsedTime,
              let duration = info.duration,
              duration > 0 else {
            return nil
        }
        return (clamp(elapsedTime, to: duration), duration)
    }

    private static func clamp(_ elapsed: TimeInterval, to duration: TimeInterval) -> TimeInterval {
        max(0, min(elapsed, duration))
    }

    private func timeText(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}