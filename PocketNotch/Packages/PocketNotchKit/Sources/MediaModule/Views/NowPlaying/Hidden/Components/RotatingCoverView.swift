import AppKit
import CoreImage
import PocketNotchShared
import QuartzCore
import SwiftUI

/// Core Animation 常驻驱动的封面旋转层：
/// - 旋转不再依赖 AnimationScheduler 的逐帧提交，直接交给 render server 跑连续循环动画。
/// - 暂停时冻结当前 presentation 值，恢复时从当前相位继续，resetToken 变化时归零。
/// - 旋转施加在「自建、自持几何」的变换子图层上：锚点/位置只设置一次，AppKit 永不重建它，
///   因此圆心永远钉在内容正中间，尺寸/耳高变化不会再带偏旋转中心。
struct RotatingCoverView: NSViewRepresentable {
    let content: AnyView
    let isRotating: Bool
    let resetToken: String
    /// 歌曲不变的关键字（标题+歌手），与 resetToken 解耦：旋转开关只改 resetToken、
    /// 不改它 → 封面缩放这类纯样式变化不该触发翻转/磨砂过渡。
    var songKey: String = ""
    var rotationDuration: Double = 8
    /// 3D 翻转切歌过渡开关；减弱动态时置 false 退化为纯淡入淡出。
    var isFlipTransitionEnabled: Bool = true
    /// 当前内容是否为 App 图标兜底（非真实封面）；兜底过渡退化为淡入淡出。
    var isFallbackArtwork: Bool = false
    /// 旋转模式（设置中心开关）是否开启：旋转经验下切歌一律直接换图、不翻面。
    /// 必须是「用户意图」这种稳定值，不能取瞬态 isRotationActive —— 切歌瞬间
    /// isPlaying / artwork 会短暂为 false，按瞬态判断会在旋转模式里冒出翻转。
    var isRotationEnabledForChanges: Bool = false

    func makeNSView(context: Context) -> RotatingCoverHostView {
        let view = RotatingCoverHostView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: RotatingCoverHostView, context: Context) {
        view.isFallbackArtwork = isFallbackArtwork
        view.isFlipTransitionEnabled = isFlipTransitionEnabled
        view.isRotationEnabledForChanges = isRotationEnabledForChanges
        view.songKey = songKey
        view.setContent(content)
        view.apply(isRotating: isRotating, resetToken: resetToken, rotationDuration: rotationDuration)
    }

    static func dismantleNSView(_ view: RotatingCoverHostView, coordinator: Void) {
        view.teardown()
    }
}

final class RotatingCoverHostView: NSView {
    private static let rotationAnimationKey = "pocketnotch.cover.rotation"
    private static let flipAnimationKey = "pocketnotch.cover.flip"
    private static let unblurAnimationKey = "pocketnotch.cover.unblur"
    private static let fadeOutAnimationKey = "pocketnotch.crossfade.out"
    private static let rezeroAnimationKey = "pocketnotch.cover.rezero"

        /// 背面模糊：CoreImage 预生成的玻璃质感模糊位图（渲染零风险，不依赖 CAFilter 的
        /// 滤镜参数动画/滤镜与遮罩的组合行为）。半分辨率做高斯模糊（模糊图无细节，
        /// 放大显示等价且省时），再压饱和、加白色冰雾，呈现「砂糖玻璃」的哑光朦胧。
        private enum FlipTransitionDesign {
            /// 翻面时长。低于 ~0.2s 会读成「闪一下」而不是翻面，高于 ~0.4s
            /// 又拖慢切歌反馈；0.3s 是能看清 3D 过程又不觉得等的中间值。
            static let flipDuration: Double = 0.3
            /// 落定后「模糊 → 清晰」的揭示时长（模糊层透明度渐隐）。
            static let unblurDuration: Double = 0.2
            /// 旋转模式切歌后「回 0°」的归零时长：与玻璃揭示同频，落定即续转。
            static let rezeroDuration: Double = 0.2
            /// 减弱动态下的纯淡入淡出时长（不翻面时的替代表现）。
            static let plainFadeDuration: Double = 0.16
            /// 透视相机距离 = 封面宽度的倍数。必须相对尺寸取值并取小值：
            /// m34 是绝对量，24pt 的耳位用常规卡片距离（如 1/500）时透视压缩不到 5%，
            /// rotateY 会退化成「水平压扁」完全读不出 3D。
            static let perspectiveDistanceRatio: CGFloat = 1.5
            static let minimumPerspectiveDistance: CGFloat = 30
            /// 背面模糊半径 = 半分辨率图宽度的比例。与镜像垫边内联：模糊核在边界
            /// 取到的是卡片自身反射的内容，整卡均匀模糊、每处透出的都是封面
            /// 透过来的颜色（左边红就透红、右边蓝就透蓝），不会糊成一张均值卡。
            static let backFaceBlurFraction: CGFloat = 0.2
            /// 玻璃哑光：轻微降饱和，只磨掉锐利感、保留封面色相。
            static let frostSaturation: CGFloat = 0.8
            /// 玻璃光泽：「渐变晕染」的柔和径向提亮强度（0=关闭）。
            /// 光晕用封面色调染成（见 addGloss：以封面不透明像素平均色做色相），
            /// 中心略偏上、向外渐隐，给背板一点「玻璃在光里」的呼吸感而无白色——
            /// 不发白的前提就是光晕色 = 封面透过来的颜色。
            static let frostBloom: CGFloat = 0.2
        }

    private static let blurContext = CIContext()

    /// 生成背面用的磨砂封面：高斯朦胧 → 轻微降饱和 → 柔和径向光晕。
    /// 雾色完全来自封面透过来的颜色，不加任何白色冰雾；光晕只是玻璃质感。
    ///
    /// 防止「只糊中间 / 边缘带色」：直接对卡片图做高斯时，模糊核碰到卡片
    /// 边界被 clampedToExtent 无限复制边界像素 → 边缘往自身颜色收、中心才
    /// 收敛到均值。这里把半分辨率封面沿四条边「镜像反射」垫成大画布再模糊，
    /// 裁回卡片范围：边缘像素取到的是卡片自己的反射，整卡均匀、随位置透出
    /// 对应区域的封面颜色。
    private static func blurredImage(from image: CGImage) -> CGImage? {
        let halfW = max(1, image.width / 2)
        let halfH = max(1, image.height / 2)
        let radius = max(
            CGFloat(2),
            CGFloat(halfW) * FlipTransitionDesign.backFaceBlurFraction
        )
        let margin = Int(radius.rounded(.up))

        guard let half = drawScaled(image, toWidth: halfW, height: halfH) else { return nil }
        let canvasW = halfW + margin * 2
        let canvasH = halfH + margin * 2
        guard let padded = drawReflectedPadding(half, width: halfW, height: halfH, margin: margin, canvasW: canvasW, canvasH: canvasH) else { return nil }

        let full = CGRect(x: 0, y: 0, width: canvasW, height: canvasH)
        let inner = CGRect(x: margin, y: margin, width: halfW, height: halfH)
        let input = CIImage(cgImage: padded).clampedToExtent()
        guard let gaussian = CIFilter(name: "CIGaussianBlur") else { return nil }
        gaussian.setValue(input, forKey: kCIInputImageKey)
        gaussian.setValue(radius, forKey: kCIInputRadiusKey)
        let blurred = gaussian.outputImage?.cropped(to: full)

        guard let controls = CIFilter(name: "CIColorControls"), let blurred else { return nil }
        controls.setValue(blurred, forKey: kCIInputImageKey)
        controls.setValue(FlipTransitionDesign.frostSaturation, forKey: kCIInputSaturationKey)
        guard let frosted = controls.outputImage?.cropped(to: inner) else { return nil }
        guard let frostedCG = blurContext.createCGImage(frosted, from: inner) else { return nil }

        // 玻璃光泽：「渐变晕染」的柔和径向白高光，加性混合在磨砂位图上
        // （中心微亮、向外渐隐）。比 CIAdditionCompositing 更可控 ——
        // CI 的 alpha 插值会被色彩空间折算，实测强度近零。
        return addGloss(to: frostedCG, width: halfW, height: halfH)
    }

    /// 在白→透明（实际用封面色调）的径向渐变上，以 plusLighter 把玻璃光泽叠进
    /// 磨砂位图。光心略偏上，模拟「玻璃在光里」的柔和晕染；光晕色 = 封面
    /// 不透明像素平均色（色相来自封面，才能不发白）；强度旋钮 frostBloom（0 关闭）。
    private static func addGloss(to frosted: CGImage, width: Int, height: Int) -> CGImage? {
        guard let ctx = makeContext(width: width, height: height) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(frosted, in: CGRect(x: 0, y: 0, width: width, height: height))

        let glow = averageOpaqueColor(of: frosted)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(
                  colorsSpace: space,
                  colors: [
                      CGColor(red: glow.r, green: glow.g, blue: glow.b, alpha: FlipTransitionDesign.frostBloom),
                      CGColor(red: glow.r, green: glow.g, blue: glow.b, alpha: 0),
                  ] as CFArray,
                  locations: [0, 1]
              ) else { return nil }
        // 翻转画布下 y=0.46h ≈ 最终图像中心偏上 8% 处。
        let center = CGPoint(x: CGFloat(width) * 0.5, y: CGFloat(height) * 0.46)
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 2,
            endCenter: center,
            endRadius: CGFloat(min(width, height)) * 0.8,
            options: [.drawsBeforeStartLocation]
        )
        ctx.restoreGState()
        return ctx.makeImage()
    }

    /// 半分辨率重绘制封面（CGContext 位屏，沿用 premultiplied RGBA）。
    private static func drawScaled(_ image: CGImage, toWidth width: Int, height: Int) -> CGImage? {
        guard let ctx = makeContext(width: width, height: height) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// 把半分辨率封面沿边 3×3 镜像平铺成画布：边缘外是卡片自身的反射内容，
    /// 模糊核无需复制边界即可跨出卡片 → 整卡均匀、无边缘伪影。
    private static func drawReflectedPadding(
        _ half: CGImage,
        width: Int,
        height: Int,
        margin: Int,
        canvasW: Int,
        canvasH: Int
    ) -> CGImage? {
        guard let ctx = makeContext(width: canvasW, height: canvasH) else { return nil }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
        ctx.translateBy(x: 0, y: CGFloat(canvasH))
        ctx.scaleBy(x: 1, y: -1)
        for dx in -1...1 {
            for dy in -1...1 {
                let rect = CGRect(
                    x: margin + dx * width,
                    y: margin + dy * height,
                    width: width,
                    height: height
                )
                ctx.saveGState()
                ctx.translateBy(x: rect.midX, y: rect.midY)
                ctx.scaleBy(x: dx == 0 ? 1 : -1, y: dy == 0 ? 1 : -1)
                ctx.translateBy(x: -rect.midX, y: -rect.midY)
                ctx.draw(half, in: rect)
                ctx.restoreGState()
            }
        }
        return ctx.makeImage()
    }

    /// 封面内不透明像素的平均色（premultiplied RGBA 转 0..1）。光晕取它的色相，
    /// 让玻璃光泽「像封面透过来的光」而不是白色。
    private static func averageOpaqueColor(of image: CGImage) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        guard let data = image.dataProvider?.data as Data? else { return (0.7, 0.7, 0.7) }
        let rowBytes = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8
        guard bpp >= 4, rowBytes > 0, image.width > 0, image.height > 0 else { return (0.7, 0.7, 0.7) }
        var sumR = 0.0, sumG = 0.0, sumB = 0.0, count = 0.0
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * rowBytes + x * bpp
                guard offset + 3 < data.count else { continue }
                let a = data[offset + 3]
                guard a > 16 else { continue }
                sumR += Double(data[offset])
                sumG += Double(data[offset + 1])
                sumB += Double(data[offset + 2])
                count += 1
            }
        }
        guard count > 0 else { return (0.7, 0.7, 0.7) }
        return (CGFloat(sumR / count / 255), CGFloat(sumG / count / 255), CGFloat(sumB / count / 255))
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// 自建变换子图层：AppKit 完全不管它的 geometry，旋转不会因 View 重建而漂移圆心。
    private var transformLayer: CALayer?
    private var content: AnyView?
    private var configuredBounds: CGRect = .zero
    /// 已渲染内容的像素尺寸（按整数 pt 分桶，动画过程中尺寸微变只缩放不重绘）。
    private var renderedContentSize: CGSize = .zero
    /// 切歌过渡时的旧封面图层（仅减弱动态淡出路径使用）。
    private var crossfadeLayer: CALayer?
    /// 翻转后半程覆盖在清晰新封面上的模糊图层（alpha 轮廓遮罩，揭示时渐隐）。
    private var blurLayer: CALayer?
    /// 是否在切歌过渡中（期间暂停旋转，避免新旧封面相位错乱）。
    private(set) var isCrossfading = false
    /// 当前显示帧所属的歌曲：切歌后「等封面」期间画面还是上一张，
    /// 显示内容与当前歌曲不一致时，封面到达必须补一次完整过渡。
    private var contentsSongKey: String?
    /// App 图标落定的时刻：真封面迟到多久之后就不再翻面，改为按压式替换。
    /// 当前过渡是否为旋转模式的纯淡入淡出（非 3D 翻转）。纯淡入淡出只叠
    /// 一个老封面子层、不触碰变换，常驻旋转可以放心并行跑，不能被杀停下。
    private var isPlainFade = false
    var isFlipTransitionEnabled = true
    /// 最新内容是否为 App 图标兜底（非真实封面）。兜底状态参与的过渡不走 3D 翻转。
    var isFallbackArtwork = false
    /// 旋转模式（设置中心开关）是否开启（稳定用户意图，非瞬态旋转态）。
    var isRotationEnabledForChanges = false
    /// 当前歌曲不变的关键字（标题+歌手）。
    var songKey = ""
    /// 已应用内容的歌曲关键字：换歌才允许翻转/磨砂过渡。
    private var storedSongKey = ""
    /// 当前已应用内容是否为 App 图标兜底。
    private var appliedFallbackArtwork = false

    private var storedResetToken: String?
    private var isAnimating = false
    private var rotationDuration: Double = 8
    /// 旋转模式切歌后正在「回 0°」的归零动画期间（期间禁插新的常驻旋转动画）。
    private var isRezeroing = false

    override var isFlipped: Bool { true }

    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? 2
    }

    // MARK: 内容渲染

    func setContent(_ content: AnyView) {
        self.content = content
        guard let transformLayer else { return }
        // 翻转进行中只记录最新内容：中途换图会破坏翻转，且平铺底图会从卡片
        // 透明区透出。落定后（runUnblurReveal 完成块）会补一次 setContent 同步。
        guard !isCrossfading else { return }

        // 渲染新帧并与当前显示帧对比：仅当封面「实际变化」时做过渡；
        // 若内容未变（暂停/播放这类不改变封面图的事件），保持现状、不重新渲染 → 不抖动。
        guard let newImage = renderImage(content, size: currentBucket, scale: backingScale) else { return }
        let fallbackTransition = isFallbackArtwork != appliedFallbackArtwork
        let songChanged = songKey != storedSongKey
        // 切歌后等封面期间 songKey 已是新歌、画面还是上一张：封面到达时
        // songChanged 已为 false，靠「显示内容属于别的歌」判定该补一次过渡。
        let contentsFromOtherSong = contentsSongKey.map { $0 != songKey } ?? false

        if transformLayer.contents == nil {
            applyRasterImage(newImage)
            contentsSongKey = songKey
        } else if !RotatingCoverHostView.imagesEqual(
            transformLayer.contents as! CGImage,
            newImage
        ) {
            if songChanged || fallbackTransition || contentsFromOtherSong {
                // 过渡（翻转/磨砂）只在「换歌」「等封面期间画面还是上一首」
                // 或「兜底 ↔ 真封面」时发生。开/关旋转只是封面缩放（songKey 不变）
                // ——纯样式变化，原位换图即可，否则关旋转会在 styleScale
                // 变化引起的重绘里误翻一面。
                applySongChangeTransition(to: newImage)
            } else {
                applyRasterImage(newImage)
            }
            contentsSongKey = songKey
        }
        storedSongKey = songKey
        appliedFallbackArtwork = isFallbackArtwork
    }

    /// 换歌过渡：按「旋转模式 / 常规 / 减弱动态」选一种表现。
    /// 「真封面 ↔ App 图标兜底」同样走这套 —— 切歌时图标先顶上、真封面到了再翻一次，
    /// 两次都是同一套动作，视觉语言一致（iOS 的做法）。
    private func applySongChangeTransition(to newImage: CGImage) {
        guard let transformLayer else { return }
        // 3D 翻转只用于非旋转场景；旋转模式（设置中心开关开启）切歌不翻转：
        // 自转已承担「变化感」，转而由 apply 统一回 0° 再做玻璃揭示（见 rezeroRotation）。
        // 判定用稳定意图值而非 isAnimating：切歌瞬间 isPlaying / artwork 短暂
        // 为 false 会让瞬态旋转态归零，按瞬态判断会在旋转模式里冒出翻转。
        if isRotationEnabledForChanges {
            // 旋转模式切歌：不做 3D 翻转（自转已承担「变化感」、翻转反而打断旋转、
            // 落定后从 0° 重起），但保留玻璃质感 —— 新封面以磨砂形态接替旧封面，
            // 磨砂镜片随后渐渐退散、真封面原地显现。旋转全程不停。
            glassFade(from: transformLayer.contents as! CGImage, to: newImage, bounds: transformLayer.bounds)
        } else if isFlipTransitionEnabled {
            // 非旋转场景（暂停 / 设置关 / 减弱动态）：180° 翻转 + 磨砂揭示。
            crossfade(from: transformLayer.contents as! CGImage, to: newImage)
        } else {
            // 减弱动态：普通淡入淡出。
            fadeTransition(from: transformLayer.contents as! CGImage, to: newImage, bounds: transformLayer.bounds)
        }
    }

    private var currentBucket: CGSize {
        CGSize(width: max(round(bounds.width), 1), height: max(round(bounds.height), 1))
    }

    /// 以禁用隐式动画的方式落位画面（内容/几何），避免与旋转、耳高动画叠加补间。
    private func applyRasterImage(_ image: CGImage) {
        guard let transformLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        transformLayer.contents = image
        transformLayer.contentsScale = backingScale
        transformLayer.bounds = CGRect(origin: .zero, size: currentBucket)
        CATransaction.commit()
        renderedContentSize = currentBucket
    }

    /// 比较两张封面图是否内容一致（尺寸 + 像素数据），用于决定是否需要过渡。
    private static func imagesEqual(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height,
              a.bitsPerPixel == b.bitsPerPixel,
              a.bytesPerRow == b.bytesPerRow,
              a.colorSpace?.model == b.colorSpace?.model,
              let da = a.dataProvider?.data as Data?,
              let db = b.dataProvider?.data as Data?
        else { return false }
        return da == db
    }

    private func ensureTransformLayer() {
        guard transformLayer == nil, bounds.width > 0, bounds.height > 0, let hostLayer = layer else { return }
        let layer = CALayer()
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.bounds = CGRect(origin: .zero, size: bounds.size)
        layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        layer.contentsGravity = .resize
        layer.allowsEdgeAntialiasing = true
        layer.masksToBounds = false
        hostLayer.addSublayer(layer)
        transformLayer = layer
        configuredBounds = bounds
        rasterizeContent()
    }

    private func rasterizeContent() {
        guard let content else { return }
        // 布局变化引发的重绘：尺寸分桶变化才重绘，连续微变只改几何。
        let bucket = currentBucket
        let sizeBucketChanged = abs(renderedContentSize.width - bucket.width) >= 0.5
            || abs(renderedContentSize.height - bucket.height) >= 0.5
        guard sizeBucketChanged else { return }
        guard let image = renderImage(content, size: bucket, scale: backingScale) else { return }
        applyRasterImage(image)
    }

    private func renderImage(_ content: AnyView, size: CGSize, scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = max(scale, 1)
        renderer.proposedSize = ProposedViewSize(size)
        _ = renderer.nsImage
        return renderer.cgImage
    }

    // MARK: 布局

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }
        ensureTransformLayer()
        guard let transformLayer else { return }

        let boundsChanged = abs(configuredBounds.width - bounds.width) > 0.5
            || abs(configuredBounds.height - bounds.height) > 0.5
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        transformLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        transformLayer.position = center
        CATransaction.commit()
        configuredBounds = bounds

        if boundsChanged {
            rasterizeContent()
            refitTransitionLayers()
        }
        if isAnimating {
            startRotation()
        }
    }

    /// 过渡中的模糊层 / 旧封面层是按「出生时的尺寸」建的固定几何。
    /// 封面尺寸会在过渡期间变化（island 生长动画、播放↔暂停的 artworkScale 切换，
    /// 且切歌封面到达与 isMediaArtworkReady 翻转同帧发生，二者撞在一起），
    /// 此时主层已按新尺寸重绘，模糊层却仍留在旧位置旧大小，
    /// 只盖住封面一角 —— 观感就是「新封面基本是清晰的，只有一小块模糊」。
    /// 这里按主层的新几何重建过渡层，保证揭示动效始终覆盖整张封面。
    private func refitTransitionLayers() {
        guard isCrossfading else { return }
        let bucket = currentBucket
        if let blurLayer, blurLayer.bounds.size != bucket {
            refitBlurLayer(blurLayer, to: bucket)
        }
        if let crossfadeLayer, crossfadeLayer.bounds.size != bucket {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setAnimationDuration(0)
            crossfadeLayer.bounds = CGRect(origin: .zero, size: bucket)
            crossfadeLayer.position = CGPoint(x: bucket.width / 2, y: bucket.height / 2)
            CATransaction.commit()
        }
    }

    /// 模糊层换到新尺寸：几何、模糊位图与 alpha 轮廓遮罩一起重建（位图必须按新尺寸
    /// 重算，旧位图拉伸后与新封面对不上）。只改内容不动 opacity，
    /// 因此正在跑的揭示动画（fillMode .forwards）不受影响。
    private func refitBlurLayer(_ blurLayer: CALayer, to bucket: CGSize) {
        guard let contents = transformLayer?.contents else { return }
        let current = contents as! CGImage
        let blurred = Self.blurredImage(from: current)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        blurLayer.bounds = CGRect(origin: .zero, size: bucket)
        blurLayer.position = CGPoint(x: bucket.width / 2, y: bucket.height / 2)
        blurLayer.contentsScale = backingScale
        if let blurred {
            blurLayer.contents = blurred
            let silhouetteMask = CALayer()
            silhouetteMask.frame = blurLayer.bounds
            silhouetteMask.contents = current
            silhouetteMask.contentsScale = backingScale
            blurLayer.mask = silhouetteMask
        }
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            pauseAnimation()
        } else if isAnimating {
            startRotation()
        }
    }

    // MARK: 旋转状态机

    func apply(isRotating: Bool, resetToken: String, rotationDuration: Double) {
        let previousDuration = self.rotationDuration
        self.rotationDuration = rotationDuration

        let tokenChanged = resetToken != storedResetToken
        if tokenChanged {
            storedResetToken = resetToken
        }

        let isChangingState = isRotating != isAnimating
        isAnimating = isRotating

        // 注意：本方法只负责旋转状态机，绝不重绘封面图。封面是否变化/是否过渡
        // 完全由 setContent 判定，因此暂停/播放事件不会触发重新渲染 → 不抖动。
        if tokenChanged {
            // 切歌（或开/关旋转）：非旋转态归零相位停止常驻旋转。
            // 旋转模式切歌：一律平滑 回 0°，再从此继续自转 —— 版面复位统一。
            // 判定不能用瞬态 isAnimating：切歌瞬间 artwork 未就绪会把 isRotating
            // 短暂打成 false，若按它归零就会「有时回 0°、有时连续」。改为看
            // 这份旋转是否真的在自转（动画仍在层上）或本帧正切向旋转态。
            let wasRotatingLayer =
                transformLayer?.animation(forKey: Self.rotationAnimationKey) != nil
            let restingAtZero = abs(rotationAngle(
                from: transformLayer?.presentation()?.transform ?? CATransform3DIdentity
            )) < 0.01
            if isRotationEnabledForChanges && (isAnimating || wasRotatingLayer) {
                if wasRotatingLayer || !restingAtZero {
                    // 正在自转的封面切歌（含 artwork 晚到窗口）、或封面停留在
                    // 非零相位：统一平滑回 0°。自转状态以动画仍在层上为准 ——
                    // 不能只看瞬态 isAnimating，切歌瞬间 isPlaying 短暂为 false
                    // 会把旋转态归零，按它判断又会出现「有时回 0、有时不回」。
                    rezeroRotation()
                } else {
                    // 静止于 0° 的封面（旋转开关刚打开、此前未转会）：直接从当前
                    // 相位起转，无需做无意义的 0°→0° 归零而卡一下。
                    startRotation()
                }
            } else {
                resetAnimation()
            }
            return
        }

        if isChangingState {
            PocketNotchLog.media.debug(
                "Cover rotation state changed rotating=\(self.isAnimating) token=\(resetToken, privacy: .public)"
            )
            if isAnimating {
                startRotation()
            } else {
                pauseAnimation()
            }
            return
        }

        if isAnimating, abs(previousDuration - rotationDuration) > .ulpOfOne {
            refreshRotationAnimation()
        }
    }

    private func startRotation() {
        // 纯淡入淡出期间旋转必须并行持续（旋转实现成 transformLayer 上的
        // transform.rotation.z 关键帧，覆盖层是它的子层、一同旋转，互不干扰）；
        // 只有 3D 翻转这类自己接管变换的过渡才需要在此期间停旋转。
        // 回 0° 动画期间不接常驻旋转（完成后由 rezeroRotation 收尾接管）。
        guard !isRezeroing else { return }
        guard !isCrossfading || isPlainFade else { return }
        guard window != nil, let transformLayer else { return }
        guard transformLayer.bounds.width > 0, transformLayer.bounds.height > 0 else { return }
        guard transformLayer.animation(forKey: Self.rotationAnimationKey) == nil else { return }
        addRotationAnimation(to: transformLayer)
    }

    private func pauseAnimation() {
        guard let transformLayer else { return }
        PocketNotchLog.media.debug("Cover rotation pause animation")
        freezeCurrentRotation(in: transformLayer)
        transformLayer.removeAnimation(forKey: Self.rotationAnimationKey)
    }

    private func refreshRotationAnimation() {
        guard let transformLayer else { return }
        freezeCurrentRotation(in: transformLayer)
        transformLayer.removeAnimation(forKey: Self.rotationAnimationKey)
        addRotationAnimation(to: transformLayer)
    }

    /// 非旋转态切歌（或关闭旋转）时停止常驻旋转并归零相位。封面内容的过渡已由
    /// setContent 完成。旋转模式切歌走 rezeroRotation（平滑回 0°，见 apply）。
    private func resetAnimation() {
        guard let transformLayer else { return }
        // 只停旋转、归零相位；切歌 3D 翻转过渡必须保留继续跑完，
        // 否则翻转进行到一半会被打断回跳。
        transformLayer.removeAnimation(forKey: Self.rotationAnimationKey)
        transformLayer.transform = CATransform3DIdentity
    }

    /// 旋转模式切歌的「统一回 0°」：把当前自转相位平滑旋回 0（与玻璃揭示同频），
    /// 落地后清回零动画、再从此处恢复常驻自转。无论 artwork 即时还是晚到，
    /// 每次切歌的表现都完全一致。
    private func rezeroRotation() {
        guard let transformLayer else { return }
        guard window != nil else { return }

        let currentAngle = rotationAngle(
            from: transformLayer.presentation()?.transform ?? transformLayer.transform
        )
        transformLayer.removeAnimation(forKey: Self.rotationAnimationKey)
        isRezeroing = true

        CATransaction.begin()
        CATransaction.setAnimationDuration(0)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, let layer = self.transformLayer else { return }
            self.isRezeroing = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setAnimationDuration(0)
            layer.removeAnimation(forKey: Self.rezeroAnimationKey)
            layer.transform = CATransform3DIdentity
            CATransaction.commit()
            // 恢复自转前确认仍在播放态（切歌后立刻暂停则不续转）。
            if self.isAnimating {
                self.startRotation()
            }
        }

        let unwind = CABasicAnimation(keyPath: "transform.rotation.z")
        unwind.fromValue = NSNumber(value: currentAngle)
        unwind.toValue = 0
        unwind.duration = FlipTransitionDesign.rezeroDuration
        unwind.timingFunction = CAMediaTimingFunction(name: .easeOut)
        unwind.isRemovedOnCompletion = false
        unwind.fillMode = .forwards
        transformLayer.add(unwind, forKey: Self.rezeroAnimationKey)
        CATransaction.commit()
    }

    /// 切歌封面过渡（灵动岛式 180° 单面 3D 翻转）：
    /// 主层自身带透视绕竖直轴纯旋转半圈，前半程当前封面转出，
    /// 90° 侧立（不可见）瞬间换上最新渲染的新封面并施加高斯模糊，
    /// 后半程模糊态新封面转入（屏幕空间镜像校正保持正向），
    /// 落定后模糊渐渐消散、真封面原地显现。不放大；App 图标兜底过渡、
    /// 减弱动态与旋转模式（见 setContent）时退化为纯透明度交叉淡入淡出。
    private func crossfade(from oldImage: CGImage, to newImage: CGImage) {
        guard let transformLayer else { return }
        let targetBounds = transformLayer.bounds

        // 若上一段过渡仍在进行，先移除残留卡片与动画，从当前画面重新起翻。
        if isCrossfading {
crossfadeLayer?.removeFromSuperlayer()
            crossfadeLayer = nil
            blurLayer?.removeFromSuperlayer()
            blurLayer = nil
            transformLayer.removeAnimation(forKey: Self.flipAnimationKey)
            transformLayer.removeAnimation(forKey: Self.unblurAnimationKey)
        }

        if isFlipTransitionEnabled {
            startFlip(from: oldImage, to: newImage, bounds: targetBounds)
            return
        }

        fadeTransition(from: oldImage, to: newImage, bounds: targetBounds)
    }

    /// 普通淡入淡出过渡：主层直接落位新封面，旧封面承载层盖在上面淡出。
    /// 减弱动态与「封面 ↔ App 图标兜底」过渡使用。
    private func fadeTransition(from oldImage: CGImage, to newImage: CGImage, bounds: CGRect) {
        guard let transformLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        transformLayer.contents = newImage
        transformLayer.contentsScale = backingScale
        transformLayer.bounds = bounds
        transformLayer.opacity = 1
        CATransaction.commit()
        renderedContentSize = bounds.size

        let overlay = CALayer()
        overlay.anchorPoint = transformLayer.anchorPoint
        overlay.bounds = bounds
        overlay.position = transformLayer.position
        overlay.contents = oldImage
        overlay.contentsScale = transformLayer.contentsScale
        overlay.contentsGravity = transformLayer.contentsGravity
        overlay.allowsEdgeAntialiasing = true
        overlay.opacity = 1
        transformLayer.addSublayer(overlay)
        crossfadeLayer = overlay

        isCrossfading = true
        isPlainFade = true

        CATransaction.begin()
        CATransaction.setAnimationDuration(0)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            self.finishCrossfade()
        }

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1
        fadeOut.toValue = 0
        fadeOut.duration = FlipTransitionDesign.plainFadeDuration
        fadeOut.isRemovedOnCompletion = false
        fadeOut.fillMode = .forwards
        overlay.add(fadeOut, forKey: Self.fadeOutAnimationKey)

        CATransaction.commit()
    }

    /// 旋转模式的「玻璃揭示」切歌过渡：与翻转落定后的揭示同源 —— 主层换上新封面，
    /// 其上叠「新封面高斯模糊」的磨砂镜片（清晰轮廓 alpha 遮罩），随后磨砂镜片
    /// 渐渐退散、真封面原地显现。磨砂就是翻转用的同一张 blurredImage 管线
    /// （反射垫边 + 高斯模糊 + 降饱和 + 封面色调光泽），且直接复用 runUnblurReveal，
    /// 效果与翻转的玻璃揭示逐像素一致。省略 3D 翻转本身（自转承担运动感），
    /// 不触碰主层变换、没有旧封面覆盖层，旋转全程不停。
    private func glassFade(from _: CGImage, to newImage: CGImage, bounds: CGRect) {
        guard let transformLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        transformLayer.contents = newImage
        transformLayer.contentsScale = backingScale
        transformLayer.bounds = bounds
        transformLayer.opacity = 1
        CATransaction.commit()
        renderedContentSize = bounds.size

        // 磨砂镜片：高斯模糊版新封面，遮罩 = 清晰封面栅格自身的 alpha。
        if let blurred = Self.blurredImage(from: newImage) {
            let blurLayer = CALayer()
            blurLayer.frame = CGRect(origin: .zero, size: bounds.size)
            blurLayer.contents = blurred
            blurLayer.contentsScale = backingScale
            let silhouetteMask = CALayer()
            silhouetteMask.frame = blurLayer.bounds
            silhouetteMask.contents = newImage
            silhouetteMask.contentsScale = backingScale
            blurLayer.mask = silhouetteMask
            blurLayer.allowsEdgeAntialiasing = true
            transformLayer.addSublayer(blurLayer)
            self.blurLayer = blurLayer
        }

        isCrossfading = true
        isPlainFade = true

        // 与翻转同款的揭示：磨砂镜片 opacity 1→0 退散显影（缺失时立即收尾）。
        runUnblurReveal()
    }

    /// 180° 单面翻转：主层自身带透视转半圈，前半程当前封面转出，
    /// 90° 侧立（不可见）瞬间换上最新渲染的新封面并施加高斯模糊，
    /// 后半程模糊态新封面转入落定（屏幕空间镜像校正保持正向），
    /// 落定后模糊半径渐渐退散、真封面原地显现。纯旋转、不放大、无双面分层。
    ///
    /// 翻转必须拆成两段 `CABasicAnimation`：背面镜像校正若嵌进同一段
    /// 关键帧矩阵里参与插值，会在 90°~120° 之间穿过行列式变号的退化状态，
    /// 中间帧变换矩阵不稳定 → 闪烁。两段各自插值时镜像恒定，插值干净。
    private func startFlip(from oldImage: CGImage, to newImage: CGImage, bounds: CGRect) {
        guard let transformLayer else { return }
        isCrossfading = true

        let distance = max(
            bounds.width * FlipTransitionDesign.perspectiveDistanceRatio,
            FlipTransitionDesign.minimumPerspectiveDistance
        )

        // 前半程（0°→90°）：当前封面转入侧面，easeIn（侧立时角速度最快）。
        CATransaction.begin()
        CATransaction.setAnimationDuration(0)
        CATransaction.setCompletionBlock { [weak self] in
            // 90° 侧立（内容零宽不可见）：换上最新渲染的新封面并施加高斯模糊。
            // 封面常在切歌后晚到，此刻读取最新渲染可吸收刚到达的封面数据。
            self?.swapToNewArtworkAtEdge()
            self?.runFlipSecondHalf(distance: distance)
        }
        let firstHalf = CABasicAnimation(keyPath: "transform")
        firstHalf.fromValue = NSValue(
            caTransform3D: Self.flipTransform(angle: 0, distance: distance)
        )
        firstHalf.toValue = NSValue(
            caTransform3D: Self.flipTransform(angle: .pi / 2, distance: distance)
        )
        firstHalf.duration = FlipTransitionDesign.flipDuration / 2
        firstHalf.timingFunction = CAMediaTimingFunction(name: .easeIn)
        firstHalf.isRemovedOnCompletion = false
        firstHalf.fillMode = .forwards
        transformLayer.add(firstHalf, forKey: Self.flipAnimationKey)
        CATransaction.commit()
    }

    /// 后半程（90°→180°）：镜像校正恒定作用于整段（from/to 均含 S(-1,1,1)，
    /// 插值不穿越退化矩阵），模糊态新封面转入落定，随后进入模糊消散揭示。
    private func runFlipSecondHalf(distance: CGFloat) {
        guard isCrossfading, let transformLayer else { return }

        CATransaction.begin()
        CATransaction.setAnimationDuration(0)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            // 180°+镜像校正的显示与 0° 逐像素等价，模型归位无跳变。
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setAnimationDuration(0)
            transformLayer.removeAnimation(forKey: Self.flipAnimationKey)
            transformLayer.transform = CATransform3DIdentity
            CATransaction.commit()
            self.runUnblurReveal()
        }
        let secondHalf = CABasicAnimation(keyPath: "transform")
        secondHalf.fromValue = NSValue(
            caTransform3D: Self.mirroredFlipTransform(angle: .pi / 2, distance: distance)
        )
        secondHalf.toValue = NSValue(
            caTransform3D: Self.mirroredFlipTransform(angle: .pi, distance: distance)
        )
        secondHalf.duration = FlipTransitionDesign.flipDuration / 2
        secondHalf.timingFunction = CAMediaTimingFunction(name: .easeOut)
        secondHalf.isRemovedOnCompletion = false
        secondHalf.fillMode = .forwards
        transformLayer.add(secondHalf, forKey: Self.flipAnimationKey)
        CATransaction.commit()
    }

    /// 背面阶段矩阵：镜像校正在本段内恒定（只在 90° 侧立瞬间启用/停用）。
    private static func mirroredFlipTransform(angle: CGFloat, distance: CGFloat) -> CATransform3D {
        CATransform3DScale(flipTransform(angle: angle, distance: distance), -1, 1, 1)
    }

    /// 90° 侧立瞬间换图：主层落位最新渲染的清晰新封面，并在其上叠加
    /// 「CoreImage 预生成的模糊封面」子图层——**用清晰封面的 alpha 轮廓做遮罩**，
    /// 高斯模糊的出血被裁在封面轮廓内，绝不糊到封面以外的区域。
    /// 模糊在旋转全程保持恒定，落定后由 runUnblurReveal 渐渐退散。
    private func swapToNewArtworkAtEdge() {
        guard isCrossfading, let transformLayer else { return }
        guard let latest = content.flatMap({
            renderImage($0, size: currentBucket, scale: backingScale)
        }) else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        transformLayer.contents = latest
        renderedContentSize = currentBucket

        if let blurred = Self.blurredImage(from: latest) {
            let blurLayer = CALayer()
            blurLayer.frame = CGRect(origin: .zero, size: currentBucket)
            blurLayer.contents = blurred
            blurLayer.contentsScale = backingScale
            // 遮罩 = 清晰封面栅格自身的 alpha：模糊向轮廓外渗透的部分被裁掉。
            // 曾因几何错配（模糊层尺寸冻结在出生时）被误判为「mask 导致整层不可见」
            // 而临时禁用作二分；几何已由 refitTransitionLayers 修复，恢复遮罩。
            let silhouetteMask = CALayer()
            silhouetteMask.frame = blurLayer.bounds
            silhouetteMask.contents = latest
            silhouetteMask.contentsScale = backingScale
            blurLayer.mask = silhouetteMask
            blurLayer.allowsEdgeAntialiasing = true
            transformLayer.addSublayer(blurLayer)
            PocketNotchLog.media.debug(
                "Cover blur layer created blurredPx=\(blurred.width)x\(blurred.height) clearPx=\(latest.width)x\(latest.height) framePt=\(Int(self.currentBucket.width))x\(Int(self.currentBucket.height)) scale=\(Int(self.backingScale))"
            )
            self.blurLayer = blurLayer
        } else {
            // 模糊位图生成失败：后续 runUnblurReveal 会按无模糊收尾（不会卡死过渡状态）。
            PocketNotchLog.media.debug(
                "Cover blur bitmap generation failed size=\(Int(self.currentBucket.width))×\(Int(self.currentBucket.height))"
            )
        }
        CATransaction.commit()
    }

    /// 过渡统一收尾：清理模糊/旧封面层、复位状态、恢复旋转并补一次内容同步。
    /// 所有过渡退出路径（正常完成、模糊层缺失、重入清理）都必须经过这里，
    /// 否则 isCrossfading 卡 true 会永久跳过 setContent 与 startRotation。
    private func finishCrossfade() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        blurLayer?.removeFromSuperlayer()
        blurLayer = nil
        crossfadeLayer?.removeFromSuperlayer()
        crossfadeLayer = nil
        CATransaction.commit()
        isCrossfading = false
        isPlainFade = false
        // 过渡期间 setContent 被跳过，结束后补一次同步（如过渡中封面才到 / 又切了歌）。
        // 必须排在 appliedFallbackArtwork 同步之前：补同步要靠「兜底 ↔ 真封面」这个
        // 变化信号决定是否再翻一次，先同步就把信号抹掉、退化成硬切了。
        if let content {
            setContent(content)
        }
        appliedFallbackArtwork = isFallbackArtwork
        // 过渡结束后：若仍在播放态，让封面从 0° 开始重新旋转。
        // 若上面补同步又起了一段翻转，startRotation 会被 isCrossfading 挡下，
        // 由新翻转自己接管变换。
        if isAnimating {
            startRotation()
        }
    }

    /// 落定后的揭示：模糊子图层透明度渐渐退散（模糊渐渐减去），
    /// 底下的清晰真封面原地显现，完成后清理并恢复旋转。
    private func runUnblurReveal() {
        guard isCrossfading else { return }
        guard let blurLayer else {
            // 模糊层缺失（模糊位图生成失败）：按无模糊完成过渡，绝不卡死状态机。
            PocketNotchLog.media.debug("Cover unblur reveal skipped: blur layer missing")
            finishCrossfade()
            return
        }
        PocketNotchLog.media.debug("Cover unblur reveal started")

        CATransaction.begin()
        CATransaction.setAnimationDuration(0)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            self.finishCrossfade()
        }
        let reveal = CABasicAnimation(keyPath: "opacity")
        reveal.fromValue = 1
        reveal.toValue = 0
        reveal.duration = FlipTransitionDesign.unblurDuration
        reveal.timingFunction = CAMediaTimingFunction(name: .easeOut)
        reveal.isRemovedOnCompletion = false
        reveal.fillMode = .forwards
        blurLayer.add(reveal, forKey: Self.unblurAnimationKey)
        CATransaction.commit()
    }
    /// 绕竖直轴、带透视的纯旋转矩阵（anchorPoint 居中），无缩放。
    private static func flipTransform(angle: CGFloat, distance: CGFloat) -> CATransform3D {
        var transform = CATransform3DIdentity
        transform.m34 = -1 / distance
        return CATransform3DRotate(transform, angle, 0, 1, 0)
    }

    private func freezeCurrentRotation(in layer: CALayer) {
        let transform = layer.presentation()?.transform ?? layer.transform
        let angle = rotationAngle(from: transform)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = rotationTransform(angle)
        CATransaction.commit()
    }

    private func addRotationAnimation(to layer: CALayer) {
        let currentTransform = layer.presentation()?.transform ?? layer.transform
        let startAngle = rotationAngle(from: currentTransform)
        let stepCount = 120
        let angleStep = (2 * Double.pi) / Double(stepCount)

        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        animation.values = (0...stepCount).map { step in
            NSNumber(value: startAngle + angleStep * Double(step))
        }
        animation.keyTimes = (0...stepCount).map { NSNumber(value: Double($0) / Double(stepCount)) }
        animation.duration = max(rotationDuration, 0.001)
        animation.repeatCount = .greatestFiniteMagnitude
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        layer.add(animation, forKey: Self.rotationAnimationKey)
    }

    /// 从当前变换提取绕 Z 轴的相位，供恢复与重建关键帧动画使用。
    private func rotationAngle(from transform: CATransform3D) -> Double {
        atan2(Double(transform.m12), Double(transform.m11))
    }

    /// 变换层固定以 anchorPoint(0.5, 0.5) 为中心旋转；几何自持，无需叠加局部平移。
    private func rotationTransform(_ radians: Double) -> CATransform3D {
        CATransform3DMakeRotation(CGFloat(radians), 0, 0, 1)
    }

    func teardown() {
        pauseAnimation()
        isAnimating = false
        isCrossfading = false
        isPlainFade = false
        isRezeroing = false
        contentsSongKey = nil
        crossfadeLayer?.removeFromSuperlayer()
        crossfadeLayer = nil
        blurLayer?.removeFromSuperlayer()
        blurLayer = nil
        transformLayer?.removeFromSuperlayer()
        transformLayer = nil
        content = nil
    }
}