import AppKit
import SwiftUI

struct MediaLaunchableArtwork: View {
    var viewModel: NowPlayingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    let fallbackSystemName: String
    let size: CGFloat
    var height: CGFloat?
    var cornerRadius: CGFloat = 8
    var borderColor: Color = .white.opacity(0.08)
    var borderWidth: CGFloat = 1
    var applicationBadgeOffset: CGFloat = 7
    var applicationBadgeSize: CGFloat?
    var showsApplicationBadge = true
    var overlayContent: AnyView? = nil
    private let hoverScale: CGFloat = 1.018

    private var renderedHeight: CGFloat { height ?? size }

    var body: some View {
        launchButton
            .scaleEffect(isHovering && !reduceMotion ? hoverScale : 1)
            .frame(width: size, height: renderedHeight)
            .contentShape(Rectangle().inset(by: -8))
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isHovering = true
                case .ended:
                    isHovering = false
                }
            }
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.34, dampingFraction: 0.9, blendDuration: 0.08),
                value: isHovering
            )
            .help("打开当前媒体应用")
            .accessibilityLabel("打开当前媒体应用")
    }

    private var launchButton: some View {
        Button(action: viewModel.openCurrentMediaApplication) {
            ZStack(alignment: .bottomTrailing) {
                ArtworkView(
                    data: viewModel.displayArtwork,
                    fallbackSystemName: fallbackSystemName,
                    size: size,
                    height: renderedHeight,
                    cornerRadius: cornerRadius,
                    maximumTransformScale: hoverScale
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: borderWidth)
                        .allowsHitTesting(false)
                }
                if showsApplicationBadge,
                   !viewModel.isUsingAppIconFallback,
                   let iconData = viewModel.sourceApplicationIcon {
                    MediaApplicationBadge(
                        iconData: iconData,
                        size: applicationBadgeSize ?? min(max(size * 0.22, 26), 30)
                    )
                        .equatable()
                        .offset(x: applicationBadgeOffset, y: applicationBadgeOffset)
                        .allowsHitTesting(false)
                }

                if let overlayContent {
                    overlayContent
                }
            }
        }
        .buttonStyle(MediaArtworkLaunchButtonStyle())
        .contentShape(Rectangle().inset(by: -8))
    }

}

private struct MediaApplicationBadge: View, Equatable {
    let iconData: Data
    let size: CGFloat

    var body: some View {
        if let icon = NSImage(data: iconData) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .scaleEffect(1.23)
                .frame(width: size, height: size)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: size * 0.22,
                        style: .continuous
                    ).inset(by: 0.5)
                )
                .shadow(color: .black.opacity(0.28), radius: 5, y: 3)
        }
    }
}

private struct MediaArtworkLaunchButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 1),
                value: configuration.isPressed
            )
    }
}
