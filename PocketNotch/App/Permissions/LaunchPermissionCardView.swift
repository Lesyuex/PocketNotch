import AppKit
import Combine
import PocketNotchCore
import MediaModule
import SwiftUI

/// 启动引导的 335×500 玻璃卡片：挑选要启用的灵动功能后进入 App。
/// 系统权限不在启动时校验/申请，改为在岛上真正用到对应功能时才按需申请。
struct LaunchPermissionCardView: View {
    @ObservedObject var featureCoordinator: PermissionCoordinator
    let onFinish: () -> Void
    let onQuit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isPresented = false


    private enum Layout {
        static let width: CGFloat = 335
        static let height: CGFloat = 500
        static let cornerRadius: CGFloat = 24
        static let horizontalPadding: CGFloat = 30
        static let verticalPadding: CGFloat = 36
        static let rowMinHeight: CGFloat = 46
        static let rowIconSize: CGFloat = 30
        static let rowIconCornerRadius: CGFloat = 9
        static let rowIconSymbolSize: CGFloat = 16
    }

    private enum Typography {
        static let headline: Font = .system(size: 17, weight: .bold)
        static let subtitle: Font = .system(size: 11, weight: .regular)
        static let rowTitle: Font = .system(size: 12, weight: .semibold)
        static let rowSubtitle: Font = .system(size: 10, weight: .regular)
        static let status: Font = .system(size: 11, weight: .medium)
        static let badge: Font = .system(size: 9, weight: .semibold)
        static let guidance: Font = .system(size: 10, weight: .medium)
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
    }


    var body: some View {
        VStack(spacing: 0) {
            featuresPage
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .frame(width: Layout.width, height: Layout.height)
        .background { panelBackground }
        .clipShape(panelShape)
        .contentShape(panelShape)

        .opacity(isPresented ? 1 : 0)
        .scaleEffect(isPresented ? 1 : 0.985)
        .onAppear {
            if reduceMotion {
                isPresented = true
            } else {
                withAnimation(.spring(response: 0.34, dampingFraction: 1)) {
                    isPresented = true
                }
            }
        }

    }

    // MARK: - 灵动功能选择

    private var featuresPage: some View {
        VStack(spacing: 0) {
            header(title: "选择灵动功能", subtitle: "挑选上岛的功能，之后可在设置中调整")

            Spacer(minLength: 12)

            VStack(spacing: 10) {
                guidanceArea(featureCoordinator.guidance)
                featureList
                    .padding(.bottom, 10)
                footer(
                    leftTitle: "退出",
                    leftAction: onQuit,
                    rightTitle: "开始",
                    rightAction: onFinish
                )
            }
        }
    }

    private var featureList: some View {
        VStack(spacing: 4) {
            ForEach(featureCoordinator.features) { feature in
                featureRow(feature)
            }
        }
    }

    private func rowTile(
        symbol: String,
        palette: (foreground: Color, background: Color)
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: Layout.rowIconSymbolSize, weight: .semibold))
            .foregroundStyle(palette.foreground)
            .frame(width: Layout.rowIconSize, height: Layout.rowIconSize)
            .background {
                RoundedRectangle(cornerRadius: Layout.rowIconCornerRadius, style: .continuous)
                    .fill(palette.background)
                    .opacity(0.92)
            }
    }

    private func featureRow(_ feature: PermissionCoordinator.Feature) -> some View {
        HStack(alignment: .center, spacing: 10) {
            rowTile(symbol: feature.symbol, palette: accentTilePalette)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(Typography.rowTitle)
                    .foregroundStyle(.white)

                Text(feature.subtitle)
                    .font(Typography.rowSubtitle)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { feature.isOn },
                set: { featureCoordinator.setEnabled(feature.id, $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
            .opacity(0.65)
        }
        .frame(maxWidth: .infinity, minHeight: Layout.rowMinHeight)
        .contentShape(Rectangle())
    }

    // MARK: - 通用区块

    private func header(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 52, height: 52)
                .shadow(color: Color(red: 0.10, green: 0.39, blue: 0.86).opacity(0.16), radius: 12, y: 4)

            Text(title)
                .font(Typography.headline)
                .foregroundStyle(.white)

            Text(subtitle)
                .font(Typography.subtitle)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func guidanceArea(_ text: String?) -> some View {
        if let text {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(Typography.guidance)
                .foregroundStyle(Color(red: 1.0, green: 0.88, blue: 0.56))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.12))
                }
        }
    }

    private func footer(
        leftTitle: String,
        leftAction: @escaping () -> Void,
        rightTitle: String,
        rightAction: @escaping () -> Void,
        rightDisabled: Bool = false
    ) -> some View {
        HStack {
            Button {
                leftAction()
            } label: {
                Text(leftTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(minWidth: 54, minHeight: 26)
                    .contentShape(Rectangle())
                    .background { glassButtonBackground(cornerRadius: 9) }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Button {
                rightAction()
            } label: {
                Text(rightTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 54, minHeight: 26)
                    .contentShape(Rectangle())
                    .background { glassButtonBackground(cornerRadius: 9) }
            }
            .buttonStyle(.plain)
            .disabled(rightDisabled)
            .opacity(rightDisabled ? 0.35 : 1)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Material

    /// 与设置中心同一套材质决策：优先液态玻璃（regular），系统不支持时回退毛玻璃。
    @ViewBuilder
    private var panelBackground: some View {
        if reduceTransparency {
            ZStack {
                panelShape.fill(.regularMaterial)
            }
            .overlay {
                panelShape.strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            }
        } else {
            // regular 液态玻璃；SystemLiquidBackdrop 内部在系统不支持时回退毛玻璃。
            // 叠一层深色底板，避免液态玻璃通透度过高导致面板看起来透明。
            ZStack {
                SystemLiquidBackdrop(cornerRadius: Layout.cornerRadius, opacity: 0.6)
                panelShape.fill(.black.opacity(0.5))
            }
            .clipShape(panelShape)
            .overlay {
                panelShape.strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func glassButtonBackground(cornerRadius: CGFloat) -> some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.white.opacity(0.2))
        } else {
            SystemLiquidBackdrop(cornerRadius: cornerRadius, opacity: 0.6)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// 全卡片统一的行瓦片：极淡半透明白底 + 亮蓝符号（暗色玻璃卡上不跳色）。
    private var accentTilePalette: (foreground: Color, background: Color) {
        (
            Color(red: 0.42, green: 0.72, blue: 1.0),
            Color.white.opacity(0.12)
        )
    }
}