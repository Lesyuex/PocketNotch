import AppKit
import PocketNotchShared
import PocketNotchCore
import SwiftUI

/// 「此刻」页系统状态卡右侧的快速小卡盒：最多 4 张 44×34 背板呈 2×2 网格，
/// 数据取自系统「最近使用的文件夹」；四张卡样式统一。
///
/// 术语：彩色卡叫「背板」；背板底部叠的同宽色条叫「盖板」（高 32，与背板底边对齐）。
/// 背板上叠 1 张居中白色文件卡，底部伸入盖板；盖板上承载文件夹名。
/// 每张背板左上角至 20/56 处顶边上抬 4pt、由曲线在 28/56 处回落，呈「左上凸」折角。
struct NowQuickStatsCardView: View {
    let viewModel: RecentFoldersViewModel

    var body: some View {
        let cards = Array(viewModel.folders.prefix(Design.cellCount))
        VStack(spacing: Design.rowGap) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: Design.columnGap) {
                    ForEach(0..<2, id: \.self) { column in
                        let index = row * 2 + column
                        if index < cards.count {
                            let folder = cards[index]
                            QuickStatsCardButton {
                                NSWorkspace.shared.open(folder.url)
                            } label: { isHovering in
                                backplate(folder: folder, isHovered: isHovering)
                                    .overlay(alignment: .topTrailing) {
                                        if viewModel.isLocked(folder) {
                                            lockBadge
                                        }
                                    }
                            }
                            .help(String(format: L10n.tr("folders.openInFinderHelp"), folder.name))
                            .contextMenu {
                                Button("folders.openInFinder") {
                                    NSWorkspace.shared.open(folder.url)
                                }
                                Divider()
                                Button(viewModel.isLocked(folder) ? "folders.unlock" : "folders.lock") {
                                    viewModel.toggleLocked(folder)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(
            width: IslandLayoutToken.expandedNowPageQuickStatsCardWidth,
            height: IslandLayoutToken.expandedNowPageCardHeight,
            alignment: .center
        )
        .accessibilityElement(children: .ignore)
    }

    /// 一块「背板」：左上凸折角的 52×40 色卡 + 居中白色文件卡 + 底部盖板；四张卡样式统一。
    @ViewBuilder
    private func backplate(folder: RecentFolder, isHovered: Bool) -> some View {
        let shape = RaisedTopLeftRect(
            cornerRadius: Design.cellCornerRadius,
            raisedEndFraction: Design.raisedEndFraction,
            curveEndFraction: Design.curveEndFraction,
            raise: Design.raise
        )
        ZStack {
            shape
                .fill(Design.backplateColor)
                .brightness(isHovered ? Design.hoverBrightness : 0)
                .overlay {
                    shape.stroke(
                        .white.opacity(Design.cellBorderOpacity),
                        lineWidth: 1
                    )
                }

            fileCard()
                .padding(.top, isHovered ? Design.fileCardHoverInset : Design.fileCardTopInset)
                .frame(width: Design.cellWidth, height: Design.cellHeight, alignment: .top)

            coverShape
                .fill(Design.coverColor)
                .overlay {
                    coverShape.strokeBorder(
                        .white.opacity(Design.coverBorderOpacity),
                        lineWidth: 0.5
                    )
                }
                .overlay {
                    fileInfoRow(folder.name)
                }
                .frame(width: Design.cellWidth, height: Design.coverHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: Design.cellWidth, height: Design.cellHeight)
        .mask(shape)
    }

    private func fileCard() -> some View {
        RoundedRectangle(cornerRadius: Design.fileCardCornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Design.fileCardTopColor, Design.fileCardBottomColor],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: Design.fileCardCornerRadius, style: .continuous)
                    .strokeBorder(Design.fileCardBorderColor, lineWidth: 0.5)
            }
            .frame(width: Design.fileCardWidth, height: Design.fileCardHeight)
    }

    /// 「盖板」形状：与背板同宽、高 28，顶部圆角 6、底部圆角 6。
    private var coverShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: Design.coverTopCornerRadius,
            bottomLeadingRadius: Design.coverCornerRadius,
            bottomTrailingRadius: Design.coverCornerRadius,
            topTrailingRadius: Design.coverTopCornerRadius,
            style: .continuous
        )
    }

    /// 文件信息行：文件夹名，居中于盖板，最多两行，超出省略号（不缩放）。
    private func fileInfoRow(_ name: String) -> some View {
        Text(name)
            .font(.system(size: Design.infoTitleSize, weight: .semibold, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [Design.infoTitleTopColor, Design.infoTitleBottomColor],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .opacity(Design.infoTitleOpacity)
            .lineLimit(1)
            .truncationMode(.tail)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Design.infoHorizontalInset)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(maxHeight: .infinity, alignment: .center)
    }

    /// 锁定角标：右上角的小钥匙，指示该文件夹已被锁定、不再随最近使用次序漂移。
    private var lockBadge: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(2.5)
            .background {
                Circle().fill(.black.opacity(0.3))
            }
            .padding(.top, 1)
            .padding(.trailing, 2)
    }
}

/// 快速小卡盒的单张卡：悬停投影 + 手型指针 + 触觉震动，按下轻微缩小。
/// 不使用系统默认按钮样式，避免点击时背板/盖板颜色被 pressed 高亮改变。
private struct QuickStatsCardButton<Label: View>: View {
    let action: () -> Void
    let label: (Bool) -> Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    init(action: @escaping () -> Void, @ViewBuilder label: @escaping (Bool) -> Label) {
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            label(isHovering)
                .scaleEffect(isHovering ? Design.hoverScale : 1.0, anchor: .bottom)
                .shadow(
                    color: .black.opacity(isHovering ? Design.hoverShadowOpacity : 0),
                    radius: isHovering ? Design.hoverShadowRadius : 0,
                    y: isHovering ? Design.hoverShadowY : 0
                )
        }
        .buttonStyle(PressScaleButtonStyle(reduceMotion: reduceMotion))
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .alignment,
                    performanceTime: .now
                )
            } else {
                NSCursor.pop()
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 1.0),
            value: isHovering
        )
    }
}

/// 按下时轻微缩小并微暗，松开回弹；不改变标签颜色构图。
private struct PressScaleButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? Design.pressDimBrightness : 0)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

/// 直角矩形变体：左上角至 `raisedEndFraction × 宽` 的一段顶边整段上抬 `raise`，
/// 再由该处沿平滑曲线过渡到 `curveEndFraction × 宽` 处回落至水平顶边；
/// 其余三角为小圆角，整体是一个左上角向上凸起的圆角矩形。
private struct RaisedTopLeftRect: Shape {
    let cornerRadius: CGFloat
    let raisedEndFraction: CGFloat
    let curveEndFraction: CGFloat
    let raise: CGFloat

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let r = cornerRadius
        let raisedEnd = width * raisedEndFraction
        let curveEnd = width * curveEndFraction
        let transition = (curveEnd - raisedEnd) / 2

        var path = Path()
        path.move(to: CGPoint(x: 0, y: -raise + r))
        path.addArc(
            center: CGPoint(x: r, y: -raise + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(-90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: raisedEnd, y: -raise))
        path.addCurve(
            to: CGPoint(x: curveEnd, y: 0),
            control1: CGPoint(x: raisedEnd + transition, y: -raise),
            control2: CGPoint(x: curveEnd - transition, y: 0)
        )
        path.addLine(to: CGPoint(x: width - r, y: 0))
        path.addArc(
            center: CGPoint(x: width - r, y: r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: width, y: height - r))
        path.addArc(
            center: CGPoint(x: width - r, y: height - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: r, y: height))
        path.addArc(
            center: CGPoint(x: r, y: height - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private enum Design {
    static let cellCount = 4
    static let cellWidth: CGFloat = 44
    static let cellHeight: CGFloat = 34
    static let cellCornerRadius: CGFloat = 4
    static let raisedEndFraction: CGFloat = 20 / 56
    static let curveEndFraction: CGFloat = 28 / 56
    static let raise: CGFloat = 4
    static let columnGap: CGFloat = 18
    static let rowGap: CGFloat = 18
    static let cellBorderOpacity: Double = 0.08
    static let backplateColor: Color = Color(hex: 0x40A5D4)
    static let coverColor: Color = Color(hex: 0x4FAFDB)
    static let hoverBrightness: Double = 0.07
    static let pressDimBrightness: Double = -0.05
    static let hoverScale: CGFloat = 1.04
    static let hoverShadowOpacity: Double = 0.16
    static let hoverShadowRadius: CGFloat = 4
    static let hoverShadowY: CGFloat = 2
    static let coverHeight: CGFloat = 28
    static let coverCornerRadius: CGFloat = 6
    static let coverTopCornerRadius: CGFloat = 6
    static let coverBorderOpacity: Double = 0.35

    static let fileCardWidth: CGFloat = 38
    static let fileCardHeight: CGFloat = 24
    static let fileCardTopInset: CGFloat = 3
    static let fileCardHoverInset: CGFloat = 2.5
    static let fileCardCornerRadius: CGFloat = 4
    /// 纯白文件卡在蓝底上过于刺眼；改为偏冷灰白的竖向渐变，底部略暗显厚度。
    static let fileCardTopColor: Color = Color(hex: 0xF4F9FC)
    static let fileCardBottomColor: Color = Color(hex: 0xD3E4EF)
    static let fileCardBorderColor: Color = Color(hex: 0xFFFFFF).opacity(0.7)

    static let infoTitleSize: CGFloat = 8.5
    static let infoHorizontalInset: CGFloat = 4
    static let infoTitleOpacity: Double = 0.95
    /// 盖板是浅蓝，纯白对比不足、深色又突兀；取偏冷的灰白，比盖板明显更亮但不带彩色。
    static let infoTitleTopColor: Color = Color(hex: 0xF2F7FA)
    static let infoTitleBottomColor: Color = Color(hex: 0xC9DCE8)
}

/// 十六进制整数转 Color（如 0x66BEFF → #66BEFF）。
private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
