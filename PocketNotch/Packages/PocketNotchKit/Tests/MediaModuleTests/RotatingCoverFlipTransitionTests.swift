import AppKit
import SwiftUI
import XCTest

@testable import MediaModule

@MainActor
final class RotatingCoverFlipTransitionTests: XCTestCase {
    /// 结构对齐耳内封面：近黑背板 + 渐变，圆角裁切。
    private struct ProbeCover: View {
        var tint: Double

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black)
                LinearGradient(
                    colors: [Color(hue: tint, saturation: 0.9, brightness: 1.0), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: 24, height: 24)
        }
    }

    private func mirror(_ object: Any) -> [String: Any] {
        Mirror(reflecting: object).children.reduce(into: [String: Any]()) { result, child in
            if let label = child.label { result[label] = child.value }
        }
    }

    private func makeHost(_ size: CGFloat) -> (NSWindow, RotatingCoverHostView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView?.wantsLayer = true
        window.orderFront(nil)
        let view = RotatingCoverHostView()
        view.wantsLayer = true
        view.frame = NSRect(x: 0, y: 0, width: size, height: size)
        window.contentView?.addSubview(view)
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        return (window, view)
    }

    /// 翻转期间封面尺寸变化：模糊层必须跟随新几何，且揭示动画继续跑完。
    /// 翻转只发生在不旋转的场景，因此 makeHost 后不以 isRotating 启动。
    func testRefitKeepsRevealAlive() throws {
        let (window, view) = makeHost(18)
        view.songKey = "a"
        view.setContent(AnyView(ProbeCover(tint: 0.6)))
        view.isFlipTransitionEnabled = true
        view.apply(isRotating: false, resetToken: "a", rotationDuration: 10)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        view.songKey = "b"
        view.setContent(AnyView(ProbeCover(tint: 0.1)))
        view.apply(isRotating: false, resetToken: "b", rotationDuration: 10)

        // 等模糊层真的出现（翻转转到 90° 才建），再改尺寸：不写死绝对时刻，
        // 过渡时长调整后本用例依然成立。
        var revealed = false
        for _ in 0..<30 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            if mirror(view)["blurLayer"] is CALayer {
                revealed = true
                break
            }
        }
        XCTAssertTrue(revealed, "翻转进入揭示阶段时应存在模糊层")
        view.frame = NSRect(x: 0, y: 0, width: 30, height: 30)
        window.contentView?.layoutSubtreeIfNeeded()

        var opacities: [Float] = []
        var sizes: Set<String> = []
        var sawRemoval = false
        for _ in 0..<60 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            let m = mirror(view)
            if let blur = m["blurLayer"] as? CALayer {
                opacities.append(blur.presentation()?.opacity ?? -1)
                sizes.insert("\(Int(blur.bounds.width))x\(Int(blur.bounds.height))")
            } else {
                sawRemoval = true
                break
            }
        }
        let m = mirror(view)
        _ = m
        XCTAssertEqual(sizes, ["30x30"], "模糊层必须跟随新尺寸")
        let decreasing = zip(opacities, opacities.dropFirst()).allSatisfy { $0 >= $1 }
        XCTAssertTrue(decreasing, "揭示动画应在重建后继续渐隐: \(opacities)")
        if !sawRemoval {
            XCTAssertEqual(opacities.last ?? 1, 0, accuracy: 0.02, "揭示应收尾到 0")
        }
    }

    /// 无尺寸变化时行为不变。翻转只发生在不旋转的场景，因此不以 isRotating 启动。
    func testNoResizePathUnchanged() throws {
        let (_, view) = makeHost(24)
        view.songKey = "a"
        view.setContent(AnyView(ProbeCover(tint: 0.6)))
        view.isFlipTransitionEnabled = true
        view.apply(isRotating: false, resetToken: "a", rotationDuration: 10)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        view.songKey = "b"
        view.setContent(AnyView(ProbeCover(tint: 0.1)))
        view.apply(isRotating: false, resetToken: "b", rotationDuration: 10)

        var sawBlurFullOpacity = false
        for _ in 0..<26 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            let m = mirror(view)
            if (m["isCrossfading"] as? Bool) != true { break }
            guard let blur = m["blurLayer"] as? CALayer else { continue }
            XCTAssertEqual(blur.bounds.size, CGSize(width: 24, height: 24))
            if (blur.presentation()?.opacity ?? 0) > 0.95 { sawBlurFullOpacity = true }
        }
        XCTAssertTrue(sawBlurFullOpacity, "翻转落定瞬间应为全模糊")
        let m = mirror(view)
        XCTAssertEqual(m["isCrossfading"] as? Bool, false, "过渡应收尾")
    }

    /// 雾面必须是「封面透过来的颜色」：红蓝双色卡上，整卡左边透红、右边透蓝、
    /// 中间过渡 —— 不是白卡、也不是一张均值卡；同时边缘已被软化（不是清晰的
    /// 纯色边缘，那正是旧实现「只糊中间」的伪影）。
    func testFrostCarriesCoverColorsAcrossWholeCard() throws {
        let (_, view) = makeHost(24)
        view.songKey = "a"
        view.setContent(AnyView(Rectangle().fill(Color.green)))
        view.isFlipTransitionEnabled = true

        view.songKey = "b"
        view.setContent(AnyView(TwoToneCover()))

        var blurContents: CGImage?
        for _ in 0..<24 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            let m = mirror(view)
            if let blur = m["blurLayer"] as? CALayer {
                if let contents = blur.contents {
                    blurContents = contents as! CGImage
                }
                if blurContents != nil { break }
            }
        }
        let image = try XCTUnwrap(blurContents, "未创建模糊层")
        let midY = image.height / 2
        let left = samplePixel(image, x: max(1, image.width / 12), y: midY)
        let center = samplePixel(image, x: image.width / 2, y: midY)
        let right = samplePixel(image, x: min(image.width - 2, image.width * 11 / 12), y: midY)
        print("PROBE5 blurImg=\(image.width)x\(image.height) left=\(left) center=\(center) right=\(right)")

        let dominance = { (p: (r: Double, g: Double, b: Double)) -> Double in p.r - p.b }
        let leftDom = dominance(left)
        let rightDom = dominance(right)
        let centerDom = dominance(center)
        print("PROBE5 domains: left=\(leftDom) center=\(centerDom) right=\(rightDom)")
        XCTAssertGreaterThan(leftDom, 15, "左缘应透出封面红色: \(leftDom)")
        XCTAssertLessThan(rightDom, -15, "右缘应透出封面蓝色: \(rightDom)")
        XCTAssertGreaterThan(centerDom, rightDom, "中→右应延续封面横向色相梯度")
        XCTAssertLessThan(abs(leftDom), 180, "左缘应已被软化（清晰红 r-b≈200）: \(leftDom)")
        XCTAssertLessThan(abs(rightDom), 180, "右缘应已被软化（清晰蓝 r-b≈-200）: \(rightDom)")
    }

    /// 模糊确实在起作用：跨过红/蓝边界的相邻像素，清晰层色阶差大、雾层被抹平。
    func testBlurSoftensLocalContrast() throws {
        let (_, view) = makeHost(24)
        view.songKey = "a"
        view.setContent(AnyView(Rectangle().fill(Color.green)))
        view.isFlipTransitionEnabled = true

        view.songKey = "b"
        view.setContent(AnyView(TwoToneCover()))

        var blurContents: CGImage?
        var crispContents: CGImage?
        for _ in 0..<24 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            let m = mirror(view)
            if let blur = m["blurLayer"] as? CALayer {
                if let contents = blur.contents {
                    blurContents = contents as! CGImage
                }
            }
            if let transform = m["transformLayer"] as? CALayer, let contents = transform.contents {
                crispContents = contents as! CGImage
            }
            if blurContents != nil, crispContents != nil { break }
        }
        let blurred = try XCTUnwrap(blurContents, "未创建模糊层")
        let crisp = try XCTUnwrap(crispContents, "清晰层缺失")
        let midY = blurred.height / 2
        let blurredMidX = blurred.width / 2
        let crispMidX = crisp.width / 2
        let blurStep = abs(
            samplePixel(blurred, x: blurredMidX - 1, y: midY).r
                - samplePixel(blurred, x: blurredMidX + 1, y: midY).r
        )
        let crispStep = abs(
            samplePixel(crisp, x: crispMidX - 1, y: midY).r
                - samplePixel(crisp, x: crispMidX + 1, y: midY).r
        )
        print("PROBE6 crispStep=\(crispStep) blurStep=\(blurStep)")
        XCTAssertGreaterThan(crispStep, 100, "清晰层跨边界应有锐利色阶差: \(crispStep)")
        XCTAssertLessThan(blurStep, 40, "雾层应抹平边界色阶: \(blurStep)")
    }

    /// 玻璃光泽：中心偏上的柔和径向光晕会明显提亮磨砂中心，四角远离光心几乎
    /// 不受影响 —— 中心亮度必须显著高于角落，且中心本身明显高于纯磨砂的均值。
    func testBloomLightsGlassCenter() throws {
        let (_, view) = makeHost(24)
        view.songKey = "a"
        view.setContent(AnyView(Rectangle().fill(Color.green)))
        view.isFlipTransitionEnabled = true

        view.songKey = "b"
        view.setContent(AnyView(TwoToneCover()))

        var blurContents: CGImage?
        for _ in 0..<24 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            let m = mirror(view)
            if let blur = m["blurLayer"] as? CALayer {
                if let contents = blur.contents { blurContents = contents as! CGImage }
                if blurContents != nil { break }
            }
        }
        let image = try XCTUnwrap(blurContents, "未创建模糊层")
        let center = samplePixel(image, x: image.width / 2, y: image.height / 2)
        let corner = samplePixel(image, x: min(image.width - 2, image.width - 1), y: min(image.height - 2, image.height - 1))
        let luma = { (p: (r: Double, g: Double, b: Double)) -> Double in 0.3 * p.r + 0.59 * p.g + 0.11 * p.b }
        let centerLuma = luma(center)
        let cornerLuma = luma(corner)
        print("PROBE7 centerLuma=\(centerLuma) cornerLuma=\(cornerLuma) center=\(center) corner=\(corner)")
        XCTAssertGreaterThan(centerLuma, 150, "中心须被光晕明显提亮: \(centerLuma)")
        XCTAssertGreaterThan(centerLuma - cornerLuma, 25, "中心应明显亮于远离光心的角落: \(centerLuma - cornerLuma)")
    }

    /// 旋转模式切歌：不翻转，改为磨砂玻璃揭示 + 相位统一回 0°（平滑旋回后再续转）。
    /// 判定依据是设置中心开关 isRotationEnabledForChanges（稳定用户意图），不是
    /// 瞬态 isAnimating：所以即使切歌瞬间 artwork 短暂未就绪、apply 把 isRotating
    /// 打成 false，回 0° 的归零过程也必须统一发生，不能时而归零时而不归零。
    func testRotatingSongChangeSkipsFlip() throws {
        let (_, view) = makeHost(24)
        view.isFlipTransitionEnabled = true
        view.isRotationEnabledForChanges = true
        view.songKey = "a"
        view.setContent(AnyView(ProbeCover(tint: 0.6)))
        view.apply(isRotating: true, resetToken: "a", rotationDuration: 10)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        // 切歌、artwork 未就绪：isRotating 短暂为 false，但旋转动画仍在层上 →
        // 依旧统一进入「回 0°」归零（旧实现正是这一步要么跳回 0°、要么不跳，时有时无）。
        view.songKey = "b"
        view.apply(isRotating: false, resetToken: "b", rotationDuration: 10)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let mWindow = mirror(view)
        let windowLayer = mWindow["transformLayer"] as! CALayer
        XCTAssertNotNil(
            windowLayer.animation(forKey: "pocketnotch.cover.rezero"),
            "旋转模式切歌应统一启动回 0° 归零动画"
        )
        XCTAssertNil(windowLayer.animation(forKey: "pocketnotch.cover.rotation"), "归零期间不应继续常驻自转")
        XCTAssertNil(windowLayer.animation(forKey: "pocketnotch.cover.flip"), "旋转模式不应翻转")

        // artwork 到达：磨砂玻璃揭示换图。
        view.setContent(AnyView(ProbeCover(tint: 0.1)))
        view.apply(isRotating: true, resetToken: "b", rotationDuration: 10)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let mMid = mirror(view)
        XCTAssertNotNil(mMid["blurLayer"] as? CALayer, "旋转模式切歌应有翻转同款磨砂玻璃揭示")
        XCTAssertNil(mMid["crossfadeLayer"] as? CALayer, "旋转模式揭示应像翻转一样是纯磨砂退散，无旧封面覆盖层")

        // 回 0° 归零结束：自转恢复、过渡收尾。
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let m = mirror(view)
        guard let layer = m["transformLayer"] as? CALayer else {
            return XCTFail("transformLayer 缺失")
        }
        XCTAssertNotNil(
            layer.animation(forKey: "pocketnotch.cover.rotation"),
            "回 0° 后应恢复常驻自转"
        )
        XCTAssertNil(
            layer.animation(forKey: "pocketnotch.cover.flip"),
            "旋转模式（开关开启）不应触发 3D 翻转动画"
        )
        XCTAssertEqual(m["isCrossfading"] as? Bool, false, "过渡应已收尾")
    }

    /// 切歌等封面期间画面还是上一张：封面到达时 songKey 早已是新歌，
    /// 必须靠「显示内容属于别的歌」判定补一次完整过渡，否则会静默换图。
    func testCoverArrivingAfterWaitStillFlips() {
        let (_, view) = makeHost(24)
        view.isFlipTransitionEnabled = true
        view.songKey = "a"
        view.setContent(AnyView(ProbeCover(tint: 0.6)))
        view.apply(isRotating: false, resetToken: "a", rotationDuration: 10)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        // 等封面窗口：songKey 已是新歌，画面仍旧封面。
        view.songKey = "b"
        view.setContent(AnyView(ProbeCover(tint: 0.6)))
        XCTAssertEqual(mirror(view)["isCrossfading"] as? Bool, false, "等封面期间画面不动")

        // 真封面到达：一次翻面到位，不出现图标占位。
        view.setContent(AnyView(ProbeCover(tint: 0.1)))
        let m = mirror(view)
        XCTAssertEqual(m["isCrossfading"] as? Bool, true, "等窗口后到达的封面应放完整过渡")
        XCTAssertEqual(m["isPlainFade"] as? Bool, false, "应是翻面，不是淡入淡出")
        XCTAssertNotNil(
            (m["transformLayer"] as? CALayer)?.animation(forKey: "pocketnotch.cover.flip"),
            "应走 180° 翻转"
        )
    }

    /// 图标已翻完定格很久、真封面才姗姗来迟：和所有其他封面变化一样翻面，
    /// 不再有「迟到」特例（按压式接力已删除）。
    func testLateCoverArrivalFlipsLikeAnyOtherCoverChange() {
        let (_, view) = makeHost(24)
        view.isFlipTransitionEnabled = true
        view.songKey = "a"
        view.setContent(AnyView(ProbeCover(tint: 0.6)))
        view.apply(isRotating: false, resetToken: "a", rotationDuration: 10)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        // 等不到封面 → 翻到 App 图标。
        view.songKey = "b"
        view.isFallbackArtwork = true
        view.setContent(AnyView(ProbeCover(tint: 0.9)))
        XCTAssertNotNil(
            (mirror(view)["transformLayer"] as? CALayer)?.animation(forKey: "pocketnotch.cover.flip"),
            "切到图标应翻面"
        )
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        XCTAssertEqual(mirror(view)["isCrossfading"] as? Bool, false, "图标过渡应收尾")

        // 图标已彻底定格（远超任何旧阈值）后真封面才到：照样翻面。
        view.isFallbackArtwork = false
        view.setContent(AnyView(ProbeCover(tint: 0.1)))
        let m = mirror(view)
        XCTAssertEqual(m["isCrossfading"] as? Bool, true, "迟到封面仍有过渡")
        XCTAssertNotNil(
            (m["transformLayer"] as? CALayer)?.animation(forKey: "pocketnotch.cover.flip"),
            "迟到封面与其它封面变化一样翻面"
        )
        XCTAssertNil(m["blurLayer"] as? CALayer, "非旋转模式的翻面不挂磨砂层")

        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        let mEnd = mirror(view)
        XCTAssertEqual(mEnd["isCrossfading"] as? Bool, false, "第二次翻面也要收尾")
        XCTAssertNil(mEnd["crossfadeLayer"] as? CALayer)
        XCTAssertNil(mEnd["blurLayer"] as? CALayer, "第二次翻面结束后磨砂层要清掉")
    }

    /// 迟到封面到达时上一段翻转仍在进行：不打断，落定后补翻一次。
    func testCoverArrivingMidFlipIsDeferredThenFlipsOnce() {
        let (_, view) = makeHost(24)
        view.isFlipTransitionEnabled = true
        view.songKey = "a"
        view.setContent(AnyView(ProbeCover(tint: 0.6)))
        view.apply(isRotating: false, resetToken: "a", rotationDuration: 10)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        view.songKey = "b"
        view.isFallbackArtwork = true
        view.setContent(AnyView(ProbeCover(tint: 0.9)))
        XCTAssertEqual(mirror(view)["isCrossfading"] as? Bool, true)

        // 翻面途中真封面到了：只记录，不打断当前翻转。
        view.isFallbackArtwork = false
        view.setContent(AnyView(ProbeCover(tint: 0.1)))
        XCTAssertEqual(mirror(view)["isCrossfading"] as? Bool, true, "途中到达不打断当前翻转")

        // 上一段落定 → 补同步起第二次翻面。翻面只有 0.5s 长，固定等 1.2s 会错过
        // 动画窗口，改成轮询记录「是否出现过翻面」。
        var sawSecondFlip = false
        for _ in 0..<30 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if (mirror(view)["transformLayer"] as? CALayer)?.animation(forKey: "pocketnotch.cover.flip") != nil {
                sawSecondFlip = true
                break
            }
        }
        XCTAssertTrue(sawSecondFlip, "落定后应补翻一次")
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        XCTAssertEqual(mirror(view)["isCrossfading"] as? Bool, false, "第二次翻面也要收尾")
    }

    /// 旋转模式下的切歌：图标与真封面各走一次磨砂玻璃揭示，仍不翻面。
    func testRotationModeIconAndRealCoverBothUseGlassReveal() {
        let (_, view) = makeHost(24)
        view.isFlipTransitionEnabled = true
        view.isRotationEnabledForChanges = true
        view.songKey = "a"
        view.setContent(AnyView(ProbeCover(tint: 0.6)))
        view.apply(isRotating: true, resetToken: "a", rotationDuration: 10)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        view.songKey = "b"
        view.isFallbackArtwork = true
        view.setContent(AnyView(ProbeCover(tint: 0.9)))
        var m = mirror(view)
        XCTAssertNotNil(m["blurLayer"] as? CALayer, "旋转模式下切到图标应是磨砂揭示")
        XCTAssertNil(m["crossfadeLayer"] as? CALayer, "旋转模式不翻面")
        XCTAssertNil(
            (m["transformLayer"] as? CALayer)?.animation(forKey: "pocketnotch.cover.flip"),
            "旋转模式不应触发 3D 翻转"
        )

        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        view.isFallbackArtwork = false
        view.setContent(AnyView(ProbeCover(tint: 0.1)))
        m = mirror(view)
        XCTAssertNotNil(m["blurLayer"] as? CALayer, "真封面到达同样是磨砂揭示")
        XCTAssertNil(m["crossfadeLayer"] as? CALayer, "旋转模式不翻面")
    }

    /// 红蓝双色封面：整卡透出封面透过来的颜色。
    private struct TwoToneCover: View {
        var body: some View {
            HStack(spacing: 0) {
                Color.red
                Color.blue
            }
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func samplePixel(_ image: CGImage, x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (0, 0, 0) }
        ctx.translateBy(x: -CGFloat(x), y: -CGFloat(y))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (Double(pixel[0]), Double(pixel[1]), Double(pixel[2]))
    }
}
