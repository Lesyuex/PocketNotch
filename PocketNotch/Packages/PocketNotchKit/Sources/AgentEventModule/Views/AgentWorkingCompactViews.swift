import CoreGraphics
import PocketNotchCore
import ImageIO
import SwiftUI

private enum AgentWorkingCompactDesign {
    /// 首次通知完整信息阶段所需的最小 Island 宽度。
    static let fullDetailIslandWidth = CompactIslandTier.secondTierMinimumWidth
    static let statusIconFontSize: CGFloat = 14
    static let statusIconScale: CGFloat = 1.0
}

struct AgentWorkingLeadingView: View {
    @ObservedObject var presentationController: AgentWorkingPresentationController
    @ObservedObject var petController: AgentPetController
    @Environment(\.notchHiddenIslandSize) private var hiddenIslandSize
    @Environment(\.islandCompactContentSize) private var islandCompactContentSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var contentHeight: CGFloat {
        islandCompactContentSize?.height
            ?? CompactIslandContentSpec.resolvedContentHeight(for: hiddenIslandSize.height)
    }

    private var isVisible: Bool {
        presentationController.presentation != nil
    }

    private var selectedPet: PetDescriptor? {
        guard let agentID = presentationController.presentation?.agentID else { return nil }
        return petController.selectedPet(for: agentID)
    }

    var body: some View {
        Group {
            if isVisible {
                HStack(spacing: 4) {
                    Group {
                        if let presentation = presentationController.presentation,
                           let selectedPet {
                            PetSpriteView(
                                pet: selectedPet,
                                state: presentation.petState,
                                isPaused: reduceMotion
                            )
                        } else {
                            AgentFallbackIcon(
                                agentID: presentationController.presentation?.agentID ?? "unknown"
                            )
                        }
                    }
                    .frame(width: contentHeight * 0.88, height: contentHeight * 0.88)

                }
                .frame(height: contentHeight, alignment: .leading)
            } else {
                Color.clear
            }
        }
        .frame(height: contentHeight, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .compactIslandContentVisible(isVisible)
        .compactIslandPreferredWidth(
            presentationController.presentation?.isFullDetail == true
                ? AgentWorkingCompactDesign.fullDetailIslandWidth
                : nil
        )
        .compactIslandSuppressesResidentContent(isVisible)
        .animation(
            PocketNotchTheme.islandCompactModuleAnimation(
                isVisible: isVisible,
                reduceMotion: reduceMotion
            ),
            value: isVisible
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let presentation = presentationController.presentation else { return "" }
        return "\(presentation.agentDisplayName)\(presentation.statusText)"
    }
}

private struct AgentFallbackIcon: View {
    let agentID: String

    var body: some View {
        Image(systemName: symbolName)
            .resizable()
            .scaledToFit()
            .foregroundStyle(tint)
            .padding(4)
    }

    private var symbolName: String {
        switch agentID {
        case "claude": "brain.head.profile"
        case "gemini": "sparkles"
        default: "terminal.fill"
        }
    }

    private var tint: Color {
        switch agentID {
        case "claude": Color.orange.opacity(0.92)
        case "gemini": Color.cyan.opacity(0.92)
        default: Color.white.opacity(0.92)
        }
    }
}

struct AgentWorkingTrailingView: View {
    @ObservedObject var presentationController: AgentWorkingPresentationController
    @Environment(\.notchHiddenIslandSize) private var hiddenIslandSize
    @Environment(\.islandCompactContentSize) private var islandCompactContentSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var contentHeight: CGFloat {
        islandCompactContentSize?.height
            ?? CompactIslandContentSpec.resolvedContentHeight(for: hiddenIslandSize.height)
    }

    private var isVisible: Bool {
        presentationController.presentation != nil
    }

    var body: some View {
        Group {
            if isVisible {
                if presentationController.presentation?.isFullDetail == true {
                    HStack(spacing: 6) {
                        Text(promptText)
                            .font(.system(
                                size: PocketNotchTheme.islandCompactFontSize,
                                weight: .semibold,
                                design: .rounded
                            ))
                            .foregroundStyle(statusColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: false)

                        if presentationController.presentation?.petState == .jumping {
                            AgentCompletedIndicator()
                                .frame(width: contentHeight * 0.9, height: contentHeight * 0.9)
                        }
                    }
                    .frame(height: contentHeight, alignment: .trailing)
                } else {
                    rightEarIcon
                        .frame(width: contentHeight * 0.9, height: contentHeight * 0.9)
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .animation(
            PocketNotchTheme.islandCompactModuleAnimation(
                isVisible: isVisible,
                reduceMotion: reduceMotion
            ),
            value: isVisible
        )
        .animation(
            PocketNotchTheme.islandCompactModuleAnimation(
                isVisible: isVisible,
                reduceMotion: reduceMotion
            ),
            value: presentationController.presentation?.isFullDetail
        )
        .accessibilityHidden(true)
    }

    private var promptText: String {
        guard let presentation = presentationController.presentation else { return "" }
        let prompt = presentation.prompt?
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let prompt, !prompt.isEmpty {
            return prompt
        }
        return presentation.statusText
    }

    /// 文字版右侧提示词颜色固定为白色。
    private var statusColor: Color {
        return .white.opacity(0.92)
    }

    @ViewBuilder
    private var rightEarIcon: some View {
        if presentationController.presentation?.petState == .waiting {
            AgentWaitingIndicator(isPaused: reduceMotion)
        } else {
            AgentRunningIndicator(isPaused: reduceMotion)
        }
    }
}

private struct AgentCompletedIndicator: View {
    var body: some View {
        Image(systemName: "checkmark.bubble")
            .font(.system(size: AgentWorkingCompactDesign.statusIconFontSize, weight: .semibold))
            .foregroundStyle(.green.opacity(0.96))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
           // .scaleEffect(AgentWorkingCompactDesign.statusIconScale)
            .accessibilityLabel("已完成")
    }
}

private struct AgentWaitingIndicator: View {
    let isPaused: Bool

    var body: some View {
        Image(systemName: "questionmark.bubble")
            .font(.system(size: AgentWorkingCompactDesign.statusIconFontSize, weight: .semibold))
            .foregroundStyle(.orange.opacity(0.96))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .haloSymbolEffect(
                .shake,
                isActive: !isPaused,
                reduceMotion: isPaused
            )
            //.scaleEffect(AgentWorkingCompactDesign.statusIconScale)
            .accessibilityLabel("等待授权")
    }
}

private struct AgentRunningIndicator: View {
    let isPaused: Bool

    @State private var rotationDegrees = 0.0
    @State private var scale = 1.0

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: AgentWorkingCompactDesign.statusIconFontSize, weight: .semibold))
            .foregroundStyle(.white.opacity(0.78))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotationDegrees))
            .task(id: isPaused) {
                if isPaused {
                    scale = 1
                } else {
                    await runCumulativeJellyAnimation()
                }
            }
            .accessibilityLabel("正在执行命令")
    }

    private var symbolName: String {
        if #available(macOS 15.0, *) {
            return "apple.intelligence"
        }
        return "sparkles"
    }

    @MainActor
    private func runCumulativeJellyAnimation() async {
        while !Task.isCancelled {
            withAnimation(.easeOut(duration: 0.12)) {
                scale = 0.88
            }
            guard await wait(nanoseconds: 120_000_000) else { return }

            withAnimation(.spring(response: 0.88, dampingFraction: 0.58)) {
                rotationDegrees += 24
                scale = 0.98
            }
            guard await wait(nanoseconds: 888_000_000) else { return }

            withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                scale = 1
            }
            guard await wait(nanoseconds: 520_000_000) else { return }
        }
    }

    private func wait(nanoseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: nanoseconds)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

private struct AnimatedWebPFrame {
    let image: CGImage
    let duration: TimeInterval
}

private struct AnimatedWebPAsset {
    let frames: [AnimatedWebPFrame]
    let duration: TimeInterval
    let refreshInterval: TimeInterval

    static func load(from url: URL?) -> AnimatedWebPAsset? {
        guard let url,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let frames: [AnimatedWebPFrame] = (0..<CGImageSourceGetCount(source)).compactMap { index in
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                return nil
            }
            return AnimatedWebPFrame(
                image: image,
                duration: frameDuration(source: source, index: index)
            )
        }
        guard !frames.isEmpty else { return nil }

        return AnimatedWebPAsset(
            frames: frames,
            duration: frames.reduce(0) { $0 + $1.duration },
            refreshInterval: frames.map { $0.duration }.min() ?? 0.1
        )
    }

    func frame(at elapsed: TimeInterval) -> AnimatedWebPFrame {
        let phase = max(elapsed, 0).truncatingRemainder(dividingBy: duration)
        var boundary: TimeInterval = 0
        for frame in frames {
            boundary += frame.duration
            if phase < boundary { return frame }
        }
        return frames[frames.count - 1]
    }

    private static func frameDuration(
        source: CGImageSource,
        index: Int
    ) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
            as? [CFString: Any] else {
            return 0.1
        }

        // WebP 动画：delay 单位为秒。
        if let webP = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
            let unclamped = webP[kCGImagePropertyWebPUnclampedDelayTime] as? TimeInterval
            let clamped = webP[kCGImagePropertyWebPDelayTime] as? TimeInterval
            return max(unclamped ?? clamped ?? 0.1, 0.02)
        }

        // GIF 动画：delay 单位为百分之一秒（centiseconds）。
        if let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
            let clamped = gif[kCGImagePropertyGIFDelayTime] as? TimeInterval
            let delay = unclamped ?? clamped ?? 0.04
            return max(delay / 100.0, 0.02)
        }

        return 0.1
    }
}

private struct AnimatedWebPView: View {
    let asset: AnimatedWebPAsset?
    let isPaused: Bool
    @State private var animationStart = Date.now

    var body: some View {
        Group {
            if let asset {
                if isPaused {
                    frameImage(asset.frames[0])
                } else {
                    TimelineView(.periodic(
                        from: animationStart,
                        by: asset.refreshInterval
                    )) { timeline in
                        frameImage(asset.frame(
                            at: timeline.date.timeIntervalSince(animationStart)
                        ))
                    }
                }
            } else {
                Image(systemName: "terminal.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(4)
            }
        }
        .onAppear {
            animationStart = .now
        }
    }

    private func frameImage(_ frame: AnimatedWebPFrame) -> some View {
        Image(decorative: frame.image, scale: 1)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
    }
}
