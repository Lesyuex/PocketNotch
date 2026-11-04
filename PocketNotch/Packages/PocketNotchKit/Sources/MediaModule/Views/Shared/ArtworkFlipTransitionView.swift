import SwiftUI

/// 切歌封面的「灵动岛式」3D 翻转过渡（单面方案）：封面整张绕竖直轴纯旋转
/// 180°（easeInOut，透视 0.65，无放大）——前半程当前封面转出，90° 侧立
/// （不可见）瞬间换上最新封面并施加高斯模糊，后半程模糊态新封面转回，
/// 落定后模糊渐渐消散、真封面原地显现。
/// 背面阶段（归一化角 90°~270°）用 scaleEffect(x: -1) 镜像校正保持正向，
/// 侧立瞬间切换不可见；翻转角逐次累计不归零（与 Atoll 一致）。
/// 封面晚到时的处理：90° 侧立换图取最新数据；落定揭示后仍有更新则自动补翻。
/// 减弱动态时直接换图不做过渡。
struct ArtworkFlipTransitionView: View {
    let data: Data?
    let fallbackSystemName: String
    let size: CGFloat
    var height: CGFloat?
    var cornerRadius: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 当前展示的封面数据；nil 表示尚未翻转过、直接跟随 `data`。
    @State private var displayedData: Data?
    /// 最新的封面数据（翻转进行中到达的新封面也持续更新到这里）。
    @State private var latestData: Data?
    /// 累计翻转角（每次切歌 ±180°，不归零；镜像校正按归一化角判定）。
    @State private var flipAngle: Double = 0
    /// 背面阶段给新封面加高斯模糊，落定揭示阶段动画退散。
    @State private var isBlurred = false
    @State private var flipTask: Task<Void, Never>?

    var body: some View {
        ArtworkView(
            data: displayedData ?? latestData ?? data,
            fallbackSystemName: fallbackSystemName,
            size: size,
            height: height,
            cornerRadius: cornerRadius
        )
        .blur(radius: isBlurred ? 12 : 0)
        .rotation3DEffect(
            .degrees(flipAngle),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.65
        )
        .scaleEffect(x: mirrorScale, y: 1)
        .onChange(of: data) { _, newData in
            latestData = newData
            if reduceMotion {
                flipTask?.cancel()
                flipTask = nil
                displayedData = newData
                isBlurred = false
            } else {
                runFlip()
            }
        }
        .onDisappear {
            flipTask?.cancel()
            flipTask = nil
        }
    }

    /// 背面阶段（归一化角 90°~270°）镜像校正：单层背面内容是反的，
    /// 屏幕空间水平镜像让背面封面保持正向；90°/270° 侧立瞬间切换不可见。
    private var mirrorScale: CGFloat {
        var value = flipAngle.truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return (value > 90 && value < 270) ? -1 : 1
    }

    /// 翻转进行中（flipTask 非空）到达的新封面只更新 `latestData`：
    /// 90° 侧立换图时取最新值；若落定揭示后仍有更新，自动补一次翻转。
    private func runFlip() {
        guard flipTask == nil else { return }
        displayedData = displayedData ?? latestData ?? data

        flipTask = Task {
            // 整张封面转 180°（中点恰为 90° 侧立，easeInOut 对称）。
            withAnimation(.easeInOut(duration: 0.45)) {
                flipAngle += 180
            }
            try? await Task.sleep(for: .milliseconds(225))
            guard !Task.isCancelled else { return }

            // 侧立瞬间：换最新封面并施加模糊（无动画，侧立态不可见）。
            displayedData = latestData
            isBlurred = true
            try? await Task.sleep(for: .milliseconds(225))
            guard !Task.isCancelled else { return }

            // 落定揭示：模糊渐渐消散，清晰真封面原地显现。
            withAnimation(.easeOut(duration: 0.30)) {
                isBlurred = false
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            flipTask = nil

            // 翻转揭示期间又有新封面到达：自动补一次翻转，而不是瞬间跳变。
            if latestData != displayedData {
                runFlip()
            }
        }
    }
}
