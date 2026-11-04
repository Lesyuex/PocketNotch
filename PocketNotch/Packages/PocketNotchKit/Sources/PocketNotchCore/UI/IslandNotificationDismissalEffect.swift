import Foundation
import Metal
import SwiftUI

public enum IslandNotificationDismissalEffect: String, CaseIterable, Identifiable, Sendable {
    case standard
    case particleDissolve = "fragmented"

    public var id: Self { self }

    public var title: String {
        switch self {
        case .standard:
            "标准"
        case .particleDissolve:
            "粒子消散"
        }
    }

    public func completionDelay(reduceMotion: Bool) -> Duration {
        guard !reduceMotion else { return .milliseconds(150) }
        switch self {
        case .standard:
            return .milliseconds(220)
        case .particleDissolve:
            return .milliseconds(1_760)
        }
    }
}

public extension View {
    func islandNotificationDismissalEffect(
        _ effect: IslandNotificationDismissalEffect = .standard,
        isDismissing: Bool
    ) -> some View {
        modifier(
            IslandNotificationDismissalModifier(
                effect: effect,
                isDismissing: isDismissing
            )
        )
    }
}

private struct IslandNotificationDismissalModifier: ViewModifier {
    let effect: IslandNotificationDismissalEffect
    let isDismissing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion || effect == .standard {
            content
                .opacity(isDismissing ? 0 : 1)
                .blur(radius: reduceMotion || !isDismissing ? 0 : 1.5)
                .scaleEffect(
                    reduceMotion || !isDismissing ? 1 : 0.985,
                    anchor: .top
                )
                .offset(y: reduceMotion || !isDismissing ? 0 : -4)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.14) : IslandNotificationDesign.removalAnimation,
                    value: isDismissing
                )
        } else {
            switch effect {
            case .standard:
                content
            case .particleDissolve:
                IslandNotificationParticleDissolve(
                    content: content,
                    isDismissing: isDismissing
                )
            }
        }
    }
}

enum ParticleDissolveMotion {
    static let duration: TimeInterval = 1.68
}

enum IslandNotificationParticleDustStyle {
    case content
    case backdrop

    var count: Int {
        switch self {
        case .content: 72
        case .backdrop: 64
        }
    }

    var lifetimeProgress: Double {
        switch self {
        case .content: 0.38
        case .backdrop: 0.30
        }
    }

    func onset(horizontalProgress: Double, noise: Double) -> Double {
        switch self {
        case .content:
            0.08 + (1 - horizontalProgress) * 0.44 + noise * 0.10
        case .backdrop:
            0.22 + (1 - horizontalProgress) * 0.44 + noise * 0.04
        }
    }

    var maximumOpacity: Double {
        switch self {
        case .content: 0.46
        case .backdrop: 0.22
        }
    }

    func size(noise: Double) -> Double {
        switch self {
        case .content:
            0.8 + pow(noise, 1.35) * 2.2
        case .backdrop:
            0.25 + pow(noise, 1.55) * 0.35
        }
    }

    var horizontalTravel: Double {
        switch self {
        case .content: 5
        case .backdrop: 3
        }
    }

    func verticalTravel(noise: Double) -> Double {
        switch self {
        case .content: 14 + noise * 18
        case .backdrop: 7 + noise * 10
        }
    }

    var scaleReduction: Double {
        switch self {
        case .content: 0.30
        case .backdrop: 0.20
        }
    }

    var earliestOnset: Double {
        switch self {
        case .content: 0.08
        case .backdrop: 0.22
        }
    }

    func isActive(at progress: Double) -> Bool {
        progress > earliestOnset && progress < 1
    }
}

enum IslandNotificationParticleMaskStyle {
    case content
    case backdrop

    var cellSize: CGFloat {
        switch self {
        case .content: 1.8
        case .backdrop: 1.1
        }
    }

    var cellOverlap: CGFloat {
        switch self {
        case .content: 0.24
        case .backdrop: 0.06
        }
    }

    var alphaBucketCount: Int {
        switch self {
        case .content: 8
        case .backdrop: 10
        }
    }

    var coarseCellSpan: Int {
        switch self {
        case .content: 3
        case .backdrop: 2
        }
    }

    var fineNoiseWeight: Double {
        switch self {
        case .content: 0.68
        case .backdrop: 0.72
        }
    }

    var initialThreshold: Double {
        switch self {
        case .content: 0.05
        case .backdrop: 0.20
        }
    }

    var frontTravel: Double { 0.48 }

    var noiseSpread: Double {
        switch self {
        case .content: 0.24
        case .backdrop: 0.12
        }
    }

    var fadeWidth: Double {
        switch self {
        case .content: 0.10
        case .backdrop: 0.14
        }
    }

    func dissolveThreshold(horizontalProgress: Double, noise: Double) -> Double {
        initialThreshold
            + (1 - horizontalProgress) * frontTravel
            + noise * noiseSpread
    }

    func remainingOpacity(
        progress: Double,
        horizontalProgress: Double,
        noise: Double
    ) -> Double {
        1 - smoothParticleStep(
            clampParticleProgress(
                (progress - dissolveThreshold(
                    horizontalProgress: horizontalProgress,
                    noise: noise
                ) + fadeWidth / 2) / fadeWidth
            )
        )
    }

    var earliestOnset: Double {
        max(
            dissolveThreshold(horizontalProgress: 1, noise: 0) - fadeWidth / 2,
            0
        )
    }

    func isActive(at progress: Double) -> Bool {
        progress > earliestOnset && progress < 1
    }
}

struct IslandNotificationParticleDissolve<Content: View>: View {
    let content: Content
    let isDismissing: Bool

    var body: some View {
        IslandNotificationEffectTimeline(
            isDismissing: isDismissing,
            duration: ParticleDissolveMotion.duration
        ) { progress in
            if let progress {
                IslandNotificationParticleDissolveFrame(
                    content: content,
                    progress: progress
                )
            } else {
                content
            }
        }
    }
}

struct IslandNotificationEffectTimeline<Content: View>: View {
    let isDismissing: Bool
    let duration: TimeInterval

    private let content: (Double?) -> Content
    @State private var startDate: Date?
    @State private var hasCompleted = false

    init(
        isDismissing: Bool,
        duration: TimeInterval,
        @ViewBuilder content: @escaping (Double?) -> Content
    ) {
        self.isDismissing = isDismissing
        self.duration = duration
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        Group {
            if hasCompleted {
                content(1)
            } else if let startDate {
                TimelineView(.animation) { timeline in
                    content(
                        clampParticleProgress(
                            timeline.date.timeIntervalSince(startDate)
                                / duration
                        )
                    )
                }
            } else {
                content(nil)
            }
        }
        .task(id: isDismissing) {
            guard isDismissing else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    startDate = nil
                    hasCompleted = false
                }
                return
            }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                startDate = Date()
                hasCompleted = false
            }

            do {
                try await Task.sleep(for: .seconds(duration))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withTransaction(transaction) {
                startDate = nil
                hasCompleted = true
            }
        }
    }
}

struct IslandNotificationParticleDissolveFrame<Content: View>: View {
    let content: Content
    let progress: Double
    var dustColor: Color = .secondary

    var body: some View {
        content
            .modifier(
                IslandNotificationParticleDissolveModifier(
                    progress: progress,
                    style: .content
                )
            )
            .overlay {
                if IslandNotificationParticleDustStyle.content.isActive(at: progress) {
                    IslandNotificationParticleDust(
                        progress: progress,
                        style: .content,
                        color: dustColor
                    )
                }
            }
    }
}

private enum ParticleDissolveRenderer {
    static let supportsShader = MTLCreateSystemDefaultDevice() != nil
}

struct IslandNotificationParticleDissolveModifier: ViewModifier {
    let progress: Double
    let style: IslandNotificationParticleMaskStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        if progress <= style.earliestOnset {
            content
        } else if progress >= 1 {
            content.opacity(0)
        } else if ParticleDissolveRenderer.supportsShader {
            content.mask {
                Color.white.visualEffect { effect, proxy in
                    effect.colorEffect(
                        ShaderLibrary.bundle(.module).haloParticleDissolve(
                            .float2(proxy.size),
                            .float(progress),
                            .float(style.cellSize),
                            .float(Double(style.coarseCellSpan)),
                            .float(style.fineNoiseWeight),
                            .float(style.initialThreshold),
                            .float(style.frontTravel),
                            .float(style.noiseSpread),
                            .float(style.fadeWidth)
                        )
                    )
                }
            }
        } else {
            content.mask {
                IslandNotificationParticleDissolveMask(
                    progress: progress,
                    style: style
                )
            }
        }
    }
}

struct IslandNotificationParticleDissolveMask: View {
    let progress: Double
    let style: IslandNotificationParticleMaskStyle

    var body: some View {
        if progress <= style.earliestOnset {
            Color.white
        } else if progress >= 1 {
            Color.clear
        } else {
            Canvas(rendersAsynchronously: false) { context, size in
                let cellSize = style.cellSize
                let cellOverlap = style.cellOverlap
                let alphaBucketCount = style.alphaBucketCount
                let columns = max(Int(ceil(size.width / cellSize)), 1)
                let rows = max(Int(ceil(size.height / cellSize)), 1)
                var alphaPaths = Array(repeating: Path(), count: alphaBucketCount)
                let coarseColumns = max(
                    Int(ceil(Double(columns) / Double(style.coarseCellSpan))),
                    1
                )

                for row in 0..<rows {
                    for column in 0..<columns {
                        let fineNoise = particleMaskNoise((row * columns + column) * 5 + 1)
                        let coarseRow = row / style.coarseCellSpan
                        let coarseColumn = column / style.coarseCellSpan
                        let coarseNoise = particleMaskNoise(
                            (coarseRow * coarseColumns + coarseColumn) * 7 + 3
                        )
                        let noise = fineNoise * style.fineNoiseWeight
                            + coarseNoise * (1 - style.fineNoiseWeight)
                        let horizontalProgress = (Double(column) + 0.5) / Double(columns)
                        let remainingOpacity = style.remainingOpacity(
                            progress: progress,
                            horizontalProgress: horizontalProgress,
                            noise: noise
                        )
                        guard remainingOpacity > 0.01 else { continue }

                        let bucket = min(
                            Int(remainingOpacity * Double(alphaBucketCount)),
                            alphaBucketCount - 1
                        )
                        alphaPaths[bucket].addRect(
                            CGRect(
                                x: CGFloat(column) * cellSize - cellOverlap / 2,
                                y: CGFloat(row) * cellSize - cellOverlap / 2,
                                width: cellSize + cellOverlap,
                                height: cellSize + cellOverlap
                            )
                        )
                    }
                }

                for bucket in alphaPaths.indices where !alphaPaths[bucket].isEmpty {
                    let opacity = Double(bucket + 1) / Double(alphaBucketCount)
                    context.fill(alphaPaths[bucket], with: .color(.white.opacity(opacity)))
                }
            }
        }
    }
}

struct IslandNotificationParticleDust: View {
    let progress: Double
    let style: IslandNotificationParticleDustStyle
    var color: Color = .white

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            for index in 0..<style.count {
                let xNoise = particleNoise(index * 7 + 1)
                let yNoise = particleNoise(index * 7 + 2)
                let onsetNoise = particleNoise(index * 7 + 3)
                let fallNoise = particleNoise(index * 7 + 4)
                let sizeNoise = particleNoise(index * 7 + 5)
                let horizontalProgress = xNoise
                let onset = style.onset(
                    horizontalProgress: horizontalProgress,
                    noise: onsetNoise
                )
                let localProgress = clampParticleProgress(
                    (progress - onset) / style.lifetimeProgress
                )
                guard localProgress > 0, localProgress < 1 else { continue }

                let movementProgress = smoothParticleStep(localProgress)
                let fadeIn = smoothParticleStep(clampParticleProgress(localProgress / 0.12))
                let fadeOut = smoothParticleStep(
                    clampParticleProgress((localProgress - 0.24) / 0.76)
                )
                let particleOpacity = fadeIn * (1 - fadeOut) * style.maximumOpacity
                let particleSize = style.size(noise: sizeNoise)
                let particleCenter = CGPoint(
                    x: horizontalProgress * size.width,
                    y: yNoise * size.height
                )
                let horizontalOffset = (onsetNoise - 0.5)
                    * style.horizontalTravel
                    * movementProgress
                let verticalOffset = pow(localProgress, 1.65)
                    * style.verticalTravel(noise: fallNoise)
                let scale = 1 - movementProgress * style.scaleReduction

                let renderedSize = particleSize * scale
                let renderedCenter = CGPoint(
                    x: particleCenter.x + horizontalOffset,
                    y: particleCenter.y + verticalOffset
                )
                let renderedRect = CGRect(
                    x: renderedCenter.x - renderedSize / 2,
                    y: renderedCenter.y - renderedSize / 2,
                    width: renderedSize,
                    height: renderedSize
                )
                context.fill(
                    Path(ellipseIn: renderedRect),
                    with: .color(color.opacity(particleOpacity))
                )
            }
        }
    }
}

private func particleNoise(_ seed: Int) -> Double {
    let value = sin(Double(seed) * 12.9898) * 43_758.5453
    return value - floor(value)
}

private func particleMaskNoise(_ seed: Int) -> Double {
    var value = UInt64(truncatingIfNeeded: seed)
    value &+= 0x9E37_79B9_7F4A_7C15
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    value ^= value >> 31
    return Double(value & 0x00FF_FFFF) / Double(0x0100_0000)
}

private func clampParticleProgress(_ value: Double) -> Double {
    min(max(value, 0), 1)
}

private func smoothParticleStep(_ value: Double) -> Double {
    value * value * (3 - 2 * value)
}
