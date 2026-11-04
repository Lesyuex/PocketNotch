import PocketNotchCore
import SceneKit
import SwiftUI

private final class CompactTransparentSCNView: SCNView {
    override var isOpaque: Bool { false }
}

private struct AirPodsCompactUSDSceneView: NSViewRepresentable {
    let isActive: Bool
    let reduceMotion: Bool
    private let rotationActionKey = "airpods-compact-horizontal-rotation"

    func makeNSView(context: Context) -> SCNView {
        let view = CompactTransparentSCNView(frame: .zero)
        configureTransparency(for: view)
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = true
        view.preferredFramesPerSecond = DisplayRefreshRateMonitor.shared.preferredFramesPerSecond
        view.rendersContinuously = false
        view.scene = AirPodsModelSceneFactory.makeScene(presentation: .notificationPair)
        view.scene?.background.contents = NSColor.clear
        view.pointOfView = view.scene?.rootNode.childNode(
            withName: AirPodsModelSceneFactory.cameraNodeName,
            recursively: true
        )
        updateAnimation(for: view)
        return view
    }

    static func dismantleNSView(_ view: SCNView, coordinator: Void) {
        view.scene?.rootNode.removeAllActions()
        view.pointOfView = nil
        view.scene = nil
        view.isPlaying = false
    }

    func updateNSView(_ view: SCNView, context: Context) {
        configureTransparency(for: view)
        updateAnimation(for: view)
    }

    private func configureTransparency(for view: SCNView) {
        view.wantsLayer = true
        view.backgroundColor = .clear
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false
    }

    private func updateAnimation(for view: SCNView) {
        guard let pivot = view.scene?.rootNode.childNode(
            withName: AirPodsModelSceneFactory.pivotNodeName,
            recursively: true
        ) else {
            return
        }

        guard !reduceMotion else {
            pivot.removeAction(forKey: rotationActionKey)
            pivot.isPaused = false
            pivot.eulerAngles.y = 0
            return
        }

        guard isActive else {
            // 退场时冻结在当前可见角度，避免模型先瞬间回正再淡出。
            pivot.isPaused = true
            return
        }

        pivot.isPaused = false
        guard pivot.action(forKey: rotationActionKey) == nil else { return }

        let rotation = SCNAction.rotateBy(
            x: 0,
            y: CGFloat.pi * 2,
            z: 0,
            duration: AudioOutputDeviceSnapshot.airPodsProRotationDuration
        )
        pivot.runAction(.repeatForever(rotation), forKey: rotationActionKey)
    }
}

/// 在极小的 compact 前导视口内播放同一 USD 模型的 3D 旋转。
struct AirPodsSpatialIcon: View {
    private enum Motion {
        static let initialScale: CGFloat = 0.88
        static let initialOpacity = 1.0
        static let initialOffsetY: CGFloat = 2
        static let exitOffsetY: CGFloat = 1
        static let reveal = Animation.spring(response: 0.34, dampingFraction: 1)
    }

    let systemName: String
    let presentationKey: String
    let diameter: CGFloat
    let isDismissing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale = Motion.initialScale
    @State private var opacity = Motion.initialOpacity
    @State private var offsetY = Motion.initialOffsetY
    @State private var shadowScale: CGFloat = 0.68

    private var animationTaskID: String {
        "\(presentationKey)|\(systemName)|\(isDismissing)"
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(.black.opacity(0.28))
                .frame(width: diameter * 0.52, height: max(diameter * 0.075, 1.4))
                .blur(radius: diameter * 0.055)
                .scaleEffect(x: reduceMotion ? 0.88 : shadowScale, y: 1)
                .offset(y: diameter * 0.34)
                .opacity(reduceMotion ? 0.22 : opacity * 0.34)

            AirPodsCompactUSDSceneView(
                isActive: !isDismissing,
                reduceMotion: reduceMotion
            )
            .frame(width: diameter, height: diameter)
            .id(presentationKey)
            .scaleEffect(reduceMotion ? 1 : scale)
            .offset(y: reduceMotion ? 0 : offsetY)
            .opacity(isDismissing ? 0 : (reduceMotion ? 1 : opacity))
        }
        .frame(width: diameter, height: diameter, alignment: .leading)
        .task(id: animationTaskID) {
            if isDismissing {
                await animateExit()
            } else {
                await animateEntrance()
            }
        }
    }

    @MainActor
    private func animateEntrance() async {
        scale = Motion.initialScale
        opacity = 1
        offsetY = Motion.initialOffsetY
        shadowScale = 0.68

        guard !reduceMotion else {
            scale = 1
            opacity = 1
            offsetY = 0
            shadowScale = 0.88
            return
        }

        withAnimation(Motion.reveal) {
            scale = 1
            offsetY = 0
            shadowScale = 0.84
        }
    }

    @MainActor
    private func animateExit() async {
        if reduceMotion {
            withAnimation(PocketNotchTheme.islandReducedMotionAnimation) {
                opacity = 0
            }
            return
        }

        withAnimation(
            PocketNotchTheme.islandCompactModuleAnimation(
                isVisible: false,
                reduceMotion: false
            )
        ) {
            scale = 0.97
            opacity = 0
            offsetY = Motion.exitOffsetY
            shadowScale = 0.72
        }
    }
}
