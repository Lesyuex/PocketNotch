import CoreGraphics
import ImageIO
import SwiftUI

struct PetAnimationFrames: @unchecked Sendable {
    let images: [CGImage]
    let durations: [TimeInterval]

    var count: Int { images.count }

    func frame(elapsed: TimeInterval) -> CGImage? {
        guard !images.isEmpty, images.count == durations.count else { return nil }
        let totalDuration = durations.reduce(0, +)
        guard totalDuration > 0 else { return images.first }
        let phase = max(elapsed, 0).truncatingRemainder(dividingBy: totalDuration)
        var boundary: TimeInterval = 0
        for index in durations.indices {
            boundary += durations[index]
            if phase < boundary { return images[index] }
        }
        return images.last
    }
}

struct PetAtlasAsset: @unchecked Sendable {
    /// 灵动岛中的宠物通常只有约 24pt；保留 2x/3x 的清晰度即可。
    private static let maxFramePixelSize = 96

    let framesByState: [PetAnimationState: PetAnimationFrames]

    var memoryCost: Int {
        framesByState.values
            .flatMap(\.images)
            .reduce(0) { $0 + $1.bytesPerRow * $1.height }
    }

    static func load(from url: URL) -> PetAtlasAsset? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil),
              atlas.width == Int(PetLibrary.atlasSize.width),
              atlas.height == Int(PetLibrary.atlasSize.height) else {
            return nil
        }

        var framesByState: [PetAnimationState: PetAnimationFrames] = [:]
        for state in PetAnimationState.allCases {
            let images: [CGImage] = state.frameDurations.indices.compactMap { column -> CGImage? in
                guard let cropped = atlas.cropping(to: CGRect(
                    x: CGFloat(column) * PetLibrary.cellSize.width,
                    y: CGFloat(state.row) * PetLibrary.cellSize.height,
                    width: PetLibrary.cellSize.width,
                    height: PetLibrary.cellSize.height
                )) else { return nil }
                return downsample(cropped)
            }
            guard images.count == state.frameDurations.count else { return nil }
            framesByState[state] = PetAnimationFrames(
                images: images,
                durations: state.frameDurations
            )
        }
        return PetAtlasAsset(framesByState: framesByState)
    }

    /// 将资源帧与灵动岛实际显示尺寸匹配，避免每帧渲染时携带整张大图的 backing store。
    private static func downsample(_ image: CGImage) -> CGImage? {
        let longestSide = max(image.width, image.height)
        guard longestSide > maxFramePixelSize else { return image }

        let scale = CGFloat(maxFramePixelSize) / CGFloat(longestSide)
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    static func load(from pet: PetDescriptor) -> PetAtlasAsset? {
        if let spritesheetURL = pet.spritesheetURL {
            return load(from: spritesheetURL)
        }

        var framesByState: [PetAnimationState: PetAnimationFrames] = [:]
        for state in PetAnimationState.allCases {
            guard let url = pet.stateAnimationURLs[state],
                  let frames = loadAnimatedImage(from: url) else {
                return nil
            }
            framesByState[state] = frames
        }
        return PetAtlasAsset(framesByState: framesByState)
    }

    func frame(for state: PetAnimationState, elapsed: TimeInterval) -> CGImage? {
        framesByState[state]?.frame(elapsed: elapsed)
    }

    private static func loadAnimatedImage(from url: URL) -> PetAnimationFrames? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var images: [CGImage] = []
        var durations: [TimeInterval] = []
        images.reserveCapacity(count)
        durations.reserveCapacity(count)
        for index in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
            guard let image = downsample(image) else { return nil }
            images.append(image)
            durations.append(frameDuration(source: source, index: index))
        }
        return PetAnimationFrames(images: images, durations: durations)
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any]
        else { return 0.1 }

        let delay = properties.values.lazy.compactMap { value -> TimeInterval? in
            guard let dictionary = value as? [String: Any] else { return nil }
            let preferred = dictionary.first { key, _ in
                key.localizedCaseInsensitiveContains("UnclampedDelayTime")
            }?.value
            let fallback = dictionary.first { key, _ in
                key.localizedCaseInsensitiveContains("DelayTime")
            }?.value
            return (preferred as? NSNumber)?.doubleValue ?? (fallback as? NSNumber)?.doubleValue
        }.first
        return max(delay ?? 0.1, 0.02)
    }
}

private final class PetAtlasBox {
    let asset: PetAtlasAsset

    init(_ asset: PetAtlasAsset) {
        self.asset = asset
    }
}

private enum PetAtlasCache {
    static let cache: NSCache<NSURL, PetAtlasBox> = {
        let cache = NSCache<NSURL, PetAtlasBox>()
        // Keep recently used pets available across consecutive Agent events.
        cache.countLimit = 4
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    static func asset(for pet: PetDescriptor) -> PetAtlasAsset? {
        let key = NSURL(fileURLWithPath: pet.assetCacheKey)
        if let cached = cache.object(forKey: key) {
            return cached.asset
        }
        guard !Task.isCancelled else { return nil }
        guard let asset = PetAtlasAsset.load(from: pet) else { return nil }
        guard !Task.isCancelled else { return nil }
        cache.setObject(PetAtlasBox(asset), forKey: key, cost: asset.memoryCost)
        return asset
    }

    static func cachedAsset(for pet: PetDescriptor) -> PetAtlasAsset? {
        cache.object(forKey: NSURL(fileURLWithPath: pet.assetCacheKey))?.asset
    }

    static func removeAllAssets() {
        cache.removeAllObjects()
    }
}

struct PetSpriteView: View {
    let pet: PetDescriptor
    let state: PetAnimationState
    let isPaused: Bool
    let showsFallback: Bool

    init(
        pet: PetDescriptor,
        state: PetAnimationState,
        isPaused: Bool,
        showsFallback: Bool = true
    ) {
        self.pet = pet
        self.state = state
        self.isPaused = isPaused
        self.showsFallback = showsFallback
        _asset = State(initialValue: PetAtlasCache.cachedAsset(for: pet))
    }

    /// Agent 事件到达后准备图集；调用方等待完成后才提交整条临时展示。
    static func prepareForPresentation(pet: PetDescriptor) async -> Bool {
        await Task.detached(priority: .utility) {
            PetAtlasCache.asset(for: pet)
        }.value != nil
    }

    static func isPreparedForPresentation(pet: PetDescriptor) -> Bool {
        PetAtlasCache.cachedAsset(for: pet) != nil
    }

    @State private var animationStart = Date.now
    @State private var asset: PetAtlasAsset?

    var body: some View {
        Group {
            if let asset {
                if isPaused {
                    frameImage(asset.framesByState[state]?.images.first)
                } else {
                    TimelineView(.periodic(from: animationStart, by: refreshInterval)) { timeline in
                        frameImage(asset.frame(
                            for: state,
                            elapsed: timeline.date.timeIntervalSince(animationStart)
                        ))
                    }
                }
            } else {
                placeholder
            }
        }
        .onAppear { animationStart = .now }
        .onDisappear { asset = nil }
        .onChange(of: state) { _, _ in animationStart = .now }
        .task(id: pet.assetCacheKey) {
            guard asset == nil else { return }
            let pet = pet
            let loadTask = Task.detached {
                PetAtlasCache.asset(for: pet)
            }
            let loadedAsset = await withTaskCancellationHandler {
                await loadTask.value
            } onCancel: {
                loadTask.cancel()
            }
            guard !Task.isCancelled else { return }
            asset = loadedAsset
            animationStart = .now
        }
        .accessibilityHidden(true)
    }

    private var refreshInterval: TimeInterval {
        asset?.framesByState[state]?.durations.min() ?? 0.12
    }

    @ViewBuilder
    private func frameImage(_ image: CGImage?) -> some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            placeholder
        }
    }

    private var fallback: some View {
        Image(systemName: "sparkles")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white.opacity(0.92))
            .padding(4)
    }

    @ViewBuilder
    private var placeholder: some View {
        if showsFallback {
            fallback
        } else {
            Color.clear
        }
    }
}

public struct PetPreviewView: View {
    private let pet: PetDescriptor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(pet: PetDescriptor) {
        self.pet = pet
    }

    public static func releaseCachedResources() {
        PetAtlasCache.removeAllAssets()
    }

    public var body: some View {
        PetSpriteView(
            pet: pet,
            state: .idle,
            isPaused: reduceMotion
        )
        .id(pet.id)
    }
}
